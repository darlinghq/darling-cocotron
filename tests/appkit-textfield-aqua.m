// Copyright (C) 2026 Lubos Dolezel
//
// Text fields and search fields look like the Aqua ones of macOS 10.14 in the light appearance: a white bezel with a
// one point outline of black at 20%, square for a text field and rounded for a search field, which also has a
// magnifying glass at its left and, when it has text, a gray cancel disc at its right. Expected values were sampled
// from renders of 140 x 22 fields on Mac OS X 10.14.4 (black-box observation; QUIRK-tagged drawing in
// NSGraphicsStyle (NSTextField, NSSearchFieldAqua) and NSSearchFieldCell).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSBitmapImageRep *render(NSView *view) {
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect: [view bounds]];
    [view cacheDisplayInRect: [view bounds] toBitmapImageRep: rep];
    return rep;
}

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
        int c[4];

        NSTextField *field = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
        [field setStringValue: @"Text"];
        NSBitmapImageRep *rep = render(field);
        // the outline is black at 20% on all sides, the inside white, the corners square
        for (int i = 0; i < 4; i++) {
            int x = i < 2 ? 70 : (i == 2 ? 0 : 139), y = i == 0 ? 0 : (i == 1 ? 21 : 11);
            rgba(rep, x, y, c);
            CHECK(c[3] > 35 && c[3] < 70);
        }
        rgba(rep, 0, 0, c);
        CHECK(c[3] > 35 && c[3] < 70);
        rgba(rep, 60, 3, c);
        CHECK(c[0] > 250 && c[1] > 250 && c[2] > 250 && c[3] == 255);
        rgba(rep, 138, 11, c);
        CHECK(c[0] > 250 && c[3] == 255);

        // a search field: rounded corners (the corner pixel is empty or faint), white inside, a dark magnifying
        // glass at the left, no cancel disc while empty
        NSSearchField *search = [[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 140, 22)];
        rep = render(search);
        rgba(rep, 0, 0, c);
        CHECK(c[3] < 30);
        rgba(rep, 70, 0, c);
        CHECK(c[3] > 35 && c[3] < 70);
        rgba(rep, 100, 11, c);
        CHECK(c[0] > 250 && c[3] == 255);
        int dark = 0;
        for (int x = 4; x < 18; x++)
            for (int y = 4; y < 18; y++) {
                rgba(rep, x, y, c);
                dark += c[3] > 200 && c[0] < 140;
            }
        CHECK(dark >= 8);
        // the right end is plain white while empty
        int gray = 0;
        for (int x = 120; x < 134; x++)
            for (int y = 4; y < 18; y++) {
                rgba(rep, x, y, c);
                gray += c[0] < 200;
            }
        CHECK(gray == 0);
        [search setStringValue: @"query"];
        rep = render(search);
        gray = 0;
        for (int x = 120; x < 134; x++)
            for (int y = 4; y < 18; y++) {
                rgba(rep, x, y, c);
                gray += c[0] < 170 && c[0] > 90 && c[3] == 255;
            }
        CHECK(gray > 60);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
