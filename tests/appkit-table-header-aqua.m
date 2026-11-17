// Copyright (C) 2026 Lubos Dolezel
//
// Table header cells look like the Aqua ones of macOS 10.14 in the light appearance: white with a light gray
// line along the top and bottom edge and a short separator at the left edge of every column but the first.
// Expected values were sampled from a render of a 300 x 17 header with three 100 point columns on Mac OS X 10.14.4
// (black-box observation; QUIRK-tagged drawing in NSGraphicsStyle (NSTableView)).
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
        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        for (int i = 0; i < 3; i++) {
            NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]];
            [column setTitle: @"Title"];
            [column setWidth: 100];
            [table addTableColumn: column];
        }
        NSView *header = [table headerView];
        [header setFrameSize: NSMakeSize(300, [header frame].size.height)];
        NSBitmapImageRep *rep = [header bitmapImageRepForCachingDisplayInRect: [header bounds]];
        [header cacheDisplayInRect: [header bounds] toBitmapImageRep: rep];
        int h = (int) [rep pixelsHigh], c[4];

        // the header is 17 points high on macOS (the view's default frame height)
        CHECK(h >= 15 && h <= 23);
        // white inside, away from the titles
        rgba(rep, 1, 8, c);
        CHECK(c[3] == 255 && c[0] >= 250 && c[1] >= 250 && c[2] >= 250);
        // light gray lines along the top and the bottom edge (colour management shifts the gray by a few values)
        for (int x = 0; x < 2; x++) {
            rgba(rep, 1 + x * 150, 0, c);
            CHECK(c[3] == 255 && abs(c[0] - 214) <= 14);
            rgba(rep, 1 + x * 150, h - 1, c);
            CHECK(c[3] == 255 && abs(c[0] - 214) <= 14);
        }
        // the separator is at the left edge of the second column (x 102 with the column spacing) and shorter
        int sep = -1;
        for (int x = 90; x < 112 && sep < 0; x++) {
            rgba(rep, x, 4, c);
            if (c[0] < 245 && c[0] > 215)
                sep = x;
        }
        CHECK(sep >= 100 && sep <= 104);
        rgba(rep, sep, 1, c);
        CHECK(c[0] > 245 || abs(c[0] - 214) <= 14);
        rgba(rep, sep, 8, c);
        CHECK(abs(c[0] - 229) <= 12);
        // no separator at the left edge of the first column
        rgba(rep, 0, 8, c);
        CHECK(c[0] > 245);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
