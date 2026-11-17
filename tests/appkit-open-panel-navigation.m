// Copyright (C) 2026 Lubos Dolezel
//
// An open panel lets the user move between folders: double-click or Return on a folder enters it, a path pop-up
// above the list jumps to an ancestor, a sidebar lists Home, Documents and / among the favorites, Command-Shift-G
// asks for a folder to go to (a leading ~ is the home folder), Command-[ and Command-] go back and forward.
// The panel is driven the way a user does it: through its views, with synthesized mouse and key events. The
// documented API around it is checked too: directoryURL, the delegate's panel:shouldEnableURL: and
// panel:didChangeToDirectoryURL:, canChooseDirectories, allowedFileTypes, showsHiddenFiles, URLs, runModal and
// beginSheetModalForWindow:completionHandler:. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

@interface Delegate : NSObject {
@public
    NSMutableArray *events;
}
@end

@implementation Delegate
- (instancetype) init {
    if ((self = [super init]))
        events = [NSMutableArray new];
    return self;
}
- (BOOL) panel: (id) sender shouldEnableURL: (NSURL *) url {
    [events addObject: [@"enable " stringByAppendingString: [url lastPathComponent]]];
    return ![[url lastPathComponent] isEqual: @"vetoed.txt"];
}
- (void) panel: (id) sender didChangeToDirectoryURL: (NSURL *) url {
    [events addObject: [@"changed " stringByAppendingString: [url lastPathComponent]]];
}
@end

static BOOL contains(NSArray *events, NSString *e) {
    return [events containsObject: e];
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL same(NSURL *url, NSString *path) {
    return url != nil && [[[url path] stringByResolvingSymlinksInPath]
                                 isEqual: [path stringByResolvingSymlinksInPath]];
}

static void collect(NSView *view, Class cls, NSMutableArray *out) {
    if ([view isKindOfClass: cls])
        [out addObject: view];
    for (NSView *sub in [view subviews])
        collect(sub, cls, out);
}

static NSArray *viewsOf(NSWindow *window, Class cls) {
    NSMutableArray *out = [NSMutableArray array];
    collect([window contentView], cls, out);
    return out;
}

static NSOutlineView *listOf(NSWindow *panel) {
    return [viewsOf(panel, [NSOutlineView class]) firstObject];
}

static NSTableView *sidebarOf(NSWindow *panel) {
    for (NSTableView *table in viewsOf(panel, [NSTableView class]))
        if (![table isKindOfClass: [NSOutlineView class]])
            return table;
    return nil;
}

static NSPopUpButton *popUpOf(NSWindow *panel) {
    return [viewsOf(panel, [NSPopUpButton class]) firstObject];
}

static NSButton *buttonTitled(NSWindow *window, NSString *title) {
    for (NSButton *button in viewsOf(window, [NSButton class]))
        if ([[button title] isEqual: title])
            return button;
    return nil;
}

static NSArray *rowNames(NSOutlineView *list) {
    NSMutableArray *names = [NSMutableArray array];
    for (NSInteger row = 0; row < [list numberOfRows]; row++)
        [names addObject: [[list itemAtRow: row] lastPathComponent]];
    return names;
}

static NSInteger rowNamed(NSOutlineView *list, NSString *name) {
    return [rowNames(list) indexOfObject: name] == NSNotFound
                   ? -1 : (NSInteger) [rowNames(list) indexOfObject: name];
}

// A click on a row of a table, as the window server would deliver it.
static void clickRow(NSWindow *panel, NSTableView *table, NSInteger row, NSInteger clickCount) {
    NSRect rect = [table rectOfRow: row];
    NSPoint point = [table convertPoint: NSMakePoint(NSMinX(rect) + 20, NSMidY(rect)) toView: nil];
    NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: point modifierFlags: 0
                                    timestamp: 0 windowNumber: [panel windowNumber] context: nil
                                  eventNumber: 0 clickCount: clickCount pressure: 0];
    NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: [panel windowNumber] context: nil
                                    eventNumber: 0 clickCount: clickCount pressure: 1];
    [NSApp postEvent: up atStart: NO];
    [panel sendEvent: down];
    spin(0.2);
}

