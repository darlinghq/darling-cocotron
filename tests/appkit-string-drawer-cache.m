/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * String drawing and sizing through the shared string drawer: repeated draws
 * of an unchanged string give identical pixels, different strings or
 * attributes are not confused for each other, and mutating a caller's
 * attribute dictionary after drawing does not change earlier results. Draws
 * into an offscreen bitmap; no window server needed.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSData *render(NSString *string, NSDictionary *attributes)
{
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL pixelsWide: 120 pixelsHigh: 30 bitsPerSample: 8
                     samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0];
    memset([rep bitmapData], 0xff, [rep bytesPerRow] * [rep pixelsHigh]);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    [string drawAtPoint: NSMakePoint(2, 2) withAttributes: attributes];
    [NSGraphicsContext restoreGraphicsState];
    return [NSData dataWithBytes: [rep bitmapData] length: [rep bytesPerRow] * [rep pixelsHigh]];
}

int main(void)
{
    @autoreleasepool {
        NSDictionary *plain = @{NSFontAttributeName: [NSFont systemFontOfSize: 12]};
        NSDictionary *big = @{NSFontAttributeName: [NSFont systemFontOfSize: 20]};

        NSData *first = render(@"Hello", plain);
        NSData *again = render(@"Hello", plain);
        expect([first isEqualToData: again], "a repeated draw of an unchanged string is identical");
        expect(![first isEqualToData: render(@"Hello!", plain)], "a different string draws differently");
        expect(![first isEqualToData: render(@"Hello", big)], "different attributes draw differently");

        NSSize small = [@"Hello" sizeWithAttributes: plain];
        NSSize large = [@"Hello" sizeWithAttributes: big];
        expect(large.width > small.width && large.height > small.height,
               "a larger font gives a larger size");
        expect([@"Hello" sizeWithAttributes: nil].width > 0, "nil attributes size with the default font");
        expect(NSEqualSizes([@"Hello" sizeWithAttributes: plain], small), "size is stable");
        expect([@"" sizeWithAttributes: plain].width == 0, "an empty string has no width");

        // A mutable dictionary changed after use must not change what was drawn.
        NSMutableDictionary *mutable = [plain mutableCopy];
        NSData *before = render(@"Mutable", mutable);
        [mutable setObject: [NSFont systemFontOfSize: 24] forKey: NSFontAttributeName];
        NSData *after = render(@"Mutable", mutable);
        expect(![before isEqualToData: after], "the changed dictionary draws with the new font");
        expect([before isEqualToData: render(@"Mutable", plain)],
               "the original attributes still draw as before");

        // A plain string and an attributed string with the same text and attributes size alike.
        NSAttributedString *attributed = [[NSAttributedString alloc] initWithString: @"Hello" attributes: plain];
        NSSize attributedSize = [attributed size];
        expect(fabs(attributedSize.width - small.width) < 1 && fabs(attributedSize.height - small.height) < 1,
               "an attributed string sizes like the plain one");
    }
    if (failures)
        return 1;
    puts("string drawer cache: PASS");
    return 0;
}
