// Copyright (C) 2026 Lubos Dolezel
//
// The pointer leaving a window on the Wayland backend sends mouseExited: to the owners of the tracking areas it was
// in, as on the X11 backend (tests/appkit-x11-mouse-exited.m): an area with NSTrackingMouseEnteredAndExited gets
// mouseEntered: when the pointer enters it and mouseExited: when the pointer leaves the window
// (https://developer.apple.com/documentation/appkit/nstrackingarea,
// https://developer.apple.com/documentation/appkit/nsresponder/mouseexited(with:)). A move inside the window
// sends no exit. The pointer is driven from outside, by tests/appkit-wayland-mouse-exited.sh through a virtual
// pointer: out of the window, in at its centre, to another point inside, out through the left side, in again, out
// through the bottom. The test waits for each step. Skipped on other backends. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static void pump(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: timeout];
    while (!condition()) {
        if ([end timeIntervalSinceNow] <= 0)
            return NO;
        pump(0.05);
    }
    return YES;
}

@interface TrackedView : NSView {
@public
    int entered, exited;
    NSPoint exitLocation;
}
@end
@implementation TrackedView
- (void) updateTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas])
        [self removeTrackingArea: area];
    NSTrackingArea *area = [[NSTrackingArea alloc]
            initWithRect: [self bounds]
                 options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                   owner: self
                userInfo: nil];
    [self addTrackingArea: area];
    [area release];
    [super updateTrackingAreas];
}
- (void) mouseEntered: (NSEvent *) event {
    entered++;
}
- (void) mouseExited: (NSEvent *) event {
    exited++;
    exitLocation = [event locationInWindow];
}
@end

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        if (![NSStringFromClass([[NSDisplay currentDisplay] class]) hasPrefix: @"Wayland"]) {
            printf("SKIP: not the Wayland backend\n");
            return 0;
        }

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        TrackedView *view = [[TrackedView alloc] initWithFrame: [[window contentView] bounds]];
        [[window contentView] addSubview: view];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        BOOL visible = waitFor(^BOOL { return [window isVisible]; }, 5.0);
        expect(visible, "the window is shown");
        if (!visible) {
            printf("FAILED\n");
            return 1;
        }
        // Tracking areas are evaluated for the motion the window is sent, which takes this setting.
        [window setAcceptsMouseMovedEvents: YES];
        pump(0.5);
        printf("READY\n");

        expect(waitFor(^BOOL { return view->entered == 1; }, 10.0), "moving into the window sends mouseEntered:");
        expect(view->exited == 0, "and no exit");

        pump(1.5); // the pointer moves to another point of the window
        expect(view->entered == 1 && view->exited == 0, "moving inside the window sends neither");

        expect(waitFor(^BOOL { return view->exited == 1; }, 10.0),
               "the pointer leaving through the left side sends mouseExited:");
        expect(view->exitLocation.x < 0, "the exit is located outside the window, beyond the left side");

        expect(waitFor(^BOOL { return view->entered == 2; }, 10.0), "moving back in sends mouseEntered: again");
        expect(waitFor(^BOOL { return view->exited == 2; }, 10.0),
               "the pointer leaving through the bottom sends mouseExited: again");
        expect(view->exitLocation.y < 0, "the exit is located outside the window, below it");

        pump(1.0);
        expect(view->entered == 2 && view->exited == 2, "each crossing was sent once");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
