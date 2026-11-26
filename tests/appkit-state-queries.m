// CFLAGS: -framework Foundation -framework AppKit -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// +[NSEvent mouseLocation], +[NSEvent modifierFlags] and +[NSEvent pressedMouseButtons] report the state
// that CoreGraphics reports: the location of CGEventCreate(NULL) (CoreGraphics' space has its origin at the top
// left of the main display, Cocoa's at the bottom left), CGEventSourceFlagsState() and
// CGEventSourceButtonState(). Real input drives them: the harness moves the pointer into the window, then holds
// Shift and the left button, then lets go (appkit-state-queries-x11.sh with XTest,
// appkit-state-queries-wayland.sh with a virtual pointer and keyboard). The program prints READY, PHASE2 once the
// pointer is over the window, PHASE3 once the keys and the button are down and the queries have been compared, and
// PHASE4 once they are let go, when the pointer leaves the window; it waits at most 60 seconds in all.
//
// Usage: appkit-state-queries
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

// CGEventCreate(NULL)'s location in Cocoa's space.
static NSPoint coreGraphicsLocation(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    return NSMakePoint(point.x, CGDisplayBounds(CGMainDisplayID()).size.height - point.y);
}

static BOOL agree(NSPoint a, NSPoint b) {
    return fabs(a.x - b.x) <= 1.0 && fabs(a.y - b.y) <= 1.0;
}

static void pump(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0 && !done()) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"state-queries"];
        [window setAcceptsMouseMovedEvents: YES];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        // Nothing is held yet.
        NSEventModifierFlags held = NSEventModifierFlagShift | NSEventModifierFlagControl |
                                    NSEventModifierFlagOption | NSEventModifierFlagCommand;
        expect(([NSEvent modifierFlags] & held) == 0, @"no modifier is held at the start");
        expect([NSEvent pressedMouseButtons] == 0, @"no button is held at the start");
        printf("READY\n");

        // The pointer is moved over the window.
        __block BOOL moved = NO;
        __block NSPoint seen = NSZeroPoint;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!moved && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event == nil)
                continue;
            if ([event type] == NSEventTypeMouseMoved && [event window] == window) {
                moved = YES;
                seen = [window convertBaseToScreen: [event locationInWindow]];
            }
            [NSApp sendEvent: event];
        }
        expect(moved, @"the pointer's motion over the window arrives");
        NSPoint mouse = [NSEvent mouseLocation];
        expect(agree(mouse, seen), [NSString stringWithFormat: @"+[NSEvent mouseLocation] is where the event was (%.0f, %.0f) (%.0f, %.0f)",
                                    mouse.x, mouse.y, seen.x, seen.y]);
        expect(agree(mouse, coreGraphicsLocation()),
               [NSString stringWithFormat: @"  and where CGEventCreate(NULL) puts it (%.0f, %.0f) (%.0f, %.0f)", mouse.x,
                mouse.y, coreGraphicsLocation().x, coreGraphicsLocation().y]);
        expect(NSPointInRect(mouse, [window frame]), @"  inside the window");
        printf("PHASE2\n");

        // Shift and the left button are held.
        pump(15, ^BOOL { return ([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0 &&
                                ([NSEvent pressedMouseButtons] & 1) != 0; });
        CGEventFlags flags = CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState);
        expect(([NSEvent modifierFlags] & NSEventModifierFlagShift) != 0, @"+[NSEvent modifierFlags] has Shift");
        expect((flags & kCGEventFlagMaskShift) != 0, @"  and so does CGEventSourceFlagsState()");
        expect(([NSEvent modifierFlags] & held) == (flags & held), @"  and they agree on the modifiers");
        expect(([NSEvent pressedMouseButtons] & 1) != 0, @"+[NSEvent pressedMouseButtons] has the left button");
        expect(CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft),
               @"  and so does CGEventSourceButtonState()");
        expect(!CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonRight) &&
               ([NSEvent pressedMouseButtons] & 2) == 0, @"  the right button is not held");
        printf("PHASE3\n");

        // They are let go.
        pump(15, ^BOOL { return ([NSEvent modifierFlags] & NSEventModifierFlagShift) == 0 &&
                                [NSEvent pressedMouseButtons] == 0; });
        expect(([NSEvent modifierFlags] & held) == 0 &&
               (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kCGEventFlagMaskShift) == 0,
               @"Shift is released");
        expect([NSEvent pressedMouseButtons] == 0 &&
               !CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft),
               @"the button is released");

        // The pointer leaves the window, to the top left corner of the display. X11 says where the pointer is
        // wherever it is; Wayland tells a client nothing of the pointer outside its surfaces, so the location stays
        // where it was last in one.
        NSPoint inside = [NSEvent mouseLocation];
        printf("PHASE4\n");
        double height = CGDisplayBounds(CGMainDisplayID()).size.height;
        BOOL wayland = getenv("DARLING_APPKIT_BACKEND") != NULL && strstr(getenv("DARLING_APPKIT_BACKEND"), "wayland") != NULL;
        pump(5, ^BOOL { return !NSPointInRect([NSEvent mouseLocation], [window frame]) &&
                               !agree([NSEvent mouseLocation], inside); });
        NSPoint outside = [NSEvent mouseLocation];
        expect(agree(outside, coreGraphicsLocation()), @"+[NSEvent mouseLocation] agrees with CGEventCreate(NULL) outside the window");
        if (wayland)
            expect(agree(outside, inside), @"  and stays where the pointer was last over the window (Wayland)");
        else
            expect(fabs(outside.x - 5) <= 2 && fabs(outside.y - (height - 5)) <= 2,
                   [NSString stringWithFormat: @"  and is where the pointer is, in the corner (%.0f, %.0f)", outside.x, outside.y]);
    }
    if (failures == 0)
        printf("ALL PASSED\n");
    else
        printf("FAILED %d\n", failures);
    return failures != 0;
}