static void doubleClickRow(NSWindow *panel, NSTableView *table, NSInteger row) {
    clickRow(panel, table, row, 1);
    clickRow(panel, table, row, 2);
}

static void pressKey(NSWindow *panel, NSString *chars, NSString *plain, NSUInteger flags) {
    NSEvent *event = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: flags
                                     timestamp: 0 windowNumber: [panel windowNumber] context: nil
                                    characters: chars charactersIgnoringModifiers: plain
                                     isARepeat: NO keyCode: 0];
    [panel sendEvent: event];
    spin(0.2);
}

static void goToFolder(NSWindow *panel, NSString *typed, BOOL confirm) {
    pressKey(panel, @"G", @"g", NSCommandKeyMask | NSShiftKeyMask);
    NSWindow *sheet = [panel attachedSheet];
    CHECK(sheet != nil);
    if (sheet == nil)
        return;
    NSTextField *field = nil;
    for (NSTextField *candidate in viewsOf(sheet, [NSTextField class]))
        if ([candidate isEditable])
            field = candidate;
    CHECK(field != nil);
    [field setStringValue: typed];
    [(confirm ? buttonTitled(sheet, @"Go") : buttonTitled(sheet, @"Cancel")) performClick: nil];
    spin(0.3);
}

static void makeFile(NSString *path) {
    [@"x" writeToFile: path atomically: NO encoding: NSUTF8StringEncoding error: nil];
}

