// Copyright (C) 2026 Lubos Dolezel
//
// The modifier and key symbols a menu shows next to a key equivalent (Command, Option, Shift, Control, Tab) are
// drawn as large as the letter beside them. Draws each symbol and the letter "O" in the menu font into a bitmap
// and requires the ink height of Command to be at least 80% and of Option and Shift 70% of the letter's. Control and Tab are
// short glyphs by design (about 55% of the letter on a Mac), so for them the bounds are 25% and 35%; they catch a missing
// glyph but not the size.
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSRect inkBounds(NSString *text, NSFont *font) {
    const int w = 64, h = 64;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: w pixelsHigh: h
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: w * 4 bitsPerPixel: 32];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [[NSColor whiteColor] set];
    NSRectFill(NSMakeRect(0, 0, w, h));
    NSDictionary *attrs = @{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor blackColor]};
    [text drawAtPoint: NSMakePoint(16, 16) withAttributes: attrs];
    [NSGraphicsContext restoreGraphicsState];

    int minY = h, maxY = -1, minX = w, maxX = -1;
    unsigned char *data = [rep bitmapData];
    for (int y = 0; y < h; y++)
        for (int x = 0; x < w; x++) {
            unsigned char *p = data + y * [rep bytesPerRow] + x * 4;
            if (p[0] < 160) {
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
            }
        }
    [rep release];
    if (maxY < 0)
        return NSZeroRect;
    return NSMakeRect(minX, minY, maxX - minX + 1, maxY - minY + 1);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        int failures = 0;
        NSFont *font = [NSFont menuFontOfSize: 0];
        double letter = inkBounds(@"O", font).size.height;
        if (letter < 4) {
            fprintf(stderr, "FAIL: letter O drew no ink\n");
            return 1;
        }
        NSString *symbols[] = {@"⌘", @"⌥", @"⇧", @"⌃", @"⇥"};
        double minimum[] = {0.8, 0.7, 0.7, 0.25, 0.35};
        for (int i = 0; i < 5; i++) {
            NSRect ink = inkBounds(symbols[i], font);
            printf("U+%04X ink %gx%g letter height %g\n", [symbols[i] characterAtIndex: 0], ink.size.width,
                   ink.size.height, letter);
            if (ink.size.height < letter * minimum[i]) {
                fprintf(stderr, "FAIL: U+%04X is %g high, the letter %g\n", [symbols[i] characterAtIndex: 0],
                        ink.size.height, letter);
                failures++;
            }
        }
        if (failures == 0)
            printf("PASS\n");
        return failures ? 1 : 0;
    }
}
