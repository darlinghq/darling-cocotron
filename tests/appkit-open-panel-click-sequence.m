// Copyright (C) 2026 Lubos Dolezel
//
// Clicks in an open panel's file list. The window system counts clicks at one place in quick succession: when a
// double-click enters a folder and the user double-clicks again at the same place of the new listing, the second
// double-click arrives as clicks 3 and 4. The listing was replaced in between, so those clicks are the first and
// second click on it: the second double-click must enter the next folder (the panel used to ignore clicks 3 and 4),
// and a third click right after a double-click enters nothing. Also: typing "/" or "~" with the list focused opens the
// Go to Folder sheet with that character in its field. The events are sent to the panel's window the way a window
// system delivers them, so this also runs on every window-system backend. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static void collect(NSView *view, Class cls, NSMutableArray *out) {
    if ([view isKindOfClass: cls])
        [out addObject: view];
    for (NSView *sub in [view subviews])
        collect(sub, cls, out);
}

static NSOutlineView *listOf(NSWindow *panel) {
    NSMutableArray *out = [NSMutableArray array];
    collect([panel contentView], [NSOutlineView class], out);
    return [out firstObject];
}

static void clickRow(NSWindow *panel, NSTableView *table, NSInteger row, NSInteger clickCount) {
    NSRect rect = [table rectOfRow: row];
    NSPoint point = [table convertPoint: NSMakePoint(NSMinX(rect) + 20, NSMidY(rect)) toView: nil];
    NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0 timestamp: 0
                                 windowNumber: [panel windowNumber] context: nil eventNumber: 0
                                   clickCount: clickCount pressure: 0];
    NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0 timestamp: 0
                                   windowNumber: [panel windowNumber] context: nil eventNumber: 0
                                     clickCount: clickCount pressure: 1];
    [NSApp postEvent: up atStart: NO];
    [panel sendEvent: down];
    spin(0.15);
}

static void typeKey(NSWindow *panel, NSString *chars) {
    NSEvent *event = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                  windowNumber: [panel windowNumber] context: nil characters: chars
                   charactersIgnoringModifiers: chars isARepeat: NO keyCode: 0];
    [panel sendEvent: event];
    spin(0.3);
}

static NSString *dirOf(NSOpenPanel *panel) {
    return [[[panel directoryURL] path] stringByResolvingSymlinksInPath];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *root = [[NSTemporaryDirectory() stringByResolvingSymlinksInPath]
                stringByAppendingPathComponent: [NSString stringWithFormat: @"openpanel-clicks-%d", getpid()]];
        NSString *dir = root;
        NSMutableArray *levels = [NSMutableArray arrayWithObject: root];
        for (int i = 0; i < 5; i++) {
            [[NSFileManager defaultManager] createDirectoryAtPath: [dir stringByAppendingPathComponent: @"a"]
                                      withIntermediateDirectories: YES attributes: nil error: nil];
            [@"x" writeToFile: [dir stringByAppendingPathComponent: @"b.txt"] atomically: NO
                     encoding: NSUTF8StringEncoding error: nil];
            dir = [dir stringByAppendingPathComponent: @"a"];
            [levels addObject: dir];
        }

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setDirectoryURL: [NSURL fileURLWithPath: root isDirectory: YES]];
        [panel beginWithCompletionHandler: ^(NSModalResponse r) {}];
        spin(0.5);
        NSOutlineView *list = listOf(panel);
        CHECK(list != nil);
        if (list == nil)
            return 1;
        CHECK([dirOf(panel) isEqual: levels[0]]);

        // a double-click enters the folder and leaves nothing selected in the new listing
        clickRow(panel, list, 0, 1);
        clickRow(panel, list, 0, 2);
        CHECK([dirOf(panel) isEqual: levels[1]]);
        CHECK([list numberOfSelectedRows] == 0);

        // the next double-click at the same place arrives as clicks 3 and 4
        clickRow(panel, list, 0, 3);
        clickRow(panel, list, 0, 4);
        CHECK([dirOf(panel) isEqual: levels[2]]);
        CHECK([list numberOfSelectedRows] == 0);

        // and again as clicks 5 and 6
        clickRow(panel, list, 0, 5);
        clickRow(panel, list, 0, 6);
        CHECK([dirOf(panel) isEqual: levels[3]]);

        // a third click right after a double-click is one click on the new listing: it enters nothing
        clickRow(panel, list, 0, 7);
        CHECK([dirOf(panel) isEqual: levels[3]]);

        // a new sequence (click count 1) after a pause is an ordinary double-click again
        clickRow(panel, list, 0, 1);
        clickRow(panel, list, 0, 2);
        CHECK([dirOf(panel) isEqual: levels[4]]);

        // typing "/" opens the Go to Folder sheet with the character in its field; "~" likewise; Cancel closes it
        for (NSString *typed in @[ @"/", @"~" ]) {
            [panel makeFirstResponder: list];
            typeKey(panel, typed);
            NSWindow *sheet = [panel attachedSheet];
            CHECK(sheet != nil);
            if (sheet == nil)
                continue;
            NSMutableArray *fields = [NSMutableArray array];
            collect([sheet contentView], [NSTextField class], fields);
            NSTextField *field = nil;
            for (NSTextField *candidate in fields)
                if ([candidate isEditable])
                    field = candidate;
            CHECK(field != nil && [[field stringValue] isEqual: typed]);
            NSMutableArray *buttons = [NSMutableArray array];
            collect([sheet contentView], [NSButton class], buttons);
            for (NSButton *button in buttons)
                if ([[button title] isEqual: @"Cancel"])
                    [button performClick: nil];
            spin(0.3);
            CHECK([panel attachedSheet] == nil);
        }
        // other characters do not open it
        typeKey(panel, @"x");
        CHECK([panel attachedSheet] == nil);

        [panel cancel: nil];
        spin(0.2);
        printf(failures ? "FAIL\n" : "PASS\n");
    }
    return failures ? 1 : 0;
}
