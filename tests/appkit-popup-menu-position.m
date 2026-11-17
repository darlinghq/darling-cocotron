// Copyright (C) 2026 Lubos Dolezel
//
// The menu of a pop-up button opens at the control: its left edge lines up with the control's left edge, it is
// at least as wide as the control, and for a pop-up (not pull-down) the selected item sits over the control, so the
// menu overlaps the control vertically. Checked for a button in a plain window and in the path pop-up of an open
// panel. The menu is opened with a mouse click and read while it is tracking. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSWindow *menuWindow(void) {
    for (NSWindow *window in [NSApp windows])
        if ([NSStringFromClass([window class]) isEqual: @"NSPopUpWindow"] && [window isVisible])
            return window;
    return nil;
}

static void collect(NSView *view, NSMutableArray *out) {
    if ([view isKindOfClass: [NSPopUpButton class]])
        [out addObject: view];
    for (NSView *sub in [view subviews])
        collect(sub, out);
}

// Opens the button's menu, returns the frame of the menu window (zero rectangle if there was none) and the
// button's rectangle in screen coordinates.
static NSRect openMenu(NSPopUpButton *button, NSRect *buttonOnScreen) {
    NSWindow *window = [button window];
    NSRect inWindow = [button convertRect: [button bounds] toView: nil];
    *buttonOnScreen = [window convertRectToScreen: inWindow];
    __block NSRect found = NSZeroRect;
    NSTimer *probe = [NSTimer timerWithTimeInterval: 0.4 repeats: NO block: ^(NSTimer *t) {
        NSWindow *menu = menuWindow();
        if (menu != nil)
            found = [menu frame];
        // Escape closes the tracking menu
        NSEvent *escape = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint modifierFlags: 0
                                          timestamp: 0 windowNumber: [menu windowNumber] context: nil
                                         characters: @"\033" charactersIgnoringModifiers: @"\033"
                                          isARepeat: NO keyCode: 53];
        [NSApp postEvent: escape atStart: NO];
        NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: NSMakePoint(5000, 5000)
                                    modifierFlags: 0 timestamp: 0 windowNumber: 0 context: nil
                                      eventNumber: 0 clickCount: 1 pressure: 0];
        [NSApp postEvent: up atStart: NO];
    }];
    [[NSRunLoop currentRunLoop] addTimer: probe forMode: NSRunLoopCommonModes];
    // the click on the control that starts tracking
    NSPoint point = NSMakePoint(NSMidX(inWindow), NSMidY(inWindow));
    NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: point modifierFlags: 0
                                      timestamp: 0 windowNumber: [window windowNumber] context: nil
                                    eventNumber: 0 clickCount: 1 pressure: 1];
    [[button cell] trackMouse: down inRect: [button bounds] ofView: button untilMouseUp: YES];
    spin(0.2);
    // events posted to end the tracking that it did not consume
    while ([NSApp nextEventMatchingMask: NSAnyEventMask untilDate: [NSDate date] inMode: NSDefaultRunLoopMode dequeue: YES]) {}
    return found;
}

static void checkPlacement(NSPopUpButton *button, const char *what) {
    NSRect control;
    NSRect menu = openMenu(button, &control);
    CHECK(!NSIsEmptyRect(menu));
    CHECK(fabs(NSMinX(menu) - NSMinX(control)) <= 8);
    CHECK(NSWidth(menu) >= NSWidth(control) - 1);
    CHECK(NSMinY(menu) < NSMaxY(control) && NSMaxY(menu) > NSMinY(control));
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(420, 380, 400, 200)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(120, 100, 200, 26) pullsDown: NO];
        [button addItemsWithTitles: @[ @"First", @"Second", @"Third" ]];
        [[window contentView] addSubview: button];
        [window makeKeyAndOrderFront: nil];
        spin(0.3);
        checkPlacement(button, "plain window");

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setDirectoryURL: [NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory: YES]];
        [panel beginWithCompletionHandler: ^(NSModalResponse r) {}];
        spin(0.5);
        NSMutableArray *buttons = [NSMutableArray array];
        collect([panel contentView], buttons);
        CHECK([buttons count] > 0);
        if ([buttons count] > 0)
            checkPlacement(buttons[0], "open panel path pop-up");
        [panel cancel: nil];
    }
    if (failures == 0)
        puts("PASS");
    return failures ? 1 : 0;
}
