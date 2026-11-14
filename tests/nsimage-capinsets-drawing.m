// Copyright (C) 2026 Lubos Dolezel
// NSImage capInsets and resizingMode drawing: a 6x6 image whose pixels carry distinct ids is
// drawn into a bitmap rep and every destination pixel's id is compared with the grid macOS
// 26.7.3 produced for the same call ('.' where nothing is drawn). Sizes are chosen so that no
// destination pixel sits exactly on a boundary between two source pixels.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static NSImage *makeSource(void) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 6 pixelsHigh: 6
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: 24 bitsPerPixel: 32];
    unsigned char *d = [rep bitmapData];
    for (int y = 0; y < 6; y++)
        for (int x = 0; x < 6; x++) {
            unsigned char *p = d + y * 24 + x * 4;
            p[0] = (y * 6 + x + 1) * 6; p[1] = 0; p[2] = 0; p[3] = 255;
        }
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(6, 6)];
    [image addRepresentation: rep];
    return image;
}

static int failures;

static void checkDraw(const char *label, NSEdgeInsets caps, NSImageResizingMode mode, int w, int h, const char *expected) {
    NSImage *image = makeSource();
    image.capInsets = caps;
    image.resizingMode = mode;
    NSBitmapImageRep *dst = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: w + 2 pixelsHigh: h + 2
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: (w + 2) * 4 bitsPerPixel: 32];
    memset([dst bitmapData], 0, (w + 2) * (h + 2) * 4);
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: dst];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [ctx setImageInterpolation: NSImageInterpolationNone];
    [image drawInRect: NSMakeRect(1, 1, w, h) fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
    NSMutableString *grid = [NSMutableString string];
    unsigned char *d = [dst bitmapData];
    for (int y = 0; y < h + 2; y++) {
        for (int x = 0; x < w + 2; x++) {
            unsigned char *p = d + y * (w + 2) * 4 + x * 4;
            if (p[3] == 0) [grid appendString: @"  ."];
            else if (p[3] != 255) [grid appendFormat: @" a%02x", p[3]];
            else [grid appendFormat: @" %2d", (int) ((p[0] + 3) / 6)];
        }
        [grid appendString: @"\n"];
    }
    if (strcmp([grid UTF8String], expected) != 0) {
        printf("FAIL: %s\n--- got\n%s--- expected\n%s", label, [grid UTF8String], expected);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSEdgeInsets sym = {2, 2, 2, 2};
        NSEdgeInsets asym = {1, 2, 0, 3};
        NSEdgeInsets none = {0, 0, 0, 0};
        checkDraw("A stretch", sym, NSImageResizingModeStretch, 12, 10,
            "  .  .  .  .  .  .  .  .  .  .  .  .  .  .\n"
            "  .  1  2  3  3  3  3  4  4  4  4  5  6  .\n"
            "  .  7  8  9  9  9  9 10 10 10 10 11 12  .\n"
            "  . 13 14 15 15 15 15 16 16 16 16 17 18  .\n"
            "  . 13 14 15 15 15 15 16 16 16 16 17 18  .\n"
            "  . 13 14 15 15 15 15 16 16 16 16 17 18  .\n"
            "  . 19 20 21 21 21 21 22 22 22 22 23 24  .\n"
            "  . 19 20 21 21 21 21 22 22 22 22 23 24  .\n"
            "  . 19 20 21 21 21 21 22 22 22 22 23 24  .\n"
            "  . 25 26 27 27 27 27 28 28 28 28 29 30  .\n"
            "  . 31 32 33 33 33 33 34 34 34 34 35 36  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .  .  .  .\n");
        checkDraw("B tile", sym, NSImageResizingModeTile, 11, 9,
            "  .  .  .  .  .  .  .  .  .  .  .  .  .\n"
            "  .  1  2  3  4  3  4  3  4  3  5  6  .\n"
            "  .  7  8  9 10  9 10  9 10  9 11 12  .\n"
            "  . 19 20 21 22 21 22 21 22 21 23 24  .\n"
            "  . 13 14 15 16 15 16 15 16 15 17 18  .\n"
            "  . 19 20 21 22 21 22 21 22 21 23 24  .\n"
            "  . 13 14 15 16 15 16 15 16 15 17 18  .\n"
            "  . 19 20 21 22 21 22 21 22 21 23 24  .\n"
            "  . 25 26 27 28 27 28 27 28 27 29 30  .\n"
            "  . 31 32 33 34 33 34 33 34 33 35 36  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .  .  .\n");
        checkDraw("C stretch smaller than caps", sym, NSImageResizingModeStretch, 3, 3,
            "  .  .  .  .  .\n"
            "  .  1  5  6  .\n"
            "  .  7 11 12  .\n"
            "  . 31 35 36  .\n"
            "  .  .  .  .  .\n");
        checkDraw("D tile smaller than caps", sym, NSImageResizingModeTile, 3, 3,
            "  .  .  .  .  .\n"
            "  .  1  5  6  .\n"
            "  .  7 11 12  .\n"
            "  . 31 35 36  .\n"
            "  .  .  .  .  .\n");
        checkDraw("E stretch asymmetric", asym, NSImageResizingModeStretch, 10, 8,
            "  .  .  .  .  .  .  .  .  .  .  .  .\n"
            "  .  1  2  3  3  3  3  3  4  5  6  .\n"
            "  .  7  8  9  9  9  9  9 10 11 12  .\n"
            "  . 13 14 15 15 15 15 15 16 17 18  .\n"
            "  . 13 14 15 15 15 15 15 16 17 18  .\n"
            "  . 19 20 21 21 21 21 21 22 23 24  .\n"
            "  . 25 26 27 27 27 27 27 28 29 30  .\n"
            "  . 25 26 27 27 27 27 27 28 29 30  .\n"
            "  . 31 32 33 33 33 33 33 34 35 36  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .  .\n");
        checkDraw("F tile asymmetric", asym, NSImageResizingModeTile, 10, 8,
            "  .  .  .  .  .  .  .  .  .  .  .  .\n"
            "  .  1  2  3  3  3  3  3  4  5  6  .\n"
            "  . 25 26 27 27 27 27 27 28 29 30  .\n"
            "  . 31 32 33 33 33 33 33 34 35 36  .\n"
            "  .  7  8  9  9  9  9  9 10 11 12  .\n"
            "  . 13 14 15 15 15 15 15 16 17 18  .\n"
            "  . 19 20 21 21 21 21 21 22 23 24  .\n"
            "  . 25 26 27 27 27 27 27 28 29 30  .\n"
            "  . 31 32 33 33 33 33 33 34 35 36  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .  .\n");
        checkDraw("G stretch no caps", none, NSImageResizingModeStretch, 12, 12,
            "  .  .  .  .  .  .  .  .  .  .  .  .  .  .\n"
            "  .  1  1  2  2  3  3  4  4  5  5  6  6  .\n"
            "  .  1  1  2  2  3  3  4  4  5  5  6  6  .\n"
            "  .  7  7  8  8  9  9 10 10 11 11 12 12  .\n"
            "  .  7  7  8  8  9  9 10 10 11 11 12 12  .\n"
            "  . 13 13 14 14 15 15 16 16 17 17 18 18  .\n"
            "  . 13 13 14 14 15 15 16 16 17 17 18 18  .\n"
            "  . 19 19 20 20 21 21 22 22 23 23 24 24  .\n"
            "  . 19 19 20 20 21 21 22 22 23 23 24 24  .\n"
            "  . 25 25 26 26 27 27 28 28 29 29 30 30  .\n"
            "  . 25 25 26 26 27 27 28 28 29 29 30 30  .\n"
            "  . 31 31 32 32 33 33 34 34 35 35 36 36  .\n"
            "  . 31 31 32 32 33 33 34 34 35 35 36 36  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .  .  .  .\n");
        checkDraw("H tile no caps", none, NSImageResizingModeTile, 9, 9,
            "  .  .  .  .  .  .  .  .  .  .  .\n"
            "  . 19 20 21 22 23 24 19 20 21  .\n"
            "  . 25 26 27 28 29 30 25 26 27  .\n"
            "  . 31 32 33 34 35 36 31 32 33  .\n"
            "  .  1  2  3  4  5  6  1  2  3  .\n"
            "  .  7  8  9 10 11 12  7  8  9  .\n"
            "  . 13 14 15 16 17 18 13 14 15  .\n"
            "  . 19 20 21 22 23 24 19 20 21  .\n"
            "  . 25 26 27 28 29 30 25 26 27  .\n"
            "  . 31 32 33 34 35 36 31 32 33  .\n"
            "  .  .  .  .  .  .  .  .  .  .  .\n");
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
