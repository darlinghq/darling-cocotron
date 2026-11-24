// SPDX-License-Identifier: MIT
// Text drawn in a translucent colour blends with what is under it, whatever was drawn before: after an opaque
// fill the glyphs of a colour with alpha 0.25 are a light grey on white, not opaque black (the text of a disabled
// menu item is such a colour). The text is drawn into a bitmap, but the test needs a display for
// +sharedApplication (run it on Xvfb).
// Prints PASS, or FAIL lines and exit status 1.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

// The darkest red component of the bitmap, 0 (black) to 255 (white).
static int darkest(NSBitmapImageRep *rep) {
    int result = 255;
    unsigned char *data = [rep bitmapData];
    NSInteger bytesPerPixel = [rep bitsPerPixel] / 8, rowBytes = [rep bytesPerRow];
    for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
        for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
            int value = data[y * rowBytes + x * bytesPerPixel];
            if (value < result)
                result = value;
        }
    return result;
}

// Fills the bitmap with white using `fill`, then draws the text with `color` and returns the darkest pixel.
static int drawText(NSColor *color, void (^fill)(NSRect)) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 160 pixelsHigh: 30
                                                                 bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES
                                                                      isPlanar: NO
                                                                colorSpaceName: NSCalibratedRGBColorSpace
                                                                   bytesPerRow: 0 bitsPerPixel: 32];
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    fill(NSMakeRect(0, 0, 160, 30));
    NSDictionary *attributes = @{NSFontAttributeName : [NSFont systemFontOfSize: 14],
                                 NSForegroundColorAttributeName : color};
    [@"Disabled text" drawInRect: NSMakeRect(4, 4, 150, 20) withAttributes: attributes];
    [NSGraphicsContext restoreGraphicsState];
    int result = darkest(rep);
    [rep release];
    return result;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSColor *translucent = [NSColor colorWithSRGBRed: 0 green: 0 blue: 0 alpha: 0.25];
        void (^opaqueFill)(NSRect) = ^(NSRect rect) {
            [[NSColor whiteColor] setFill];
            NSRectFill(rect);
        };
        // A translucent fill selects the blending function, which is what reset the state in menus: the control.
        void (^translucentFillAfter)(NSRect) = ^(NSRect rect) {
            opaqueFill(rect);
            [[NSColor colorWithSRGBRed: 0 green: 0 blue: 0 alpha: 0.01] setFill];
            NSRectFillUsingOperation(NSMakeRect(0, 0, 1, 1), NSCompositeSourceOver);
        };

        // At alpha 0.25 over white no pixel is darker than 191; allow for rounding.
        expect(drawText(translucent, translucentFillAfter) >= 180,
               "translucent text after a translucent fill is light (control)");
        expect(drawText(translucent, opaqueFill) >= 180, "translucent text after an opaque fill is light");
        expect(drawText([NSColor blackColor], opaqueFill) <= 40, "opaque text after an opaque fill is black");
    }
    printf("translucent text after opaque fill: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
