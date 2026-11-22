// Copyright (C) 2026 Lubos Dolezel
//
// The events a tracking area sends to its owner (mouse entered, exited, moved and cursor update) carry a
// timestamp in seconds since the system started, like every other event
// (https://developer.apple.com/documentation/appkit/nsevent/timestamp). The mach_absolute_time clock is used as the
// reference, as in appkit-event-timestamps.m. The area is active in the active application because a
// cursor-update area is not sent cursorUpdate: with NSTrackingActiveAlways. The pointer is moved with CGWarpMouseCursorPosition. Needs an X server with a window manager. Build without ARC.
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <mach/mach_time.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: timeout];
    while (!condition()) {
        if ([end timeIntervalSinceNow] <= 0)
            return NO;
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    }
    return YES;
}

@interface Recorder : NSObject {
@public
    NSTimeInterval entered, exited, moved, cursorUpdate;
    BOOL gotEntered, gotExited, gotMoved, gotCursorUpdate;
}
@end
@implementation Recorder
- (void) mouseEntered: (NSEvent *) event {
    entered = [event timestamp];
    gotEntered = YES;
}
- (void) mouseExited: (NSEvent *) event {
    exited = [event timestamp];
    gotExited = YES;
}
- (void) mouseMoved: (NSEvent *) event {
    moved = [event timestamp];
    gotMoved = YES;
}
- (void) cursorUpdate: (NSEvent *) event {
    cursorUpdate = [event timestamp];
    gotCursorUpdate = YES;
}
@end

static NSWindow *window;
static CGFloat screenHeight;

static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y) toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

// A timestamp since system start is within seconds of the uptime now; one counted from 2001 is decades away.
static void expectSinceStartup(NSTimeInterval stamp, const char *what) {
    mach_timebase_info_data_t base;
    mach_timebase_info(&base);
    NSTimeInterval uptime = (double) mach_absolute_time() * base.numer / base.denom / 1e9;
    char message[200];
    snprintf(message, sizeof message, "%s: timestamp %.3f is within 10 s before the system uptime %.3f", what, stamp,
             uptime);
    expect(stamp <= uptime + 0.5 && stamp > uptime - 10, message);
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        screenHeight = [[NSScreen mainScreen] frame].size.height;
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        [window setContentView: view];
        Recorder *recorder = [[Recorder alloc] init];
        NSTrackingArea *area = [[NSTrackingArea alloc]
                initWithRect: NSMakeRect(200, 0, 100, 100)
                     options: NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingCursorUpdate |
                              NSTrackingActiveInActiveApp
                       owner: recorder
                    userInfo: nil];
        [view addTrackingArea: area];

        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        if (!waitFor(^BOOL { return [window isVisible]; }, 5.0)) {
            printf("FAILED\n");
            return 1;
        }
        [window setAcceptsMouseMovedEvents: YES];

        movePointer(350, 250); // outside the area
        waitFor(^BOOL { return NO; }, 0.5);
        movePointer(250, 50); // inside
        expect(waitFor(^BOOL { return recorder->gotEntered; }, 3.0), "mouseEntered: is sent");
        expectSinceStartup(recorder->entered, "mouseEntered:");
        expect(waitFor(^BOOL { return recorder->gotCursorUpdate; }, 3.0), "cursorUpdate: is sent");
        expectSinceStartup(recorder->cursorUpdate, "cursorUpdate:");

        movePointer(260, 60); // still inside
        expect(waitFor(^BOOL { return recorder->gotMoved; }, 3.0), "mouseMoved: is sent");
        expectSinceStartup(recorder->moved, "mouseMoved:");

        movePointer(350, 250); // out again
        expect(waitFor(^BOOL { return recorder->gotExited; }, 3.0), "mouseExited: is sent");
        expectSinceStartup(recorder->exited, "mouseExited:");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
