// Copyright (C) 2026 Lubos Dolezel
//
// Images of a compiled asset catalog. The fixture tests/fixtures/assetcatalog/Assets.car was compiled with actool
// (Xcode 26, --platform macosx --minimum-deployment-target 10.13) from the image sets that
// fixtures/assetcatalog/make-xcassets.py writes. It stores them as run-length encoded and LZFSE-compressed
// bitmaps, small ones packed into a shared image, and a PDF. Expected values are from black-box runs of this test
// on macOS 26.7.3 (x86_64) and Mac OS X 10.14.4 (i386).
//  - test_bundle_images: -[NSBundle imageForResource:] of a bundle with the catalog gives each image set at its
//    point size, with a bitmap of the right pixel size for each scale, and with the right pixels: Halves (20 x 10,
//    1x and 2x, red top half, blue bottom half), Translucent (green at half alpha), Gray (gray left half, clear right
//    half), Large (300 x 200), Vector (a red square, with a PDF representation), Template (a template image; the
//    others are not). A name that is not in the catalog gives nil.
//  - test_main_bundle (run in a copy of this program inside an application bundle with the catalog):
//    +[NSImage imageNamed:] finds the image set and the image has that name. Skipped with --no-application (on
//    Mac OS X 10.14 the copy, launched over ssh, does not finish starting up; macOS 26.7.3 passes it).
// Usage: appkit-asset-catalog-images <path of Assets.car> [--no-application]
// Build: clang -framework AppKit appkit-asset-catalog-images.m (no ARC)
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *makeBundle(const char *car, NSString *name, BOOL application) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"%@-%d.%@", name, getpid(), application ? @"app" : @"bundle"]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"Contents/Resources"] withIntermediateDirectories: YES
                   attributes: nil error: NULL];
    [fm copyItemAtPath: [NSString stringWithUTF8String: car]
                toPath: [dir stringByAppendingPathComponent: @"Contents/Resources/Assets.car"] error: NULL];
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"org.darlinghq.test.assetcatalog", @"CFBundleIdentifier", name, @"CFBundleName",
            application ? @"APPL" : @"BNDL", @"CFBundlePackageType", nil];
    if (application)
        [info setObject: name forKey: @"CFBundleExecutable"];
    [info writeToFile: [dir stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
    return dir;
}

// The image drawn into a 20 x 20 RGBA bitmap; pixel (x, y) from the top left.
static NSBitmapImageRep *render(NSImage *image) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 20 pixelsHigh: 20
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: 80 bitsPerPixel: 32] autorelease];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: NSMakeRect(0, 0, 20, 20) fromRect: NSZeroRect operation: NSCompositingOperationCopy fraction: 1];
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

static BOOL sizeIs(NSImage *image, CGFloat width, CGFloat height) {
    return image != nil && fabs([image size].width - width) < 0.01 && fabs([image size].height - height) < 0.01;
}

// Whether the image has a bitmap representation of the given pixel size.
static BOOL hasBitmap(NSImage *image, NSInteger width, NSInteger height) {
    for (NSImageRep *rep in [image representations])
        if (![rep isKindOfClass: [NSPDFImageRep class]] && [rep pixelsWide] == width && [rep pixelsHigh] == height)
            return YES;
    return NO;
}

static BOOL hasPDF(NSImage *image) {
    for (NSImageRep *rep in [image representations])
        if ([rep isKindOfClass: [NSPDFImageRep class]])
            return YES;
    return NO;
}

