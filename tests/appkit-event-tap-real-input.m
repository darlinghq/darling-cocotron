// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// Real input of the window system goes through the event taps of the process before AppKit gets
// it, and AppKit's mouse events pass the Carbon handlers before -sendEvent:. An active tap in the
// process turns the key "a" into "b" and counts the key and mouse-down events it sees; a Carbon
// handler on the application target and an NSApplication subclass log the mouse-down. Driven by
// appkit-event-tap-real-input-x11.sh (XTest) and appkit-event-tap-real-input-wayland.sh (virtual
// keyboard and pointer): the program prints READY and the window's content frame, the harness types
// "a" and clicks in the window, and the program reports what arrived.
//
// Then a second part, with the tap still active, checks the order of real pointer input that piles
// up unread: the program prints PHASE2 and does not read events for two seconds; the harness
// moves the pointer twice, clicks, and moves it twice more. The program must get the moves before the click (their deltas
// summed into one or two events), the click at the position where it was made, and the moves after
// it, ending at the last position: a move is never merged into one that is before the click.
//
// Usage: appkit-event-tap-real-input (it waits at most 30 seconds for the input; no arguments,
// which -finishLaunching would take for documents to open)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <stdlib.h>

static int tapKeys, tapMouseDowns;
static NSMutableArray *mouseLog;
static NSString *typed;
static BOOL keyCGEventChanged, keyHasWindow, mouseHasWindow;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        UniChar chars[4];
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 4, &length, chars);
        if (length == 1 && chars[0] == 'a') {
            UniChar b = 'b';
            CGEventKeyboardSetUnicodeString(event, 1, &b);
            CGEventSetIntegerValueField(event, kCGKeyboardEventKeycode, kVK_ANSI_B);
            if (type == kCGEventKeyDown)
                tapKeys++;
        }
    } else if (type == kCGEventLeftMouseDown) {
        tapMouseDowns++;
    }
    return event;
}

static OSStatus mouseHandler(EventHandlerCallRef call, EventRef event, void *info) {
    [mouseLog addObject: @"carbon"];
    return eventNotHandledErr;
}

@interface TapApplication : NSApplication
@end

