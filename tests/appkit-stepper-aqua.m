// Copyright (C) 2026 Lubos Dolezel
//
// A stepper looks like the Aqua one of macOS 10.14 in the light appearance: one white capsule with a gray outline and
// a dark chevron in its upper and lower half. -sizeToFit gives the stepper's own size (19 x 27 points at the regular
// size). Expected values were sampled from renders on Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing
// in NSGraphicsStyle (NSStepperAqua) and NSStepperCell).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void rgba(NSBitmapImageRep *rep, int x, int y, int *c) {
    NSColor *color = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    c[0] = lround([color redComponent] * 255);
    c[1] = lround([color greenComponent] * 255);
    c[2] = lround([color blueComponent] * 255);
    c[3] = lround([color alphaComponent] * 255);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        static const struct { NSControlSize size; int w, h, bodyW, bodyH, inset; } sizes[] = {
            { NSControlSizeRegular, 19, 27, 13, 21, 3 }, { NSControlSizeSmall, 15, 22, 11, 18, 2 },
            { NSControlSizeMini, 13, 15, 9, 14, 2 }
        };
        for (int i = 0; i < 3; i++) {
            NSStepper *stepper = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
            [[stepper cell] setControlSize: sizes[i].size];
            [stepper sizeToFit];
            CHECK([stepper frame].size.width == sizes[i].w && [stepper frame].size.height == sizes[i].h);
            NSBitmapImageRep *rep = [stepper bitmapImageRepForCachingDisplayInRect: [stepper bounds]];
            [stepper cacheDisplayInRect: [stepper bounds] toBitmapImageRep: rep];
            int c[4], mid = sizes[i].h / 2;

            // the capsule: white in the middle row away from the chevrons (near its left side), nothing outside
            rgba(rep, sizes[i].inset + 2, mid, c);
            CHECK(c[0] > 245 && c[1] > 245 && c[2] > 245 && c[3] == 255);
            rgba(rep, 0, mid, c);
            CHECK(c[3] == 0);
            // the width of the capsule across the middle row
            int first = -1, last = -1;
            for (int x = 0; x < sizes[i].w; x++) {
                rgba(rep, x, mid, c);
                if (c[3] > 20) {
                    if (first < 0)
                        first = x;
                    last = x;
                }
            }
            CHECK(last - first + 1 >= sizes[i].bodyW - 1 && last - first + 1 <= sizes[i].bodyW + 1);
            // dark chevron pixels in both halves
            int upper = 0, lower = 0;
            for (int x = 0; x < sizes[i].w; x++)
                for (int y = 0; y < sizes[i].h; y++) {
                    rgba(rep, x, y, c);
                    if (c[3] > 200 && c[0] < 110) {
                        if (y < mid)
                            upper++;
                        else
                            lower++;
                    }
                }
            CHECK(upper >= 4 && lower >= 4);
        }
        // a disabled stepper is fainter
        NSStepper *disabled = [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 19, 27)];
        [disabled setEnabled: NO];
        NSBitmapImageRep *rep = [disabled bitmapImageRepForCachingDisplayInRect: [disabled bounds]];
        [disabled cacheDisplayInRect: [disabled bounds] toBitmapImageRep: rep];
        int c[4], dark = 0;
        for (int x = 0; x < 19; x++)
            for (int y = 0; y < 27; y++) {
                rgba(rep, x, y, c);
                dark += c[3] > 200 && c[0] < 110;
            }
        CHECK(dark == 0);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
