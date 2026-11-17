/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A window with a full-size content view and a transparent title bar has no title bar of its own
// to show, so the platform must not draw or request any frame for it; a titled window without
// both properties keeps its frame. Opens four windows (plain, full-size only, transparent only,
// both) and a fifth that becomes transparent after it is shown. The harness
// appkit-wayland-window-chrome.sh asks the compositor for each window's state at the "shown" and
// "changed" lines this program prints, after the "win" lines that give the window sizes AppKit reports. Usage: appkit-wayland-window-chrome <hold seconds>.
// Needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY; prints SKIP otherwise.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void spin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

// One "win <title> <width> <height>" line per window: the size AppKit reports for the window.
static void report(NSArray *windows) {
    for (NSWindow *w in windows)
        printf("win %s %d %d\n", [w.title UTF8String], (int) w.frame.size.width, (int) w.frame.size.height);
}

static NSWindow *make(NSString *title, NSUInteger style, BOOL transparent) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 300, 200)
                                              styleMask: style
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    w.title = title;
    w.titlebarAppearsTransparent = transparent;
    [w setReleasedWhenClosed: NO];
    [w orderFront: nil];
    return w;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *backend = getenv("DARLING_APPKIT_BACKEND");
        if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
            printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
            return 0;
        }
        [NSApplication sharedApplication];
        if (![NSStringFromClass([[NSClassFromString(@"NSDisplay") performSelector: @selector(currentDisplay)] class])
                    isEqualToString: @"WaylandDisplay"]) {
            printf("SKIP: the Wayland backend is not in use\n");
            return 0;
        }
        NSUInteger base = NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        NSUInteger full = base | NSWindowStyleMaskFullSizeContentView;
        NSWindow *a = make(@"plain", base, NO);
        NSWindow *b = make(@"fullsize-only", full, NO);
        NSWindow *c = make(@"transparent-only", base, YES);
        NSWindow *d = make(@"chromeless", full, YES);
        NSWindow *e = make(@"late-transparent", full, NO);
        [NSApp activateIgnoringOtherApps: YES];
        spin(3);
        NSArray *windows = @[a, b, c, d, e];
        report(windows);
        printf("shown\n");
        fflush(stdout);
        spin(3);
        e.titlebarAppearsTransparent = YES; // takes effect on a window that is already shown
        spin(2);
        report(windows);
        printf("changed\n");
        fflush(stdout);
        spin(argc > 1 ? atof(argv[1]) : 0);
    }
    return 0;
}
