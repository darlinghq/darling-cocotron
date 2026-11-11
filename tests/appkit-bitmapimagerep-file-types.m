// Copyright (C) 2026 Lubos Dolezel
//
// Encodes an NSBitmapImageRep with -representationUsingType:properties: and
// -TIFFRepresentation in each file type, checks the container signature,
// decodes the data back with +imageRepWithData: and compares the size and (for
// lossless formats) the pixels. For JPEG it also reads the pixel density that
// the encoder stored, which -representationUsingType:properties: derives from
// the image's size in points and its pixel size.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

enum { W = 7, H = 5 };
static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

static void pixelAt(int x, int y, unsigned char *p) {
    p[0] = (unsigned char) (x * 40 + 10);
    p[1] = (unsigned char) (y * 50 + 5);
    p[2] = (unsigned char) ((x * 17 + y * 31) % 256);
    p[3] = 255;
}

static NSBitmapImageRep *makeRep(NSSize size) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL
                          pixelsWide: W
                          pixelsHigh: H
                       bitsPerSample: 8
                     samplesPerPixel: 4
                            hasAlpha: YES
                            isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace
                         bytesPerRow: W * 4
                        bitsPerPixel: 32] autorelease];
    unsigned char *data = [rep bitmapData];
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
            pixelAt(x, y, data + y * W * 4 + x * 4);
    [rep setSize: size];
    return rep;
}

// Compares the red, green and blue samples of a decoded rep with the pattern.
// Returns the largest per-sample difference, or -1 if the layout is unusable.
static int maxDifference(NSBitmapImageRep *rep) {
    if ([rep isPlanar] || [rep bitsPerSample] != 8 || [rep samplesPerPixel] < 3)
        return -1;
    NSInteger bytesPerPixel = [rep bitsPerPixel] / 8;
    NSInteger bytesPerRow = [rep bytesPerRow];
    const unsigned char *data = [rep bitmapData];
    int worst = 0;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned char want[4];
            pixelAt(x, y, want);
            const unsigned char *got = data + y * bytesPerRow + x * bytesPerPixel;
            for (int c = 0; c < 3; c++) {
                int d = (int) got[c] - (int) want[c];
                if (d < 0)
                    d = -d;
                if (d > worst)
                    worst = d;
            }
        }
    return worst;
}

static BOOL hasPrefix(NSData *data, const void *bytes, NSUInteger length) {
    return [data length] >= length && memcmp([data bytes], bytes, length) == 0;
}

static void checkDecoded(const char *name, NSData *data, int tolerance) {
    NSBitmapImageRep *back = [NSBitmapImageRep imageRepWithData: data];
    CHECK(back != nil, "%s: +imageRepWithData: returned nil", name);
    if (back == nil)
        return;
    CHECK([back pixelsWide] == W && [back pixelsHigh] == H,
          "%s: decoded size %ldx%ld, expected %dx%d", name,
          (long) [back pixelsWide], (long) [back pixelsHigh], W, H);
    if (tolerance >= 0) {
        int diff = maxDifference(back);
        CHECK(diff >= 0 && diff <= tolerance,
              "%s: pixel difference %d, allowed %d", name, diff, tolerance);
    }
}

// Reads the JFIF APP0 pixel density. Returns NO if there is no JFIF segment.
static BOOL jfifDensity(NSData *data, int *units, int *xd, int *yd) {
    const unsigned char *b = [data bytes];
    NSUInteger n = [data length], i = 2;
    while (i + 4 <= n && b[i] == 0xFF) {
        unsigned marker = b[i + 1];
        NSUInteger len = (b[i + 2] << 8) | b[i + 3];
        if (marker == 0xE0 && len >= 16 && i + 4 + 14 <= n &&
            memcmp(b + i + 4, "JFIF\0", 5) == 0) {
            *units = b[i + 11];
            *xd = (b[i + 12] << 8) | b[i + 13];
            *yd = (b[i + 14] << 8) | b[i + 15];
            return YES;
        }
        if (marker == 0xDA)
            break;
        i += 2 + len;
    }
    return NO;
}

static void checkJPEGDensity(const char *name, NSData *data, int expected) {
    int units = -1, xd = -1, yd = -1;
    BOOL jfif = jfifDensity(data, &units, &xd, &yd);
    printf("%s: JFIF=%d units=%d x=%d y=%d\n", name, jfif, units, xd, yd);
    CHECK(jfif, "%s: no JFIF APP0 segment", name);
    // The density fields hold the dots per inch. The units byte is not
    // compared: macOS writes 0 (aspect ratio only) while JFIF defines 1 as dots
    // per inch, and both are accepted.
    CHECK(jfif && (units == 0 || units == 1) && xd == expected && yd == expected,
          "%s: density units=%d x=%d y=%d, expected dpi %d", name, units, xd, yd,
          expected);
}

