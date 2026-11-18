/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSWindow occlusionState and NSWindowDidChangeOcclusionStateNotification, and the application's
// occlusionState following its windows. Prints PASS on success. Needs a window system session (X11
// or Wayland). Build without ARC.
//
//   appkit-window-occlusion-state            ordering in and out, and miniaturizing where the window
//                                            system reports it (SKIP lines for what it cannot)
//   appkit-window-occlusion-state external   ordered in, then waits for something outside to cover
//                                            the window (a fullscreen window of another client on X11,
//                                            another workspace on a compositor that suspends hidden
//                                            toplevels) and to uncover it again; see
//                                            appkit-window-occlusion-x11.sh and
//                                            appkit-window-occlusion-wayland.sh
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static int notifications;
static NSWindow *watched;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Counter : NSObject
- (void) changed: (NSNotification *) note;
@end
@implementation Counter
- (void) changed: (NSNotification *) note {
    if ([note object] == watched)
        notifications++;
}
@end

static BOOL windowVisible(void) {
    return ([watched occlusionState] & NSWindowOcclusionStateVisible) != 0;
}

static BOOL appVisible(void) {
    return ([NSApp occlusionState] & NSApplicationOcclusionStateVisible) != 0;
}

static void pump(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// Runs the loop until the window's Visible bit equals wanted, for at most seconds.
static BOOL waitForVisible(BOOL wanted, double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while (windowVisible() != wanted && [end timeIntervalSinceNow] > 0)
        pump(0.05);
    return windowVisible() == wanted;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL external = argc > 1 && strcmp(argv[1], "external") == 0;
        [NSApplication sharedApplication];
        Counter *counter = [[Counter alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(changed:)
                                                     name: NSWindowDidChangeOcclusionStateNotification
                                                   object: nil];
        expect([NSWindowDidChangeOcclusionStateNotification
                       isEqualToString: @"NSWindowDidChangeOcclusionStateNotification"],
               "notification name");

        watched = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
                                              styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
        expect(!windowVisible(), "an ordered-out window does not have the Visible bit");
        expect(!appVisible(), "the application is not visible without a visible window");
        expect(notifications == 0, "creating a window posts no occlusion notification");

        [watched orderFront: nil];
        pump(0.5);
        expect(windowVisible(), "an ordered-in window has the Visible bit");
        expect(appVisible(), "the application is visible while a window is");
        expect(notifications == 1, "ordering in posts one notification");

        if (external) {
            // The driver covers the window once it sees READY and uncovers it again after COVERED.
            printf("READY\n");
            fflush(stdout);
            int before = notifications;
            expect(waitForVisible(NO, 20), "a covered window loses the Visible bit");
            if (!windowVisible()) {
                expect(notifications > before, "covering posts a notification");
                expect(!appVisible(), "the application is not visible while its only window is covered");
                printf("COVERED\n");
                fflush(stdout);
                before = notifications;
                expect(waitForVisible(YES, 20), "an uncovered window has the Visible bit again");
                expect(notifications > before, "uncovering posts a notification");
                expect(appVisible(), "the application is visible again once the window is");
            }
        } else {
            // Window managers and compositors that report miniaturization (an EWMH hidden state on
            // X11) also take the Visible bit away; ones that cannot report it leave the window as it was.
            int before = notifications;
            [watched miniaturize: nil];
            pump(2.0);
            if ([watched isMiniaturized]) {
                expect(!windowVisible(), "a miniaturized window does not have the Visible bit");
                expect(notifications > before, "miniaturizing posts a notification");
                expect(!appVisible(), "the application is not visible while its only window is miniaturized");
                before = notifications;
                [watched deminiaturize: nil];
                expect(waitForVisible(YES, 5), "a deminiaturized window has the Visible bit again");
                expect(notifications > before, "deminiaturizing posts a notification");
                expect(appVisible(), "the application is visible after deminiaturizing");
            } else {
                printf("SKIP: this window system does not report miniaturization\n");
            }
        }

        int before = notifications;
        [watched orderOut: nil];
        pump(0.5);
        expect(!windowVisible(), "an ordered-out window does not have the Visible bit again");
        expect(!appVisible(), "the application is not visible after ordering the window out");
        expect(notifications > before, "ordering out posts a notification");
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
