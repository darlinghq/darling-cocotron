// Copyright (C) 2026 Darling Developers
//
// Images of an asset catalog whose trees have several leaves. The fixture
// tests/fixtures/assetcatalog/Assets-multileaf.car is written by fixtures/assetcatalog/make-multileaf-car.py (a hand
// written store of uncompressed bitmaps, not compiled by actool). Its FACETKEYS tree has two leaves under a root
// node, and its RENDITIONS tree has four leaves in three levels: a root over two inner nodes, each over two leaves.
// The images are spread over the leaves, so every one of them is found only by a reader that follows the whole
// tree, not only its first or its first few children. The expected names, sizes and pixels below are the ones the
// generator's comment defines; they are not observations of macOS.
//  - test_every_leaf: -[NSBundle imageForResource:] of a bundle with the catalog finds every image of the catalog:
//    Red (2 x 2, red), Gradient (4 x 2, eight different colors), Gray (3 x 2, a template, gray levels and one clear
//    pixel), Blue (1 x 1, blue) and Green (2 x 1, green and yellow). Each has its size at scale 1 and its exact
//    pixels. A name that is not in the catalog gives nil.
// Usage: appkit-asset-catalog-multileaf <path of Assets-multileaf.car>
// Build: clang -framework AppKit appkit-asset-catalog-multileaf.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *makeBundle(const char *car) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"MultiLeafFixture-%d.bundle", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"Contents/Resources"] withIntermediateDirectories: YES
                   attributes: nil error: NULL];
    [fm copyItemAtPath: [NSString stringWithUTF8String: car]
                toPath: [dir stringByAppendingPathComponent: @"Contents/Resources/Assets.car"] error: NULL];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
            @"org.darlinghq.test.assetcatalog.multileaf", @"CFBundleIdentifier", @"MultiLeafFixture", @"CFBundleName",
            @"BNDL", @"CFBundlePackageType", nil];
    [info writeToFile: [dir stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
    return dir;
}

// The image drawn at one bitmap pixel per image pixel of the given size, pixel (x, y) from the top left; nil if
// there is no image, so that a missing image fails its checks instead of ending the test.
static NSBitmapImageRep *render(NSImage *image, NSInteger width, NSInteger height) {
    if (image == nil)
        return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: width pixelsHigh: height
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: width * 4 bitsPerPixel: 32] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: NSMakeRect(0, 0, width, height) fromRect: NSZeroRect operation: NSCompositingOperationCopy fraction: 1];
    [NSGraphicsContext restoreGraphicsState];
    return rep;
}

static BOOL pixelIs(NSBitmapImageRep *rep, int x, int y, int r, int g, int b, int a) {
    if (rep == nil) {
        fprintf(stderr, "  no image for pixel (%d, %d)\n", x, y);
        return NO;
    }
    const unsigned char *p = [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
    BOOL ok = abs(p[0] - r) <= 3 && abs(p[1] - g) <= 3 && abs(p[2] - b) <= 3 && abs(p[3] - a) <= 3;
    if (!ok)
        fprintf(stderr, "  pixel (%d, %d) is %d,%d,%d,%d, expected %d,%d,%d,%d\n", x, y, p[0], p[1], p[2], p[3], r, g, b, a);
    return ok;
}

static BOOL sizeIs(NSImage *image, CGFloat width, CGFloat height) {
    return image != nil && fabs([image size].width - width) < 0.01 && fabs([image size].height - height) < 0.01;
}

static void test_every_leaf(const char *car) {
    NSString *dir = makeBundle(car);
    NSBundle *bundle = [NSBundle bundleWithPath: dir];

    NSImage *red = [bundle imageForResource: @"Red"];
    CHECK(sizeIs(red, 2, 2));
    CHECK(red != nil && ![red isTemplate]);
    NSBitmapImageRep *pixels = render(red, 2, 2);
    for (int y = 0; y < 2; y++)
        for (int x = 0; x < 2; x++)
            CHECK(pixelIs(pixels, x, y, 255, 0, 0, 255));

    NSImage *gradient = [bundle imageForResource: @"Gradient"];
    CHECK(sizeIs(gradient, 4, 2));
    pixels = render(gradient, 4, 2);
    CHECK(pixelIs(pixels, 0, 0, 255, 0, 0, 255));
    CHECK(pixelIs(pixels, 1, 0, 0, 255, 0, 255));
    CHECK(pixelIs(pixels, 2, 0, 0, 0, 255, 255));
    CHECK(pixelIs(pixels, 3, 0, 255, 255, 255, 255));
    CHECK(pixelIs(pixels, 0, 1, 0, 0, 0, 255));
    CHECK(pixelIs(pixels, 1, 1, 255, 255, 0, 255));
    CHECK(pixelIs(pixels, 2, 1, 0, 255, 255, 255));
    CHECK(pixelIs(pixels, 3, 1, 255, 0, 255, 255));

    NSImage *gray = [bundle imageForResource: @"Gray"];
    CHECK(sizeIs(gray, 3, 2));
    CHECK(gray != nil && [gray isTemplate]);
    pixels = render(gray, 3, 2);
    CHECK(pixelIs(pixels, 0, 0, 0, 0, 0, 255));
    CHECK(pixelIs(pixels, 1, 0, 128, 128, 128, 255));
    CHECK(pixelIs(pixels, 2, 0, 255, 255, 255, 255));
    CHECK(pixelIs(pixels, 0, 1, 64, 64, 64, 255));
    CHECK(pixelIs(pixels, 1, 1, 192, 192, 192, 255));
    CHECK(pixelIs(pixels, 2, 1, 0, 0, 0, 0));

    // The last leaf of both trees holds two images.
    NSImage *blue = [bundle imageForResource: @"Blue"];
    CHECK(sizeIs(blue, 1, 1));
    CHECK(blue != nil && ![blue isTemplate]);
    CHECK(pixelIs(render(blue, 1, 1), 0, 0, 0, 0, 255, 255));

    NSImage *green = [bundle imageForResource: @"Green"];
    CHECK(sizeIs(green, 2, 1));
    pixels = render(green, 2, 1);
    CHECK(pixelIs(pixels, 0, 0, 0, 255, 0, 255));
    CHECK(pixelIs(pixels, 1, 0, 255, 255, 0, 255));

    CHECK([bundle imageForResource: @"Missing"] == nil);
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    if (argc < 2) {
        fprintf(stderr, "usage: appkit-asset-catalog-multileaf <Assets-multileaf.car>\n");
        return 2;
    }
    RUN(test_every_leaf(argv[1]));
    if (failures == 0)
        printf("PASS appkit-asset-catalog-multileaf\n");
    [pool release];
    return failures != 0;
}