int main(void) {
    @autoreleasepool {
        NSDictionary *none = [NSDictionary dictionary];
        NSBitmapImageRep *rep = makeRep(NSMakeSize(W, H));

        // Lossless formats: signature, size and exact pixels.
        static const unsigned char pngMagic[8] = {0x89, 'P', 'N', 'G', 13, 10, 26, 10};
        for (int variant = 0; variant < 2; variant++) {
            NSData *png = [rep representationUsingType: NSPNGFileType
                                            properties: variant ? none : nil];
            CHECK(png != nil && hasPrefix(png, pngMagic, 8), "PNG signature (variant %d)", variant);
            if (png)
                checkDecoded("PNG", png, 0);

            NSData *tiff = [rep representationUsingType: NSTIFFFileType
                                             properties: variant ? none : nil];
            CHECK(tiff != nil && ([tiff length] > 4) &&
                  (hasPrefix(tiff, "II*\0", 4) || hasPrefix(tiff, "MM\0*", 4)),
                  "TIFF signature (variant %d)", variant);
            if (tiff)
                checkDecoded("TIFF", tiff, 0);

            NSData *bmp = [rep representationUsingType: NSBMPFileType
                                            properties: variant ? none : nil];
            CHECK(bmp != nil && hasPrefix(bmp, "BM", 2), "BMP signature (variant %d)", variant);
            if (bmp)
                checkDecoded("BMP", bmp, 0);
        }

        NSData *tiffRep = [rep TIFFRepresentation];
        CHECK(tiffRep != nil && [tiffRep length] > 4 &&
              (hasPrefix(tiffRep, "II*\0", 4) || hasPrefix(tiffRep, "MM\0*", 4)),
              "TIFFRepresentation signature");
        if (tiffRep)
            checkDecoded("TIFFRepresentation", tiffRep, 0);

        // GIF is palettized, so only the signature and size are compared.
        NSData *gif = [rep representationUsingType: NSGIFFileType properties: nil];
        CHECK(gif != nil && (hasPrefix(gif, "GIF87a", 6) || hasPrefix(gif, "GIF89a", 6)),
              "GIF signature");
        if (gif)
            checkDecoded("GIF", gif, -1);

        // JPEG is lossy: signature, size, approximate pixels and the density.
        // The size equals the pixel size, so the density is 72 dpi.
        NSData *jpeg = [rep representationUsingType: NSJPEGFileType properties: nil];
        CHECK(jpeg != nil && hasPrefix(jpeg, "\xFF\xD8\xFF", 3), "JPEG signature");
        if (jpeg) {
            checkDecoded("JPEG", jpeg, 40);
            checkJPEGDensity("JPEG default", jpeg, 72);
        }

        NSDictionary *quality = [NSDictionary
                dictionaryWithObject: [NSNumber numberWithFloat: 1.0f]
                              forKey: NSImageCompressionFactor];
        NSData *jpegHigh = [rep representationUsingType: NSJPEGFileType properties: quality];
        quality = [NSDictionary dictionaryWithObject: [NSNumber numberWithFloat: 0.1f]
                                              forKey: NSImageCompressionFactor];
        NSData *jpegLow = [rep representationUsingType: NSJPEGFileType properties: quality];
        CHECK(jpegHigh != nil && jpegLow != nil && hasPrefix(jpegHigh, "\xFF\xD8\xFF", 3) &&
              hasPrefix(jpegLow, "\xFF\xD8\xFF", 3), "JPEG with compression factor");
        if (jpegHigh && jpegLow) {
            checkDecoded("JPEG q1.0", jpegHigh, 8);
            checkDecoded("JPEG q0.1", jpegLow, 120);
            CHECK([jpegHigh length] > [jpegLow length],
                  "JPEG quality 1.0 (%lu bytes) not larger than 0.1 (%lu bytes)",
                  (unsigned long) [jpegHigh length], (unsigned long) [jpegLow length]);
            checkJPEGDensity("JPEG q1.0", jpegHigh, 72);
        }

        // A size of half the pixel size means 144 dpi (rounded up).
        NSBitmapImageRep *retina = makeRep(NSMakeSize(W / 2.0, H / 2.0));
        NSData *jpeg144 = [retina representationUsingType: NSJPEGFileType properties: nil];
        CHECK(jpeg144 != nil, "JPEG at half size");
        if (jpeg144)
            checkJPEGDensity("JPEG half size", jpeg144, 144);

        // An unsupported file type produces no data.
        CHECK([rep representationUsingType: (NSBitmapImageFileType) 99 properties: nil] == nil,
              "unknown file type returned data");
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS");
    return 0;
}