static NSString *quirk(NSOutlineView *list, NSString *name) {
    // whether the panel lets the user select the entry: its delegate's answer
    NSInteger row = rowNamed(list, name);
    if (row < 0)
        return @"missing";
    id delegate = [list delegate];
    return [delegate respondsToSelector: @selector(outlineView:shouldSelectItem:)] &&
                           ![delegate outlineView: list shouldSelectItem: [list itemAtRow: row]]
                   ? @"disabled" : @"enabled";
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [[NSTemporaryDirectory() stringByResolvingSymlinksInPath]
                stringByAppendingPathComponent: [NSString stringWithFormat: @"openpanel-nav-%d", getpid()]];
        NSString *sub = [root stringByAppendingPathComponent: @"sub"];
        NSString *deep = [sub stringByAppendingPathComponent: @"deep"];
        [fm createDirectoryAtPath: deep withIntermediateDirectories: YES attributes: nil error: nil];
        makeFile([root stringByAppendingPathComponent: @"a.txt"]);
        makeFile([root stringByAppendingPathComponent: @"b.png"]);
        makeFile([root stringByAppendingPathComponent: @"vetoed.txt"]);
        makeFile([root stringByAppendingPathComponent: @".hidden"]);
        makeFile([sub stringByAppendingPathComponent: @"inner.txt"]);
        NSURL *rootURL = [NSURL fileURLWithPath: root isDirectory: YES];

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        Delegate *delegate = [Delegate new];
        [panel performSelector: @selector(setDelegate:) withObject: delegate];
        [panel setDirectoryURL: rootURL];
        [panel setAllowedFileTypes: @[ @"txt" ]];
        CHECK(same([panel directoryURL], root));

        __block NSInteger result = -1;
        [panel beginWithCompletionHandler: ^(NSModalResponse r) { result = r; }];
        spin(0.5);

        // what the list shows: this folder, hidden files left out, entries offered to the delegate
        NSOutlineView *list = listOf(panel);
        CHECK(list != nil);
        if (list == nil) {
            puts("FAIL: no file list");
            return 1;
        }
        NSArray *names = rowNames(list);
        CHECK([names isEqual: @[ @"a.txt", @"b.png", @"sub", @"vetoed.txt" ]]);
        CHECK(contains(delegate->events, @"enable a.txt") && contains(delegate->events, @"enable sub"));
        // Files of another type, and the ones the delegate vetoes, can't be selected; folders can.
        CHECK([quirk(list, @"a.txt") isEqual: @"enabled"]);
        CHECK([quirk(list, @"b.png") isEqual: @"disabled"]);
        CHECK([quirk(list, @"vetoed.txt") isEqual: @"disabled"]);
        CHECK([quirk(list, @"sub") isEqual: @"enabled"]);

        [panel setShowsHiddenFiles: YES];
        CHECK([rowNames(list) containsObject: @".hidden"]);
        [panel setShowsHiddenFiles: NO];
        CHECK(![rowNames(list) containsObject: @".hidden"]);

        // double-click on a folder enters it
        [delegate->events removeAllObjects];
        doubleClickRow(panel, list, rowNamed(list, @"sub"));
        CHECK(same([panel directoryURL], sub));
        CHECK([rowNames(list) isEqual: @[ @"deep", @"inner.txt" ]]);
        CHECK(contains(delegate->events, @"changed sub"));
        CHECK(result == -1);

        // path pop-up: the folder, then its ancestors up to /
        NSPopUpButton *popUp = popUpOf(panel);
        CHECK(popUp != nil);
        if (popUp != nil) {
            CHECK([[popUp titleOfSelectedItem] isEqual: @"sub"]);
            CHECK([[popUp itemTitles] containsObject: [root lastPathComponent]]);
            CHECK([[[popUp itemTitles] lastObject] isEqual: @"/"]);
            [popUp selectItemAtIndex: 1];
            [popUp sendAction: [popUp action] to: [popUp target]];
            spin(0.2);
            CHECK(same([panel directoryURL], root));
            CHECK([rowNames(list) containsObject: @"sub"]);
        }

        // sidebar favorites
        NSTableView *sidebar = sidebarOf(panel);
        CHECK(sidebar != nil);
        if (sidebar != nil) {
            NSMutableArray *titles = [NSMutableArray array];
            for (NSInteger row = 0; row < [sidebar numberOfRows]; row++)
                [titles addObject: [[sidebar dataSource] tableView: sidebar
                                         objectValueForTableColumn: [[sidebar tableColumns] firstObject]
                                                               row: row]];
            CHECK([titles containsObject: NSUserName()]);
            CHECK([titles containsObject: @"/"]);
            clickRow(panel, sidebar, [titles indexOfObject: @"/"], 1);
            CHECK(same([panel directoryURL], @"/"));
            if ([titles containsObject: @"Applications"] || [fm fileExistsAtPath: @"/Applications"]) {
                CHECK([titles containsObject: @"Applications"]);
                clickRow(panel, sidebar, [titles indexOfObject: @"Applications"], 1);
                CHECK(same([panel directoryURL], @"/Applications"));
            }
            clickRow(panel, sidebar, [titles indexOfObject: NSUserName()], 1);
            CHECK(same([panel directoryURL], NSHomeDirectory()));
        }

        // Go to Folder: a typed path, ~, and a path that does not exist
        goToFolder(panel, root, YES);
        CHECK(same([panel directoryURL], root));
        CHECK([panel attachedSheet] == nil);
        goToFolder(panel, @"~", YES);
        CHECK(same([panel directoryURL], NSHomeDirectory()));
        goToFolder(panel, [root stringByAppendingPathComponent: @"nonexistent"], YES);
        CHECK(same([panel directoryURL], NSHomeDirectory()));
        CHECK([panel attachedSheet] != nil); // still asking
        [buttonTitled([panel attachedSheet], @"Cancel") performClick: nil];
        spin(0.3);
        CHECK([panel attachedSheet] == nil);
        goToFolder(panel, sub, YES);
        CHECK(same([panel directoryURL], sub));

        // back, forward and the enclosing folder from the keyboard
        pressKey(panel, @"[", @"[", NSCommandKeyMask);
        CHECK(same([panel directoryURL], NSHomeDirectory()));
        pressKey(panel, @"]", @"]", NSCommandKeyMask);
        CHECK(same([panel directoryURL], sub));
        pressKey(panel, [NSString stringWithFormat: @"%C", (unichar) NSUpArrowFunctionKey],
                 [NSString stringWithFormat: @"%C", (unichar) NSUpArrowFunctionKey], NSCommandKeyMask);
        CHECK(same([panel directoryURL], root));

        // Open on a selected folder enters it, as canChooseDirectories is NO
        [list selectRowIndexes: [NSIndexSet indexSetWithIndex: rowNamed(list, @"sub")] byExtendingSelection: NO];
        [buttonTitled(panel, @"Open") performClick: nil];
        spin(0.2);
        CHECK(same([panel directoryURL], sub));
        CHECK(result == -1 && [[panel URLs] count] == 0);

        // Open on a selected file accepts it
        [list selectRowIndexes: [NSIndexSet indexSetWithIndex: rowNamed(list, @"inner.txt")]
          byExtendingSelection: NO];
        [buttonTitled(panel, @"Open") performClick: nil];
        spin(0.3);
        CHECK(result == NSModalResponseOK);
        CHECK([[panel URLs] count] == 1 &&
              same([[panel URLs] firstObject], [sub stringByAppendingPathComponent: @"inner.txt"]));

        // as a sheet, and run modally, with the folder entered by double-click first
        NSWindow *parent = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered defer: NO];
        [parent makeKeyAndOrderFront: nil];
        NSOpenPanel *sheetPanel = [NSOpenPanel openPanel];
        [sheetPanel setDirectoryURL: rootURL];
        [sheetPanel setCanChooseDirectories: YES];
        __block NSInteger sheetResult = -1;
        [sheetPanel beginSheetModalForWindow: parent
                           completionHandler: ^(NSModalResponse r) { sheetResult = r; }];
        spin(0.5);
        NSOutlineView *sheetList = listOf(sheetPanel);
        CHECK(sheetList != nil);
        if (sheetList != nil) {
            doubleClickRow(sheetPanel, sheetList, rowNamed(sheetList, @"sub"));
            CHECK(same([sheetPanel directoryURL], sub));
            CHECK(sheetResult == -1);
            // With canChooseDirectories a selected folder is chosen, not entered.
            [sheetList selectRowIndexes: [NSIndexSet indexSetWithIndex: rowNamed(sheetList, @"deep")]
                   byExtendingSelection: NO];
            [buttonTitled(sheetPanel, @"Open") performClick: nil];
            spin(0.3);
            CHECK(sheetResult == NSModalResponseOK);
            CHECK([[sheetPanel URLs] count] == 1 && same([[sheetPanel URLs] firstObject], deep));
        }
        [parent close];

        NSOpenPanel *modal = [NSOpenPanel openPanel];
        [modal setDirectoryURL: rootURL];
        NSTimer *driver = [NSTimer timerWithTimeInterval: 0.5 repeats: NO block: ^(NSTimer *t) {
            NSOutlineView *modalList = listOf(modal);
            doubleClickRow(modal, modalList, rowNamed(modalList, @"sub"));
            [modalList selectRowIndexes:
                    [NSIndexSet indexSetWithIndex: rowNamed(modalList, @"inner.txt")] byExtendingSelection: NO];
            [buttonTitled(modal, @"Open") performClick: nil];
        }];
        [[NSRunLoop currentRunLoop] addTimer: driver forMode: NSRunLoopCommonModes];
        NSInteger modalResult = [modal runModal];
        CHECK(modalResult == NSModalResponseOK);
        CHECK([[modal URLs] count] == 1 &&
              same([[modal URLs] firstObject], [sub stringByAppendingPathComponent: @"inner.txt"]));

        [fm removeItemAtPath: root error: nil];
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
