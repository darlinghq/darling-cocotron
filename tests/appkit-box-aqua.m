// Copyright (C) 2026 Lubos Dolezel
//
// Primary and secondary boxes look like the Aqua box of macOS 10.14 in the light appearance: a 4 point rounded
// rectangle tinted with 4% black and outlined, inset 3 points from the sides of the view and starting below the
// title. Expected values were sampled from renders of a 200 x 100 box titled "Title" on Mac OS X 10.14.4
// (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSBoxAqua) and NSBox).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void alphaOf(NSBitmapImageRep *rep, int x, int y, int *a) {
    *a = lround([[rep colorAtX: x y: y] alphaComponent] * 255);
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (int secondary = 0; secondary < 2; secondary++) {
            NSBox *box = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
            [box setBoxType: secondary ? NSBoxSecondary : NSBoxPrimary];
            [box setTitle: @"Title"];
            NSBitmapImageRep *rep = [box bitmapImageRepForCachingDisplayInRect: [box bounds]];
            [box cacheDisplayInRect: [box bounds] toBitmapImageRep: rep];
            int a;
            CHECK(![box isTransparent] && [box borderType] == NSGrooveBorder && [box titlePosition] == NSAtTop);
            // observed on macOS 10.14.4: the default title font is the 11 point system font
            CHECK([[box titleFont] pointSize] == 11);
            CHECK(NSEqualSizes([box contentViewMargins], NSMakeSize(5, 5)));
            CHECK(NSEqualRects([[box contentView] frame], NSMakeRect(8, 8, 184, 77)));

            // inside the box: about 4% black; outside the inset: nothing
            alphaOf(rep, 100, 50, &a);
            CHECK(a >= 6 && a <= 16);
            alphaOf(rep, 1, 50, &a);
            CHECK(a == 0);
            alphaOf(rep, 198, 50, &a);
            CHECK(a == 0);
            alphaOf(rep, 3, 50, &a);
            CHECK(a >= 10 && a <= 40);
            alphaOf(rep, 196, 50, &a);
            CHECK(a >= 10 && a <= 40);
            // rounded corner: the outermost pixel is empty
            alphaOf(rep, 3, 96, &a);
            CHECK(a < 10);
            // column in the middle: the box starts 14 points from the top and ends 4 from the bottom
            int first = -1, last = -1;
            for (int y = 0; y < 100; y++) {
                alphaOf(rep, 150, y, &a);
                if (a > 0) {
                    if (first < 0)
                        first = y;
                    last = y;
                }
            }
            CHECK(first >= 12 && first <= 16);
            CHECK(last >= 94 && last <= 96);
        }
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
