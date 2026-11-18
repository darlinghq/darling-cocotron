/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSScreen: convertRectToBacking:, convertRectFromBacking:, backingAlignedRect:options: and
// canRepresentDisplayGamut:. The conversions scale by backingScaleFactor, the alignment moves the edges
// onto whole backing pixels, and a screen can show the sRGB gamut. Prints PASS on success. Needs a screen
// (a display or the Mac's headless one), no windows.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL sameRect(NSRect a, NSRect b) {
    return fabs(a.origin.x - b.origin.x) < 1e-6 && fabs(a.origin.y - b.origin.y) < 1e-6 &&
           fabs(a.size.width - b.size.width) < 1e-6 && fabs(a.size.height - b.size.height) < 1e-6;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSScreen *screen = [[NSScreen screens] firstObject];
        expect(screen != nil, "there is a screen");
        if (screen == nil)
            return 1;

        CGFloat scale = [screen backingScaleFactor];
        NSRect rect = NSMakeRect(10.3, 20.6, 100.4, 50.5);
        NSRect backing = [screen convertRectToBacking: rect];
        expect(sameRect(backing, NSMakeRect(10.3 * scale, 20.6 * scale, 100.4 * scale, 50.5 * scale)),
               "convertRectToBacking: scales by the backing scale factor");
        expect(sameRect([screen convertRectFromBacking: backing], rect),
               "convertRectFromBacking: undoes convertRectToBacking:");
        expect(sameRect([screen convertRectToBacking: NSZeroRect], NSZeroRect), "an empty rect stays empty");

        // Edges on whole backing pixels. Expected values are for one pixel per point (scale 1); at other
        // scales only the grid property is checked.
        NSRect nearest = [screen backingAlignedRect: rect options: NSAlignAllEdgesNearest];
        NSRect outward = [screen backingAlignedRect: rect options: NSAlignAllEdgesOutward];
        NSRect inward = [screen backingAlignedRect: rect options: NSAlignAllEdgesInward];
        NSRect nearestPixels = [screen convertRectToBacking: nearest];
        expect(fabs(nearestPixels.origin.x - round(nearestPixels.origin.x)) < 1e-6 &&
                       fabs(NSMaxY(nearestPixels) - round(NSMaxY(nearestPixels))) < 1e-6,
               "aligned edges are on whole backing pixels");
        expect(NSContainsRect(outward, rect), "outward alignment contains the rect");
        expect(NSContainsRect(rect, inward), "inward alignment is inside the rect");
        if (scale == 1.0) {
            expect(sameRect(nearest, NSMakeRect(10, 21, 101, 50)), "nearest alignment of the sample rect");
            expect(sameRect(outward, NSMakeRect(10, 20, 101, 52)), "outward alignment of the sample rect");
        }

        expect([screen canRepresentDisplayGamut: NSDisplayGamutSRGB], "a screen can represent sRGB");
        expect(![screen canRepresentDisplayGamut: (NSDisplayGamut) 99], "an unknown gamut is not representable");
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
