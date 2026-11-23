/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// The pointer leaving a window on the X11 backend sends mouseExited: to the owners of the tracking areas it was
// in. The owner of an area with NSTrackingMouseEnteredAndExited gets mouseEntered: when the pointer enters the
// area and mouseExited: when it leaves it; a pointer outside the window is outside every area of the view
// (https://developer.apple.com/documentation/appkit/nstrackingarea,
// https://developer.apple.com/documentation/appkit/nsresponder/mouseexited(with:)).
// The pointer is moved with CGWarpMouseCursorPosition, which the X11 backend turns into XWarpPointer, so the
// window gets real MotionNotify and LeaveNotify events (the crossing rules are tested in tests/x11-leave-notify.c).
// An exit carries the pointer's position outside the window. A move inside the window sends no exit. Needs an X
// session with a window manager; skipped on other backends. Build without ARC.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
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

static NSWindow *window;
static CGFloat screenHeight;

// A point of the content view (outside it as well), as a pointer position in the global CoreGraphics space
// (y down).
static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y) toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (![NSStringFromClass([[NSDisplay currentDisplay] class]) hasPrefix: @"X11"]) {
            printf("SKIP: not the X11 backend\n");
            return 0;
        }
        screenHeight = [[NSScreen mainScreen] frame].size.height;

        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSRect bounds = [[window contentView] bounds];
        TrackedView *view = [[TrackedView alloc] initWithFrame: bounds];
        [[window contentView] addSubview: view];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        BOOL key = waitFor(^BOOL { return [window isKeyWindow]; }, 5.0);
        expect(key, "the window becomes key");
        if (!key) {
            printf("FAILED\n");
            return 1;
        }
        // Tracking areas are evaluated for the motion the window is sent, which takes this setting.
        [window setAcceptsMouseMovedEvents: YES];

        movePointer(-60, 100); // outside, left of the window
        pump(0.5);
        view->entered = view->exited = 0;

        movePointer(100, 100);
        expect(waitFor(^BOOL { return view->entered == 1; }, 3.0), "moving into the window sends mouseEntered:");
        expect(view->exited == 0, "and no exit");

        movePointer(250, 150);
        pump(0.5);
        expect(view->entered == 1 && view->exited == 0, "moving inside the window sends neither");

        movePointer(-60, 100);
        expect(waitFor(^BOOL { return view->exited == 1; }, 3.0), "moving the pointer out of the window sends mouseExited:");
        expect(view->exitLocation.x < 0, "the exit is located outside the window");

        pump(0.5);
        expect(view->exited == 1, "the exit is sent once");

        movePointer(100, 100);
        expect(waitFor(^BOOL { return view->entered == 2; }, 3.0), "moving back in sends mouseEntered: again");

        // Leaving through another side, the bottom edge.
        movePointer(100, -80);
        expect(waitFor(^BOOL { return view->exited == 2; }, 3.0), "leaving through another side sends mouseExited: again");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
