/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Fullscreen on the Wayland backend (xdg_toplevel set_fullscreen / unset_fullscreen),
// seen through the AppKit API. Needs a compositor that honours the requests, such as a
// headless sway: run with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY set; prints
// SKIP otherwise. A titled window that is made fullscreen has the fullscreen style bit and
// the size of its screen once the compositor has answered, and returns to its previous
// size when it leaves fullscreen. A borderless window the size of the screen is promoted
// without asking.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// Runs the event loop until the condition holds or two seconds pass.
static BOOL waitFor(BOOL (^condition)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: 2.0];
    while ([until timeIntervalSinceNow] > 0) {
        if (condition())
            return YES;
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
    return condition();
}

int main(void) {
    const char *backend = getenv("DARLING_APPKIT_BACKEND");
    if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
        printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
        return 0;
    }
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect screen = [[NSScreen mainScreen] frame];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(60, 60, 400, 300)
                                                       styleMask: NSTitledWindowMask | NSClosableWindowMask |
                                                                  NSResizableWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window makeKeyAndOrderFront: nil];
        waitFor(^BOOL { return [window isVisible]; });
        NSSize before = [[window contentView] frame].size;

        [window toggleFullScreen: nil];
        BOOL entered = waitFor(^BOOL {
            return ([window styleMask] & NSWindowStyleMaskFullScreen) != 0 &&
                   fabs([[window contentView] frame].size.width - screen.size.width) < 2;
        });
        expect(entered, "toggleFullScreen: gives the fullscreen style and the screen's width");
        expect(fabs([[window contentView] frame].size.height - screen.size.height) < 2, "and its height");

        [window toggleFullScreen: nil];
        BOOL left = waitFor(^BOOL {
            return ([window styleMask] & NSWindowStyleMaskFullScreen) == 0 &&
                   fabs([[window contentView] frame].size.width - before.width) < 2;
        });
        expect(left, "leaving fullscreen restores the previous size");
        [window orderOut: nil];
        [window release];

        // A borderless window of exactly the screen's size is how borderless fullscreen is done.
        NSWindow *borderless = [[NSWindow alloc] initWithContentRect: screen
                                                           styleMask: NSBorderlessWindowMask
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
        [borderless makeKeyAndOrderFront: nil];
        BOOL covers = waitFor(^BOOL {
            NSRect frame = [borderless frame];
            return fabs(frame.size.width - screen.size.width) < 2 && fabs(frame.size.height - screen.size.height) < 2;
        });
        expect(covers, "a screen-sized borderless window keeps the screen's size");
        [borderless orderOut: nil];
        [borderless release];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
