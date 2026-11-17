// Copyright (C) 2026 Lubos Dolezel
//
// A stepper draws a small solid triangle in each of its two buttons: pointing up in the upper one and down
// in the lower one (a few pixels wide and tall, widest at the base). It must not draw glyphs of a font that
// the platform lacks. The arrows are found by their dark pixels inside each half, away from the bezel.
// Checked on macOS 10.14.4 and 26.7.3.
//
// Build: clang -fobjc-arc -framework AppKit appkit-stepper-arrows-drawn.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The darkness of each row in x range [x0, x1) of rows [y0, y1), antialiased pixels counting partly;
// returns the number of rows that have any.
static int darkRows(NSBitmapImageRep *rep, int x0, int x1, int y0, int y1, double widths[32]) {
    int rows = 0;
    for (int y = y0; y < y1; y++) {
        double n = 0;
        for (int x = x0; x < x1; x++) {
            NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            double l = ([c redComponent] + [c greenComponent] + [c blueComponent]) / 3;
            if (l < 0.5) n += 1 - l;
        }
        if (n > 0 && rows < 32) widths[rows++] = n;
    }
    return rows;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(0, 0, 19, 27)];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 60, 60) styleMask:NSWindowStyleMaskBorderless
                                                         backing:NSBackingStoreBuffered defer:NO];
        [[window contentView] addSubview:stepper];
        NSBitmapImageRep *rep = [stepper bitmapImageRepForCachingDisplayInRect:[stepper bounds]];
        [stepper cacheDisplayInRect:[stepper bounds] toBitmapImageRep:rep];
        int w = (int)[rep pixelsWide], h = (int)[rep pixelsHigh];

        double upper[32], lower[32];
        // Bitmap row 0 is the top. Inner area of each half: clear of the bezel and of the divider.
        int upperRows = darkRows(rep, 6, w - 6, 4, h / 2 - 3, upper);
        int lowerRows = darkRows(rep, 6, w - 6, h / 2 + 3, h - 5, lower);
        if (getenv("VERBOSE")) {
            for (int i = 0; i < upperRows; i++) fprintf(stderr, "upper row %d: %.2f\n", i, upper[i]);
            for (int i = 0; i < lowerRows; i++) fprintf(stderr, "lower row %d: %.2f\n", i, lower[i]);
        }
        CHECK(upperRows >= 2 && upperRows <= 6);
        CHECK(lowerRows >= 2 && lowerRows <= 6);
        // Up arrow: the first (top) dark row is narrower than the last. Down arrow: the other way round.
        CHECK(upperRows >= 2 && upper[0] < upper[upperRows - 1]);
        CHECK(lowerRows >= 2 && lower[0] > lower[lowerRows - 1]);
        for (int i = 0; i < upperRows; i++) CHECK(upper[i] <= 9);
        for (int i = 0; i < lowerRows; i++) CHECK(lower[i] <= 9);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
