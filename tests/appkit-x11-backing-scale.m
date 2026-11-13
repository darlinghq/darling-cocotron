/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend at a configured backing scale. Run on an X server with the scale
// in GDK_SCALE (usage: appkit-x11-backing-scale <scale> <pixel width> <pixel height>,
// the size of the X screen), e.g. under Xvfb :99 with GDK_SCALE=2 and 1920 1080.
// Screen frames are in points, a borderless window keeps its frame, content
// converts to backing pixels by the scale, and a new frame in points survives the
// round trip through the device pixel geometry the X server reports.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) <= 1.0;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <scale> <pixel width> <pixel height>\n", argv[0]);
        return 2;
    }
    double scale = atof(argv[1]);
    double pixelWidth = atof(argv[2]), pixelHeight = atof(argv[3]);

    @autoreleasepool {
        [NSApplication sharedApplication];

        NSScreen *screen = [[NSScreen screens] objectAtIndex: 0];
        expect([screen backingScaleFactor] == scale, "the screen reports the configured scale");
        NSRect frame = [screen frame];
        expect(near(frame.size.width * scale, pixelWidth) && near(frame.size.height * scale, pixelHeight),
               "the screen frame is the X screen size divided by the scale");
        expect(frame.origin.x == 0 && frame.origin.y == 0, "the main screen is at the origin");

        NSRect content = NSMakeRect(100, 100, 400, 300);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: content
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        expect([window backingScaleFactor] == scale, "the window reports the scale of its screen");
        NSRect backing = [[window contentView] convertRectToBacking: [[window contentView] bounds]];
        expect(near(backing.size.width, 400 * scale) && near(backing.size.height, 300 * scale),
               "the content view is 'scale' device pixels per point");

        [window makeKeyAndOrderFront: nil];
        // Let the ConfigureNotify for the mapped window arrive; the geometry read back from X
        // is in device pixels and has to come out as the frame that was asked for.
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
        NSRect after = [window frame];
        expect(near(after.origin.x, 100) && near(after.origin.y, 100) && near(after.size.width, 400) &&
                       near(after.size.height, 300),
               "the window keeps its frame in points after it is mapped");

        [window setFrame: NSMakeRect(50, 60, 200, 150) display: YES];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
        after = [window frame];
        expect(near(after.origin.x, 50) && near(after.origin.y, 60) && near(after.size.width, 200) &&
                       near(after.size.height, 150),
               "a new frame in points is kept after the X geometry is read back");

        [window close];
    }
    if (failures == 0)
        printf("OK\n");
    return failures == 0 ? 0 : 1;
}
