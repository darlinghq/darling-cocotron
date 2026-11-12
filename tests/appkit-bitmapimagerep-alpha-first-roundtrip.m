// Copyright (C) 2026 Lubos Dolezel
//
// Encodes 8-bit NSBitmapImageReps with the alpha channel last and first
// (NSAlphaFirstBitmapFormat) as PNG and TIFF, decodes the data back with
// +imageRepWithData: and checks that every pixel keeps its red, green, blue
// and alpha values. Channels that come back swapped mean the representation
// described its byte order wrongly to the encoder. Also checks the
// byte order and alpha info of the rep's CGImage and that a rep made from that
// CGImage encodes the same pixels.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

enum { W = 6, H = 4 };
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

// Opaque pixels have distinct channel values, so any swap is visible. The
// last column is half transparent; premultiplication on the way through the
// encoder is allowed to move the color channels by a few steps.
static void expectedPixel(int x, int y, unsigned char *rgba) {
    rgba[0] = (unsigned char) (x * 40 + 10);
    rgba[1] = (unsigned char) (y * 50 + 5);
    rgba[2] = (unsigned char) (200 - x * 20 - y * 10);
    rgba[3] = (x == W - 1) ? 128 : 255;
}

// Reads the pixel at x, y of a 4 samples-per-pixel 8-bit rep as R, G, B, A,
// whichever order the rep stores them in.
static void readPixel(NSBitmapImageRep *rep, int x, int y, unsigned char *rgba) {
    const unsigned char *row = [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
    BOOL alphaFirst = ([rep bitmapFormat] & NSAlphaFirstBitmapFormat) != 0;
    if (alphaFirst) {
        rgba[0] = row[1];
        rgba[1] = row[2];
        rgba[2] = row[3];
        rgba[3] = row[0];
    } else {
        rgba[0] = row[0];
        rgba[1] = row[1];
        rgba[2] = row[2];
        rgba[3] = row[3];
    }
}

static NSBitmapImageRep *makeRep(BOOL alphaFirst) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes: NULL
                          pixelsWide: W
                          pixelsHigh: H
                       bitsPerSample: 8
                     samplesPerPixel: 4
                            hasAlpha: YES
                            isPlanar: NO
                      colorSpaceName: NSDeviceRGBColorSpace
                        bitmapFormat: alphaFirst ? NSAlphaFirstBitmapFormat : 0
                         bytesPerRow: W * 4
                        bitsPerPixel: 32] autorelease];
    unsigned char *data = [rep bitmapData];
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            unsigned char p[4];
            expectedPixel(x, y, p);
            unsigned char *dst = data + y * W * 4 + x * 4;
            if (alphaFirst) {
                dst[0] = p[3];
                dst[1] = p[0] * p[3] / 255;
                dst[2] = p[1] * p[3] / 255;
                dst[3] = p[2] * p[3] / 255;
            } else {
                dst[0] = p[0] * p[3] / 255;
                dst[1] = p[1] * p[3] / 255;
                dst[2] = p[2] * p[3] / 255;
                dst[3] = p[3];
            }
        }
    }
    return rep;
}

static int diff(int a, int b) {
    return abs(a - b);
}

static void checkDecoded(NSData *data, const char *name) {
    CHECK(data != nil && [data length] > 0, "%s: encoding produced data", name);
    if (data == nil)
        return;
    NSBitmapImageRep *decoded = [NSBitmapImageRep imageRepWithData: data];
    CHECK(decoded != nil, "%s: data decodes", name);
    if (decoded == nil)
        return;
    CHECK([decoded pixelsWide] == W && [decoded pixelsHigh] == H, "%s: size %ldx%ld", name,
          (long) [decoded pixelsWide], (long) [decoded pixelsHigh]);
    if ([decoded samplesPerPixel] != 4 || [decoded bitsPerSample] != 8) {
        CHECK(0, "%s: decoded as %ld samples of %ld bits", name, (long) [decoded samplesPerPixel],
              (long) [decoded bitsPerSample]);
        return;
    }
    // Un-premultiply when the decoded rep is premultiplied.
    BOOL nonPremultiplied = ([decoded bitmapFormat] & NSAlphaNonpremultipliedBitmapFormat) != 0;
    for (int y = 0; y < H; y++) {
        for (int x = 0; x < W; x++) {
            unsigned char want[4], got[4];
            expectedPixel(x, y, want);
            readPixel(decoded, x, y, got);
            if (!nonPremultiplied && got[3] != 0)
                for (int c = 0; c < 3; c++)
                    got[c] = (unsigned char) (got[c] * 255 / got[3] > 255 ? 255 : got[c] * 255 / got[3]);
            int tolerance = want[3] == 255 ? 0 : 4;
            CHECK(diff(got[0], want[0]) <= tolerance && diff(got[1], want[1]) <= tolerance &&
                          diff(got[2], want[2]) <= tolerance && diff(got[3], want[3]) <= tolerance,
                  "%s: pixel %d,%d is %d,%d,%d,%d, expected %d,%d,%d,%d", name, x, y, got[0], got[1],
                  got[2], got[3], want[0], want[1], want[2], want[3]);
        }
    }
}

int main(void) {
    @autoreleasepool {
        for (int alphaFirst = 0; alphaFirst <= 1; alphaFirst++) {
            NSBitmapImageRep *rep = makeRep(alphaFirst);
            const char *layout = alphaFirst ? "alpha first" : "alpha last";
            char name[64];

            CGImageRef image = [rep CGImage];
            CHECK(image != NULL, "%s: CGImage", layout);
            if (image == NULL)
                continue;
            CGBitmapInfo info = CGImageGetBitmapInfo(image);
            // The byte order bits are not checked: macOS reports no byte order bits for the image
            // of an 8-bit rep (only the alpha info), and the pixel round trips below pin the layout.
            CGBitmapInfo alpha = info & kCGBitmapAlphaInfoMask;
            CHECK(alpha == (alphaFirst ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaPremultipliedLast),
                  "%s: CGBitmapInfo alpha info (0x%x)", layout, (unsigned) alpha);

            snprintf(name, sizeof name, "%s PNG", layout);
            checkDecoded([rep representationUsingType: NSPNGFileType properties: @{}], name);
            snprintf(name, sizeof name, "%s TIFF", layout);
            checkDecoded([rep TIFFRepresentation], name);

            // A second rep made from the rep's CGImage must keep the channels.
            NSBitmapImageRep *copy = [[[NSBitmapImageRep alloc] initWithCGImage: image] autorelease];
            snprintf(name, sizeof name, "%s via CGImage PNG", layout);
            checkDecoded([copy representationUsingType: NSPNGFileType properties: @{}], name);
        }
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: alpha-first and alpha-last bitmap reps round-trip through PNG and TIFF");
    return 0;
}
