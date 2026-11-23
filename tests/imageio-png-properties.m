// CFLAGS: -framework AppKit -framework ImageIO -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// CGImageSourceCopyPropertiesAtIndex of a PNG gives its size in pixels (kCGImagePropertyPixelWidth and
// kCGImagePropertyPixelHeight, as numbers). Observed on macOS 10.14.4 and 26.7.3, where this test passes unchanged.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static NSDictionary *properties(NSData *data)
{
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) data, NULL);
    if (source == NULL)
        return nil;
    NSDictionary *result = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return result;
}

static BOOL sizeIs(NSDictionary *props, NSInteger width, NSInteger height)
{
    id w = props[(__bridge NSString *) kCGImagePropertyPixelWidth], h = props[(__bridge NSString *) kCGImagePropertyPixelHeight];
    return [w isKindOfClass: [NSNumber class]] && [h isKindOfClass: [NSNumber class]] && [w integerValue] == width
        && [h integerValue] == height;
}

int main(void)
{
    @autoreleasepool {
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 5 pixelsHigh: 3
                                                                     bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES
                                                                          isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
                                                                       bytesPerRow: 0 bitsPerPixel: 0];
        NSDictionary *props = properties([rep representationUsingType: NSPNGFileType properties: @{}]);
        expect(sizeIs(props, 5, 3), [NSString stringWithFormat: @"a 5x3 PNG: PixelWidth 5, PixelHeight 3 (%@)", props]);

        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
