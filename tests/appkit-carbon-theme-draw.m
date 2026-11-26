// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// The private AppKit functions _NSDrawCarbonThemeBezel(rect, enabled, flipped) and
// _NSDrawCarbonThemeListBox(rect, enabled, flipped, active): sunken frames drawn inside the rect, the inside left
// untouched. The pixel values are those the functions draw into a bitmap context on macOS 26.7.3 and Mac OS X
// 10.14.4 (identical on both; probe: mac-probes/gog-blockers/appkit-carbon-theme.m); the program builds and runs there
// too. The edge at the top of the rect (the largest y of an unflipped context, the smallest of a flipped one) is the
// darkest.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

extern void _NSDrawCarbonThemeBezel(NSRect rect, BOOL enabled, BOOL flipped);
extern void _NSDrawCarbonThemeListBox(NSRect rect, BOOL enabled, BOOL flipped, BOOL active);

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

typedef void (^Draw)(void);

// The grey value (red channel) at bitmap column x, row y (row 0 is the top of the bitmap) after drawing over `background`.
static NSBitmapImageRep *render(CGFloat background, Draw draw)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:40 pixelsHigh:30
                                                                 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
                                                                      isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    [[NSColor colorWithDeviceWhite:background alpha:1] set];
    NSRectFill(NSMakeRect(0, 0, 40, 30));
    draw();
    [context flushGraphics];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static int grey(NSBitmapImageRep *rep, int x, int y)
{
    return [rep bitmapData][y * [rep bytesPerRow] + x * 4];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect full = NSMakeRect(0, 0, 40, 30);

        NSBitmapImageRep *r = render(1, ^{ _NSDrawCarbonThemeBezel(full, YES, NO); });
        expect(grey(r, 20, 0) == 0x7c && grey(r, 20, 1) == 0xc3 && grey(r, 20, 2) == 0xff, "bezel, enabled: two edge lines at the top, then the inside");
        expect(grey(r, 0, 15) == 0xc3 && grey(r, 1, 15) == 0xf0 && grey(r, 2, 15) == 0xff, "bezel, enabled: the sides");
        expect(grey(r, 20, 29) == 0xdd && grey(r, 20, 28) == 0xfe, "bezel, enabled: the bottom");
        expect(grey(r, 0, 0) == 0x69 && grey(r, 39, 0) == 0x69 && grey(r, 0, 29) == 0xb9 && grey(r, 39, 29) == 0xb9, "bezel, enabled: the corners");
        expect(grey(r, 1, 1) == 0xb9 && grey(r, 38, 28) == 0xf0, "bezel, enabled: the inner corners");
        expect(grey(r, 20, 15) == 0xff, "bezel: the inside is not painted");

        r = render(1, ^{ _NSDrawCarbonThemeBezel(full, YES, YES); });
        expect(grey(r, 20, 29) == 0x7c && grey(r, 20, 28) == 0xc3 && grey(r, 20, 0) == 0xdd, "bezel, flipped: the dark edge is at the smallest y, which is the bottom of the bitmap here");

        r = render(1, ^{ _NSDrawCarbonThemeBezel(full, NO, NO); });
        expect(grey(r, 20, 0) == 0xbe && grey(r, 20, 1) == 0xe1 && grey(r, 0, 15) == 0xe1 && grey(r, 20, 29) == 0xee, "bezel, disabled: lighter lines");

        r = render(0.5, ^{ _NSDrawCarbonThemeBezel(NSMakeRect(5, 5, 30, 20), YES, NO); });
        expect(grey(r, 20, 4) == 0x80 && grey(r, 20, 25) == 0x80 && grey(r, 4, 15) == 0x80 && grey(r, 36, 15) == 0x80,
               "bezel: nothing outside the rect");
        expect(grey(r, 20, 5) == 0x7c && grey(r, 20, 6) == 0xc3 && grey(r, 20, 7) == 0x80, "bezel: drawn inside the rect, the inside is the background");

        r = render(1, ^{ _NSDrawCarbonThemeListBox(full, YES, NO, YES); });
        expect(grey(r, 20, 0) == 0x73 && grey(r, 20, 1) == 0xff, "list box, enabled: one dark line at the top");
        expect(grey(r, 0, 15) == 0x99 && grey(r, 39, 15) == 0x99 && grey(r, 20, 29) == 0x99, "list box, enabled: the sides and the bottom");
        expect(grey(r, 20, 15) == 0xff, "list box: the inside is not painted");

        r = render(1, ^{ _NSDrawCarbonThemeListBox(full, YES, YES, YES); });
        expect(grey(r, 20, 29) == 0x73 && grey(r, 20, 0) == 0x99, "list box, flipped: the dark edge is at the smallest y");

        r = render(1, ^{ _NSDrawCarbonThemeListBox(full, NO, NO, YES); });
        expect(grey(r, 20, 0) == 0x99 && grey(r, 0, 15) == 0xac, "list box, disabled: lighter lines");

        r = render(1, ^{ _NSDrawCarbonThemeListBox(full, YES, NO, NO); });
        expect(grey(r, 20, 0) == 0x8e && grey(r, 0, 15) == 0xbe, "list box, not active: lighter lines than the active one");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
