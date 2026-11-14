/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Rendering scale through the AppKit API on the Wayland backend (integer buffer scale or
// wp-fractional-scale-v1). Usage: appkit-wayland-backing-scale <scale> [hold-seconds], the scale the
// compositor gives the output the window opens on, e.g. 1, 2 or 1.5. Needs a compositor
// (DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY set); prints SKIP otherwise.
// Checked: the screen and window scale are the output's scale rounded up to a whole number
// (as on macOS, backingScaleFactor is whole: a 1.5 output gives 2 and its surface is drawn
// at 2 and shown at the logical size), point sizes are untouched by the scale, content
// converts to pixels by that scale and back. With hold-seconds the window stays up for that
// long after the checks, so that tests/appkit-wayland-presented-size.sh can ask the compositor
// what size it shows.
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

int main(int argc, char **argv) {
    const char *backend = getenv("DARLING_APPKIT_BACKEND");
    if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
        printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
        return 0;
    }
    if (argc < 2 || argc > 3) {
        fprintf(stderr, "usage: %s <scale> [hold-seconds]\n", argv[0]);
        return 2;
    }
    double outputScale = atof(argv[1]);
    double scale = ceil(outputScale - 0.001);

    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(40, 40, 301, 203)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window orderFront: nil];
        spin(0.5);

        expect(fabs([[NSScreen mainScreen] backingScaleFactor] - scale) < 0.01, "the screen reports the output scale rounded up");
        expect(fabs([window backingScaleFactor] - scale) < 0.01, "the window reports the output scale rounded up");
        expect(fabs(NSWidth([[window contentView] bounds]) - 301) < 0.01 &&
               fabs(NSHeight([[window contentView] bounds]) - 203) < 0.01,
               "the point size does not depend on the scale");

        NSRect pixels = [[window contentView] convertRectToBacking: [[window contentView] bounds]];
        double slack = 0.01;
        expect(fabs(NSWidth(pixels) - 301 * scale) <= slack && fabs(NSHeight(pixels) - 203 * scale) <= slack,
               "content converts to pixels by the scale");
        NSRect back = [[window contentView] convertRectFromBacking: pixels];
        expect(fabs(NSWidth(back) - 301) <= slack / scale && fabs(NSHeight(back) - 203) <= slack / scale,
               "pixels convert back to the point size");

        if (argc == 3)
            spin(atof(argv[2]));
        [window orderOut: nil];
        [window release];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