@implementation TapApplication
- (void) sendEvent: (NSEvent *) event {
    if ([event type] == NSEventTypeLeftMouseDown) {
        [mouseLog addObject: @"sendEvent"];
        mouseHasWindow = [event window] != nil;
    } else if ([event type] == NSEventTypeKeyDown && typed == nil) {
        typed = [[event characters] copy];
        keyHasWindow = [event window] != nil;
        keyCGEventChanged = [event CGEvent] != NULL &&
                CGEventGetIntegerValueField([event CGEvent], kCGKeyboardEventKeycode) == kVK_ANSI_B;
    }
    [super sendEvent: event];
}
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    double seconds = 30;
    mouseLog = [NSMutableArray new];
    [TapApplication sharedApplication];
    [NSApp finishLaunching];

    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventLeftMouseDown);
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask,
                                         tapCallback, NULL);
    if (tap == NULL) {
        printf("FAIL no event tap\n");
        return 1;
    }
    CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(tap, true);

    EventTypeSpec spec = {kEventClassMouse, kEventMouseDown};
    InstallEventHandler(GetApplicationEventTarget(), mouseHandler, 1, &spec, NULL, NULL);

    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 400, 300)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: @"tap-real-input"];
    [window setAcceptsMouseMovedEvents: YES];
    [window center];
    [window makeKeyAndOrderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];

    // Where the harness clicks: the middle of the content, in screen coordinates with the origin at
    // the top left (where the window system put the window may differ; the harness also asks it)
    NSRect content = [window contentRectForFrameRect: [window frame]];
    CGFloat top = NSMaxY([[[NSScreen screens] objectAtIndex: 0] frame]);
    printf("CONTENT %d %d %d %d\n", (int) content.origin.x, (int) (top - NSMaxY(content)), (int) content.size.width,
           (int) content.size.height);
    printf("READY\n");
    fflush(stdout);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0 && (typed == nil || [mouseLog count] < 2)) {
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.25]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
        [inner release];
    }

    expect(tapKeys >= 1, [NSString stringWithFormat: @"the tap saw the real key press (%d)", tapKeys]);
    expect([typed isEqual: @"b"], [NSString stringWithFormat: @"AppKit got the key as the tap changed it (%@)", typed]);
    expect(keyCGEventChanged, @"  its -CGEvent is the changed one");
    expect(keyHasWindow, @"  and it belongs to the key window");
    expect(tapMouseDowns >= 1, [NSString stringWithFormat: @"the tap saw the real mouse-down (%d)", tapMouseDowns]);
    NSString *order = [mouseLog componentsJoinedByString: @","];
    expect([order hasPrefix: @"carbon,sendEvent"],
          [NSString stringWithFormat: @"the Carbon handler runs before -sendEvent: (%@)", order]);
    expect(mouseHasWindow, @"  the mouse-down belongs to the window");

    // Part two: real moves, a click and moves again, read only after they all arrived. The tap stays
    // active: it holds the mouse-down (it is in its mask) while the moves around it are not, and the
    // events must still come in the order they were made. The run loop runs meanwhile, which the
    // tap needs to get its events, but no event is read.
    printf("PHASE2\n");
    fflush(stdout);
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 2]];
    NSMutableArray *motion = [NSMutableArray array]; // "M x" / "D x" / "U x" in the order they arrive
    deadline = [NSDate dateWithTimeIntervalSinceNow: 4];
    NSTimeInterval quietUntil = 0; // reference time when the input has been quiet long enough
    while ([deadline timeIntervalSinceNow] > 0 && (quietUntil == 0 || [NSDate timeIntervalSinceReferenceDate] < quietUntil)) {
        NSAutoreleasePool *inner = [NSAutoreleasePool new];
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.25]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil) {
            NSEventType type = [event type];
            const char *name = type == NSEventTypeMouseMoved ? "M" : type == NSEventTypeLeftMouseDown ? "D" :
                               type == NSEventTypeLeftMouseUp ? "U" : NULL;
            if (name != NULL) {
                [motion addObject: [NSString stringWithFormat: @"%s %d", name, (int) [event locationInWindow].x]];
                quietUntil = [NSDate timeIntervalSinceReferenceDate] + 0.6;
            }
            [NSApp sendEvent: event];
        }
        [inner release];
    }
    NSString *seq = [motion componentsJoinedByString: @", "];
    // The click: first down, with the moves before it at x <= its x and the moves after it past it
    NSUInteger down = NSNotFound;
    int downX = 0, lastX = 0;
    for (NSUInteger i = 0; i < [motion count]; i++) {
        NSArray *parts = [[motion objectAtIndex: i] componentsSeparatedByString: @" "];
        if ([[parts objectAtIndex: 0] isEqual: @"D"] && down == NSNotFound) {
            down = i;
            downX = [[parts objectAtIndex: 1] intValue];
        }
    }
    BOOL before = down != NSNotFound && down >= 1, after = down != NSNotFound && down + 2 < [motion count];
    for (NSUInteger i = 0; down != NSNotFound && i < [motion count]; i++) {
        NSArray *parts = [[motion objectAtIndex: i] componentsSeparatedByString: @" "];
        int x = [[parts objectAtIndex: 1] intValue];
        if ([[parts objectAtIndex: 0] isEqual: @"M"]) {
            if (i < down && x > downX)
                before = NO;
            if (i > down && x <= downX)
                after = NO;
            lastX = x;
        }
    }
    expect(down != NSNotFound && [[motion lastObject] hasPrefix: @"M"] && before && after && lastX > downX,
          [NSString stringWithFormat: @"moves, click, moves arrive in that order at their positions (%@)", seq]);
    // Two moves each side could only merge into one each, so there are at most two before the click
    // and two after it (the click is followed by its release)
    expect(down != NSNotFound && down <= 2 && [motion count] - down - 2 <= 2,
          [NSString stringWithFormat: @"  and the moves on either side are merged, not duplicated (%@)", seq]);

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    fflush(stdout);
    [pool release];
    return failures ? 1 : 0;
}
