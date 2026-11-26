/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// The process' connection to the window system is CoreGraphics': the native display it reports is the
// connection of the main CGS connection, it is the one an AppKit window uses, and it does not change when
// AppKit starts. The host script coregraphics-native-connection-count.sh counts the sockets.
//
// Usage: coregraphics-native-connection             checks (CoreGraphics only, then AppKit)
//        coregraphics-native-connection hold        also stays up after READY with only CoreGraphics' displays queried
//        coregraphics-native-connection hold-appkit also stays up with an AppKit window shown
//        EXPECT_KIND=x11|wayland checks the kind of the connection.
// Compile with -DNO_NATIVE_API to leave out the calls of the interface this test checks (it then only
// holds the connection for the script).
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef NO_NATIVE_API
// CGSMainConnectionID() and _CGSNativeDisplay() are declared by the CoreGraphics headers.
extern int _CGSNativeConnectionKind(void);
extern void *_CGSNativeConnectionDisplay(void);
#endif

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

static void spinFor(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *mode = argc > 1 ? argv[1] : "";
        BOOL holdAppKit = strcmp(mode, "hold-appkit") == 0;
        BOOL hold = holdAppKit || strcmp(mode, "hold") == 0;

        // CoreGraphics first: the displays are read through the connection.
        uint32_t count = 0;
        CHECK(1, CGGetActiveDisplayList(0, NULL, &count) == kCGErrorSuccess && count >= 1);
#ifndef NO_NATIVE_API
        int kind = _CGSNativeConnectionKind();
        const char *expected = getenv("EXPECT_KIND");
        CHECK(2, kind == 1 || kind == 2);
        CHECK(3, expected == NULL || (strcmp(expected, "x11") == 0 ? kind == 1 : kind == 2));
        void *display = _CGSNativeConnectionDisplay();
        CHECK(4, display != NULL);
        CHECK(5, display == _CGSNativeDisplay(CGSMainConnectionID()));
#endif

        if (holdAppKit || !hold) {
            // AppKit's backend takes this connection: starting it, and showing a window, does not change it.
            [NSApplication sharedApplication];
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                           styleMask: NSTitledWindowMask
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
            spinFor(0.5);
            CHECK(6, [[NSScreen screens] count] == count);
#ifndef NO_NATIVE_API
            CHECK(7, _CGSNativeConnectionDisplay() == display);
            CHECK(8, _CGSNativeConnectionKind() == kind);
#endif
        }
        if (hold) {
            printf("READY\n");
            fflush(stdout);
            spinFor(30);
            return 0;
        }
        printf("PASS\n");
    }
    return 0;
}