static void test_bundle_images(const char *car) {
    NSString *dir = makeBundle(car, @"CatalogFixture", NO);
    NSBundle *bundle = [NSBundle bundleWithPath: dir];

    NSImage *halves = [bundle imageForResource: @"Halves"];
    CHECK(sizeIs(halves, 20, 10));
    CHECK(hasBitmap(halves, 20, 10));
    CHECK(hasBitmap(halves, 40, 20));
    CHECK(![halves isTemplate]);
    NSBitmapImageRep *pixels = render(halves);
    CHECK(pixelIs(pixels, 2, 2, 255, 0, 0, 255));
    CHECK(pixelIs(pixels, 17, 2, 255, 0, 0, 255));
    CHECK(pixelIs(pixels, 2, 17, 0, 0, 255, 255));

    NSImage *translucent = [bundle imageForResource: @"Translucent"];
    CHECK(sizeIs(translucent, 12, 12));
    CHECK(hasBitmap(translucent, 12, 12));
    CHECK(pixelIs(render(translucent), 10, 10, 0, 128, 0, 128));

    NSImage *gray = [bundle imageForResource: @"Gray"];
    CHECK(sizeIs(gray, 16, 16));
    pixels = render(gray);
    CHECK(pixelIs(pixels, 2, 2, 128, 128, 128, 255));
    CHECK(pixelIs(pixels, 2, 17, 128, 128, 128, 255));
    CHECK(pixelIs(pixels, 17, 2, 0, 0, 0, 0));

    NSImage *large = [bundle imageForResource: @"Large"];
    CHECK(sizeIs(large, 300, 200));
    CHECK(hasBitmap(large, 300, 200));
    pixels = render(large);
    CHECK(pixelIs(pixels, 10, 2, 255, 0, 0, 255));
    CHECK(pixelIs(pixels, 10, 17, 0, 0, 255, 255));

    NSImage *vector = [bundle imageForResource: @"Vector"];
    CHECK(sizeIs(vector, 16, 16));
    CHECK(hasPDF(vector));
    CHECK(hasBitmap(vector, 16, 16));
    CHECK(hasBitmap(vector, 32, 32));
    CHECK(pixelIs(render(vector), 10, 10, 255, 0, 0, 255));

    NSImage *template = [bundle imageForResource: @"Template"];
    CHECK(sizeIs(template, 16, 16));
    CHECK([template isTemplate]);
    CHECK(![vector isTemplate] && ![gray isTemplate]);

    CHECK([bundle imageForResource: @"Missing"] == nil);
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
}

static void test_main_bundle(void) {
    NSImage *image = [NSImage imageNamed: @"Halves"];
    CHECK(sizeIs(image, 20, 10));
    CHECK([[image name] isEqualToString: @"Halves"]);
    CHECK(pixelIs(render(image), 2, 2, 255, 0, 0, 255));
    CHECK([NSImage imageNamed: @"Missing"] == nil);
}

// Runs a copy of this program as the executable of an application bundle with the catalog.
static void run_in_application(const char *car) {
    NSString *dir = makeBundle(car, @"CatalogApp", YES);
    NSString *macos = [dir stringByAppendingPathComponent: @"Contents/MacOS"];
    [[NSFileManager defaultManager] createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
    NSString *executable = [macos stringByAppendingPathComponent: @"CatalogApp"];
    [[NSFileManager defaultManager] copyItemAtPath: [[NSBundle mainBundle] executablePath] toPath: executable error: NULL];
    NSTask *task = [NSTask launchedTaskWithLaunchPath: executable arguments: [NSArray arrayWithObject: @"--main-bundle"]];
    [task waitUntilExit];
    if ([task terminationStatus] != 0) {
        fprintf(stderr, "FAIL: test_main_bundle\n");
        failures++;
    }
    [[NSFileManager defaultManager] removeItemAtPath: dir error: NULL];
}

#define RUN(t) do { @try { t; } @catch (id e) { fprintf(stderr, "FAIL: %s raised %s\n", #t, [[e description] UTF8String]); failures++; } } while (0)

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    if (argc > 1 && strcmp(argv[1], "--main-bundle") == 0) {
        RUN(test_main_bundle());
        [pool release];
        return failures != 0;
    }
    if (argc < 2) {
        fprintf(stderr, "usage: appkit-asset-catalog-images <Assets.car>\n");
        return 2;
    }
    RUN(test_bundle_images(argv[1]));
    if (argc < 3 || strcmp(argv[2], "--no-application") != 0)
        RUN(run_in_application(argv[1]));
    if (failures == 0)
        printf("PASS appkit-asset-catalog-images\n");
    [pool release];
    return failures != 0;
}
