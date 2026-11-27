/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A titled window in fullscreen, on any backend whose window system does fullscreen (the X11 backend under a
// window manager that does it, or the Wayland backend with a compositor): the menu is out of the way, so the
// content view fills the whole frame, and leaving fullscreen brings the window back at the content size it had
// (the in-window menu strip, if the backend shows the menu in the windows, is back too). Run with
// DARLING_APPKIT_BACKEND=x11 and DISPLAY, or with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static BOOL waitFor(BOOL (^condition)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: 3.0];
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

static BOOL sameSize(NSSize a, NSSize b) { return fabs(a.width - b.width) < 1 && fabs(a.height - b.height) < 1; }

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(60, 60, 400, 300)
                                                       styleMask: NSTitledWindowMask | NSClosableWindowMask |
                                                                  NSResizableWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
        [window makeKeyAndOrderFront: nil];
        waitFor(^BOOL { return [window isVisible]; });
        NSSize before = [[window contentView] frame].size;
        NSSize screen = [[NSScreen mainScreen] frame].size;

        [window toggleFullScreen: nil];
        BOOL entered = waitFor(^BOOL {
            return ([window styleMask] & NSWindowStyleMaskFullScreen) != 0 && sameSize([window frame].size, screen);
        });
        if (!entered) {
            printf("SKIP: the window system does not do fullscreen\n");
            return 0;
        }
        expect(waitFor(^BOOL { return sameSize([[window contentView] frame].size, [window frame].size); }),
               "in fullscreen the content view is as large as the frame");

        [window toggleFullScreen: nil];
        expect(waitFor(^BOOL {
                   return ([window styleMask] & NSWindowStyleMaskFullScreen) == 0 &&
                          sameSize([[window contentView] frame].size, before);
               }),
               "leaving fullscreen restores the content size");
        [window orderOut: nil];
        [window release];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
