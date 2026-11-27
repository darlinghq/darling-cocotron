// Copyright (C) 2026 Lubos Dolezel
//
// A JPEG image of a compiled asset catalog. The fixture tests/fixtures/assetcatalog/Assets-jpeg.car was compiled
// with actool (Xcode 26, --platform macosx --minimum-deployment-target 10.14) from the image set that
// fixtures/assetcatalog/make-xcassets-jpeg.py writes; assetutil --info reports its rendition with the encoding
// "JPEG", 32 x 24 pixels, scale 1. actool keeps a JPEG file as the JPEG bytes (in the same wrapper a PDF
// rendition has) instead of decoding it into pixels, so the catalog has to decode the JPEG itself.
// Expected values: the image is 32 x 24 points, its top half solid red and its bottom half solid blue (what the
// script draws; the JPEG is lossy, so each channel may differ by a few levels).
// Usage: appkit-asset-catalog-jpeg <path of Assets-jpeg.car>
// Build: clang -framework AppKit appkit-asset-catalog-jpeg.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *makeBundle(const char *car) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"CatalogJpeg-%d.bundle", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"Contents/Resources"] withIntermediateDirectories: YES
                   attributes: nil error: NULL];
    [fm copyItemAtPath: [NSString stringWithUTF8String: car]
                toPath: [dir stringByAppendingPathComponent: @"Contents/Resources/Assets.car"] error: NULL];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
            @"org.darlinghq.test.assetcatalog.jpeg", @"CFBundleIdentifier", @"CatalogJpeg", @"CFBundleName",
            @"BNDL", @"CFBundlePackageType", nil];
    [info writeToFile: [dir stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
    return dir;
}

static NSBitmapImageRep *render(NSImage *image) {
    NSInteger w = (NSInteger) [image size].width, h = (NSInteger) [image size].height;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: w pixelsHigh: h
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: w * 4 bitsPerPixel: 32] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: NSMakeRect(0, 0, w, h) fromRect: NSZeroRect operation: NSCompositingOperationCopy fraction: 1];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static BOOL pixelIs(NSBitmapImageRep *rep, int x, int y, int r, int g, int b) {
    const unsigned char *p = [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
    BOOL ok = abs(p[0] - r) <= 12 && abs(p[1] - g) <= 12 && abs(p[2] - b) <= 12 && p[3] == 255;
    if (!ok)
        fprintf(stderr, "  pixel (%d, %d) is %d,%d,%d,%d, expected %d,%d,%d,255\n", x, y, p[0], p[1], p[2], p[3], r, g, b);
    return ok;
}

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    if (argc < 2) {
        fprintf(stderr, "usage: appkit-asset-catalog-jpeg <Assets-jpeg.car>\n");
        return 2;
    }
    NSString *dir = makeBundle(argv[1]);
    NSBundle *bundle = [NSBundle bundleWithPath: dir];

    NSImage *image = [bundle imageForResource: @"Jpeg"];
    CHECK(image != nil);
    if (image != nil) {
        CHECK(fabs([image size].width - 32) < 0.01 && fabs([image size].height - 24) < 0.01);
        NSBitmapImageRep *pixels = render(image);
        CHECK(pixelIs(pixels, 2, 2, 255, 0, 0));
        CHECK(pixelIs(pixels, 28, 9, 255, 0, 0));
        CHECK(pixelIs(pixels, 2, 14, 0, 0, 255));
        CHECK(pixelIs(pixels, 28, 21, 0, 0, 255));
    }

    CHECK([bundle imageForResource: @"Missing"] == nil);
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
    if (failures == 0)
        printf("PASS appkit-asset-catalog-jpeg\n");
    [pool release];
    return failures != 0;
}
