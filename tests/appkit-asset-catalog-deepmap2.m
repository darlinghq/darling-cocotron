// Copyright (C) 2026 Lubos Dolezel
//
// Images of a compiled asset catalog that was built for a recent deployment target. The fixture
// tests/fixtures/assetcatalog/Assets-deepmap2.car was compiled with actool (Xcode 26, --platform macosx
// --minimum-deployment-target 26.0) from the image sets that fixtures/assetcatalog/make-xcassets-deepmap2.py
// writes. For that target actool compresses bitmaps with the "deepmap2" compression (assetutil --info reports
// it; the data is an LZFSE stream behind a header) instead of plain LZFSE or run-length encoding, packs the
// small images into a shared image, and keeps the vector image as an SVG rendition (a PDF only for older
// targets). Expected values are from black-box runs of this test on macOS 26.7.3 (x86_64).
//  - twelve small opaque images Pack0..Pack11 (sizes (12 + i) x (10 + i % 3) points) whose pixels all differ
//    from their neighbours (colour = bytes of hash(i, x, y), see hash_rgb in
//    fixtures/assetcatalog/make-xcassets-deepmap2.py), packed into one shared image: every pixel has to come from the
//    right place of the packed image, so a reader that takes a frame from the wrong corner shows another
//    image's pixels;
//  - PackGA, 64 x 64 black with alpha the second byte of hash(100, x, y) (the compressed data keeps the alpha in a
//    plane of its own);
//  - Vec, an SVG 20 x 20 points: a red square from 2 to 18 and a blue square from 6 to 14 on a clear background.
//    (The deepmap2 compression has more than one form: an image of a single colour or a regular one is stored
//    in a shorter form than the LZFSE stream these pixels need, and this test does not cover it.)
// Usage: appkit-asset-catalog-deepmap2 <path of Assets-deepmap2.car>
// Build: clang -framework AppKit appkit-asset-catalog-deepmap2.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *makeBundle(const char *car) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"CatalogDeepmap2-%d.bundle", getpid()]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"Contents/Resources"] withIntermediateDirectories: YES
                   attributes: nil error: NULL];
    [fm copyItemAtPath: [NSString stringWithUTF8String: car]
                toPath: [dir stringByAppendingPathComponent: @"Contents/Resources/Assets.car"] error: NULL];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
            @"org.darlinghq.test.assetcatalog.deepmap2", @"CFBundleIdentifier", @"CatalogDeepmap2", @"CFBundleName",
            @"BNDL", @"CFBundlePackageType", nil];
    [info writeToFile: [dir stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
    return dir;
}

// The image drawn 1:1 into an RGBA bitmap of its size; pixel (x, y) from the top left.
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

static BOOL pixelIs(NSBitmapImageRep *rep, int x, int y, int r, int g, int b, int a) {
    const unsigned char *p = [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
    BOOL ok = abs(p[0] - r) <= 3 && abs(p[1] - g) <= 3 && abs(p[2] - b) <= 3 && abs(p[3] - a) <= 3;
    if (!ok)
        fprintf(stderr, "  pixel (%d, %d) is %d,%d,%d,%d, expected %d,%d,%d,%d\n", x, y, p[0], p[1], p[2], p[3], r, g, b, a);
    return ok;
}

// The colour bytes of pixel (x, y) of image k, as in make-xcassets-deepmap2.py.
static uint32_t hashOf(int k, int x, int y) {
    return ((uint32_t) x * 73856093u) ^ ((uint32_t) y * 19349663u) ^ ((uint32_t) k * 83492791u);
}

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    if (argc < 2) {
        fprintf(stderr, "usage: appkit-asset-catalog-deepmap2 <Assets-deepmap2.car>\n");
        return 2;
    }
    NSString *dir = makeBundle(argv[1]);
    NSBundle *bundle = [NSBundle bundleWithPath: dir];

    for (int i = 0; i < 12; i++) {
        NSImage *image = [bundle imageForResource: [NSString stringWithFormat: @"Pack%d", i]];
        CHECK(image != nil);
        if (image == nil)
            continue;
        int w = 12 + i, h = 10 + (i % 3);
        CHECK(fabs([image size].width - w) < 0.01 && fabs([image size].height - h) < 0.01);
        NSBitmapImageRep *pixels = render(image);
        int bad = 0;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                uint32_t hash = hashOf(i, x, y);
                const unsigned char *p = [pixels bitmapData] + y * [pixels bytesPerRow] + x * 4;
                if (abs(p[0] - (int) (hash & 255)) > 3 || abs(p[1] - (int) ((hash >> 8) & 255)) > 3 ||
                    abs(p[2] - (int) ((hash >> 16) & 255)) > 3 || p[3] != 255)
                    bad++;
            }
        if (bad != 0)
            fprintf(stderr, "  Pack%d: %d of %d pixels are wrong\n", i, bad, w * h);
        CHECK(bad == 0);
    }

    NSImage *grey = [bundle imageForResource: @"PackGA"];
    CHECK(grey != nil && fabs([grey size].width - 64) < 0.01 && fabs([grey size].height - 64) < 0.01);
    if (grey != nil) {
        NSBitmapImageRep *pixels = render(grey);
        int bad = 0;
        for (int y = 0; y < 64; y++)
            for (int x = 0; x < 64; x++) {
                const unsigned char *p = [pixels bitmapData] + y * [pixels bytesPerRow] + x * 4;
                int alpha = (int) ((hashOf(100, x, y) >> 8) & 255);
                if (p[0] > 3 || p[1] > 3 || p[2] > 3 || abs(p[3] - alpha) > 3)
                    bad++;
            }
        if (bad != 0)
            fprintf(stderr, "  PackGA: %d of 4096 pixels are wrong\n", bad);
        CHECK(bad == 0);
    }

    NSImage *vector = [bundle imageForResource: @"Vec"];
    CHECK(vector != nil && fabs([vector size].width - 20) < 0.01 && fabs([vector size].height - 20) < 0.01);
    if (vector != nil) {
        NSBitmapImageRep *pixels = render(vector);
        CHECK(pixelIs(pixels, 0, 0, 0, 0, 0, 0));
        CHECK(pixelIs(pixels, 3, 3, 255, 0, 0, 255));
        CHECK(pixelIs(pixels, 16, 3, 255, 0, 0, 255));
        CHECK(pixelIs(pixels, 10, 10, 0, 0, 255, 255));
        CHECK(pixelIs(pixels, 19, 19, 0, 0, 0, 0));
    }

    CHECK([bundle imageForResource: @"Missing"] == nil);
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
    if (failures == 0)
        printf("PASS appkit-asset-catalog-deepmap2\n");
    [pool release];
    return failures != 0;
}
