// Copyright (C) 2026 Lubos Dolezel
//
// A bordered NSColorWell shows its colour inset 6 points from each edge, at any size, so even a small
// well (19 x 17) shows a usable swatch. Observed on macOS 10.14.4 (black-box: the red pixels of the middle
// row and column of wells of 19 x 17, 24 x 20, 44 x 23 and 52 x 28 points start 6 points from each edge).
// Passes on macOS 10.14.4.
//
// Build: clang -framework AppKit appkit-colorwell-swatch-inset.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static BOOL isRed(NSBitmapImageRep *rep, int x, int y) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    return [c redComponent] > 0.8 && [c greenComponent] < 0.3 && [c blueComponent] < 0.3;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        NSSize sizes[4] = {{19, 17}, {24, 20}, {44, 23}, {52, 28}};

        for (int s = 0; s < 4; s++) {
            NSColorWell *well = [[[NSColorWell alloc] initWithFrame: NSMakeRect(10, 10, sizes[s].width, sizes[s].height)] autorelease];
            [well setColor: [NSColor redColor]];
            [[window contentView] addSubview: well];

            NSBitmapImageRep *rep = [well bitmapImageRepForCachingDisplayInRect: [well bounds]];
            [well cacheDisplayInRect: [well bounds] toBitmapImageRep: rep];
            CGFloat scale = [rep pixelsWide] / sizes[s].width;
            int first = -1, last = -1, top = -1, bottom = -1;
            for (int x = 0; x < [rep pixelsWide]; x++)
                if (isRed(rep, x, (int) [rep pixelsHigh] / 2)) {
                    if (first < 0)
                        first = x;
                    last = x;
                }
            for (int y = 0; y < [rep pixelsHigh]; y++)
                if (isRed(rep, (int) [rep pixelsWide] / 2, y)) {
                    if (top < 0)
                        top = y;
                    bottom = y;
                }
            printf("well %g x %g: red columns %.1f..%.1f, rows %.1f..%.1f\n", sizes[s].width, sizes[s].height,
                   first / scale, (last + 1) / scale, top / scale, (bottom + 1) / scale);
            CHECK(first >= 0 && fabs(first / scale - 6) <= 1);
            CHECK(fabs((last + 1) / scale - (sizes[s].width - 6)) <= 1);
            CHECK(top >= 0 && fabs(top / scale - 6) <= 1);
            CHECK(fabs((bottom + 1) / scale - (sizes[s].height - 6)) <= 1);
            [well removeFromSuperview];
        }
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
