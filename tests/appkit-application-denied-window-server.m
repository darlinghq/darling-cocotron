/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// A process that denies itself connections to the window system before it starts AppKit (as WebKit's web
// content process does) still gets its NSApplication, has no window system connection and sees no screens.
// Observed on macOS 26.7.3 x86_64: CGSSetDenyWindowServerConnections(true) returns 0, +sharedApplication
// returns NSApp, CGSMainConnectionID() is 0 and +[NSScreen screens] is an empty array; allowing connections
// again also returns 0.
#import <AppKit/AppKit.h>
#include <stdio.h>

extern int CGSSetDenyWindowServerConnections(unsigned char deny);
extern int CGSMainConnectionID(void);

static int failures;
#define CHECK(cond, what) do { int ok_ = (cond); printf("%s: %s\n", ok_ ? "PASS" : "FAIL", what); if (!ok_) failures++; } while (0)

int main(void) {
    @autoreleasepool {
        CHECK(CGSSetDenyWindowServerConnections(1) == 0, "connections can be denied before any was opened");

        NSApplication *app = nil;
        @try {
            app = [NSApplication sharedApplication];
        } @catch (NSException *e) {
            printf("sharedApplication raised %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
        }
        CHECK(app != nil && app == NSApp, "+sharedApplication returns NSApp");
        CHECK(CGSMainConnectionID() == 0, "the process has no window system connection");

        NSArray *screens = nil;
        @try {
            screens = [NSScreen screens];
        } @catch (NSException *e) {
            printf("screens raised %s: %s\n", e.name.UTF8String, e.reason.UTF8String);
        }
        CHECK(screens != nil && screens.count == 0, "+[NSScreen screens] is an empty array");

        CHECK(CGSSetDenyWindowServerConnections(0) == 0, "connections can be allowed again");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
