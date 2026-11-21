/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The X11 backend's occlusion judgement must not ask the server again for what it already knows. While another
// client's window is the focused one, a window manager keeps sending ConfigureNotify events that repeat that
// window's geometry and rewrites the stacking list; none of that can change whether a window of ours is covered,
// so the application must send (almost) no X requests for it. Prints PASS on success. Needs an X11 session
// (the test is skipped on others); run through appkit-x11-occlusion-requests.sh, which starts the helper
// x11-active-window.c after READY. Build without ARC.
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

static void pump(double seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window orderFront: nil];

        id display = [NSDisplay currentDisplay];
        if (![NSStringFromClass([display class]) hasPrefix: @"X11"] || ![display respondsToSelector: @selector(display)]) {
            printf("SKIP: not the X11 backend\nPASS\n");
            return 0;
        }
        void *xdisplay = [display performSelector: @selector(display)];
        unsigned long (*nextRequest)(void *) = dlsym(RTLD_DEFAULT, "XNextRequest");
        if (nextRequest == NULL) {
            printf("FAIL: XNextRequest is not available\n");
            return 1;
        }

        pump(0.5);
        printf("READY\n");
        fflush(stdout);
        // The helper makes its window the focused one and starts its stream; the first judgement
        // of the new focused window may cost a few requests, so measure after it.
        pump(2.0);
        unsigned long before = nextRequest(xdisplay);
        pump(3.0);
        unsigned long used = nextRequest(xdisplay) - before;
        printf("X requests in 3 s of repeated notifications: %lu\n", used);
        if (used > 20) {
            printf("FAIL: the notifications cost %lu requests, expected at most 20\n", used);
            return 1;
        }
        printf("PASS\n");
    }
    return 0;
}
