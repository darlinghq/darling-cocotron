/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// State the Wayland backend reports through the AppKit API: the display class in
// use, screen frames and scale, and a window's frame and backing conversions.
// Needs a compositor: run with DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY
// set to the compositor's socket (a host path). Prints SKIP when the backend is
// not selected. Positions on Wayland are only the backend's virtual origin, so
// only sizes and scale relations are checked, never an absolute position.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSObject (WaylandWindowStateProbe)
+ (id) currentDisplay;
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

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

int main(void) {
    @autoreleasepool {
        const char *backend = getenv("DARLING_APPKIT_BACKEND");
        if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
            printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
            return 0;
        }
        [NSApplication sharedApplication];

        expect([NSStringFromClass([[NSClassFromString(@"NSDisplay") currentDisplay] class])
                       isEqualToString: @"WaylandDisplay"],
               "the Wayland display is the one in use");

        NSArray *screens = [NSScreen screens];
        expect([screens count] >= 1, "at least one screen");
        NSScreen *main = [NSScreen mainScreen];
        expect(main != nil, "main screen");
        expect(NSWidth([main frame]) > 0 && NSHeight([main frame]) > 0, "main screen has a size");
        CGFloat scale = [main backingScaleFactor];
        expect(scale >= 1.0, "screen scale is at least 1");

        NSRect contentRect = NSMakeRect(40, 40, 320, 200);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: contentRect
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window orderFront: nil];
        spin(0.3);

        expect(fabs(NSWidth([window frame]) - 320) < 1 && fabs(NSHeight([window frame]) - 200) < 1,
               "a borderless window keeps its size");
        expect(fabs([window backingScaleFactor] - scale) < 0.01 ||
               fabs([window backingScaleFactor] - [[window screen] backingScaleFactor]) < 0.01,
               "the window scale is the scale of its screen");

        NSRect pixels = [[window contentView] convertRectToBacking: NSMakeRect(0, 0, 100, 50)];
        expect(fabs(NSWidth(pixels) - 100 * [window backingScaleFactor]) < 1.0 &&
               fabs(NSHeight(pixels) - 50 * [window backingScaleFactor]) < 1.0,
               "content converts to pixels by the window scale");

        // A client chooses its own size on xdg-shell unless the compositor tiles it.
        NSRect resized = NSMakeRect(NSMinX([window frame]), NSMinY([window frame]), 400, 260);
        [window setFrame: resized display: YES];
        spin(0.3);
        expect(fabs(NSWidth([window frame]) - 400) < 1 && fabs(NSHeight([window frame]) - 260) < 1,
               "setFrame: size round trips");

        [window orderOut: nil];
        spin(0.1);
        expect(![window isVisible], "orderOut hides the window");
        [window release];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
