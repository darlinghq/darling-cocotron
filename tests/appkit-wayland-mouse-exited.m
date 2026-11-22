// Copyright (C) 2026 Lubos Dolezel
//
// The pointer leaving a window on the Wayland backend sends mouseExited: to the owners of the tracking areas it was
// in, as on the X11 backend (tests/appkit-x11-mouse-exited.m): an area with NSTrackingMouseEnteredAndExited gets
// mouseEntered: when the pointer enters it and mouseExited: when the pointer leaves the window
// (https://developer.apple.com/documentation/appkit/nstrackingarea,
// https://developer.apple.com/documentation/appkit/nsresponder/mouseexited(with:)). A move inside the window
// sends no exit. The pointer is driven from outside, by tests/appkit-wayland-mouse-exited.sh through a virtual
// pointer: out of the window, in at its centre, to another point inside, out through the left side, in again, out
// through the bottom. The script moves the pointer when the test has printed the STEP line of the previous step. Skipped on other backends. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

static int failures;

static int currentEntered, currentExited;

static void expect(BOOL condition, const char *what) {
    printf("%s %s (entered %d, exited %d so far)\n", condition ? "PASS" : "FAIL", what, currentEntered, currentExited);
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
    currentEntered = entered;
}
- (void) mouseExited: (NSEvent *) event {
    exited++;
    currentExited = exited;
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
        // Each STEP line tells the script that the checks of the step are done and the pointer can go on.
        printf("READY\n");
        pump(1.0); // the pointer is moved to a point outside the window
        printf("STEP 1\n");

        expect(waitFor(^BOOL { return view->entered == 1; }, 10.0), "moving into the window sends mouseEntered:");
        expect(view->exited == 0, "and no exit");
        printf("STEP 2\n");

        pump(1.0); // the pointer moves to another point of the window
        expect(view->entered == 1 && view->exited == 0, "moving inside the window sends neither");
        printf("STEP 3\n");

        expect(waitFor(^BOOL { return view->exited == 1; }, 10.0),
               "the pointer leaving through the left side sends mouseExited:");
        // The compositor does not say where the pointer went: the exit is located just outside the nearest edge.
        NSRect frame = NSMakeRect(0, 0, [window frame].size.width, [window frame].size.height);
        expect(!NSPointInRect(view->exitLocation, frame), "the exit is located outside the window");
        printf("STEP 4\n");

        expect(waitFor(^BOOL { return view->entered == 2; }, 10.0), "moving back in sends mouseEntered: again");
        printf("STEP 5\n");

        expect(waitFor(^BOOL { return view->exited == 2; }, 10.0),
               "the pointer leaving through the bottom sends mouseExited: again");
        expect(!NSPointInRect(view->exitLocation, frame), "the second exit is located outside the window too");
        pump(1.0);
        expect(view->entered == 2 && view->exited == 2, "each crossing was sent once");
        printf("STEP 6\n");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
