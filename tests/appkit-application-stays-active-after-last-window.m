/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: the application stays active when the input focus leaves its last
// window because that window was closed or hidden, and when it never had a
// window; it resigns when the focus leaves a window that is still shown.
// Prints PASS or FAIL. Needs a window server for the windows.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSWindow (BackendCallbacks)
- (void) platformWindowActivated: (id) window displayIfNeeded: (BOOL) displayIfNeeded;
- (void) platformWindowDeactivated: (id) window checkForAppDeactivation: (BOOL) check;
@end

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSWindow *makeWindow(void) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 200, 100)
                                              styleMask: NSWindowStyleMaskTitled
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    [w setReleasedWhenClosed: NO];
    return w;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        spin(0.2);
        CHECK([NSApp isActive], "application with no window is not active");

        // Closing the window holding the focus.
        NSWindow *a = makeWindow();
        [a orderFront: nil];
        [a platformWindowActivated: nil displayIfNeeded: NO];
        spin(0.2);
        CHECK([NSApp isActive], "not active with a focused window");
        [a close];
        [a platformWindowDeactivated: nil checkForAppDeactivation: NO];
        spin(0.3);
        CHECK([NSApp isActive], "resigned after the last window closed");

        // Hiding the window holding the focus.
        NSWindow *b = makeWindow();
        [b orderFront: nil];
        [b platformWindowActivated: nil displayIfNeeded: NO];
        [b orderOut: nil];
        [b platformWindowDeactivated: nil checkForAppDeactivation: NO];
        spin(0.3);
        CHECK([NSApp isActive], "resigned after the last window was hidden");

        // The focus leaving a window that stays on screen.
        NSWindow *c = makeWindow();
        [c orderFront: nil];
        [c platformWindowActivated: nil displayIfNeeded: NO];
        // A window manager that focuses the new window reports the focus for
        // real in the meantime; the simulated loss comes after it.
        spin(0.5);
        [c platformWindowDeactivated: nil checkForAppDeactivation: NO];
        spin(0.3);
        CHECK(![NSApp isActive], "still active after the focus left a shown window");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
