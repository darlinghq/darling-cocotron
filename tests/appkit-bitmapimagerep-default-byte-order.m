// Copyright (C) 2026 Lubos Dolezel
//
// 8-bit pixels with the default byte order are in component order: R, G, B, A
// with the alpha last and A, R, G, B with the alpha first (bitmap contexts
// and images created with those flags, and the image of an
// NSBitmapImageRep). The image of such a rep reports its alpha info only, no
// byte-order bits. Bytes of little-endian pixels are checked for contrast.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

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

static CGContextRef makeContext(unsigned char *buf, CGBitmapInfo info) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, 1, 1, 8, 4, space, info);
    CGColorSpaceRelease(space);
    return ctx;
}

// Fills a 1x1 context of the given format with opaque (10, 20, 30) and checks the bytes.
static void checkContextBytes(CGBitmapInfo info, const unsigned char *expected, const char *name) {
    unsigned char buf[4] = {0, 0, 0, 0};
    CGContextRef ctx = makeContext(buf, info);
    CHECK(ctx != NULL, "%s: context", name);
    if (ctx == NULL)
        return;
    CGContextSetRGBFillColor(ctx, 10 / 255.0, 20 / 255.0, 30 / 255.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    CGContextRelease(ctx);
    CHECK(memcmp(buf, expected, 4) == 0, "%s: bytes %u,%u,%u,%u, expected %u,%u,%u,%u", name, buf[0], buf[1], buf[2],
          buf[3], expected[0], expected[1], expected[2], expected[3]);
}

// Draws a 1x1 image holding the bytes into an RGBA context and checks the colour.
static void checkImageBytes(CGBitmapInfo info, const unsigned char *bytes, const char *name) {
    CFDataRef data = CFDataCreate(NULL, bytes, 4);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(1, 1, 8, 32, 4, space, info, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    CHECK(image != NULL, "%s: image", name);
    if (image == NULL)
        return;
    unsigned char out[4] = {0, 0, 0, 0};
    CGContextRef ctx = makeContext(out, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), image);
    CGContextRelease(ctx);
    CGImageRelease(image);
    CHECK(out[0] == 10 && out[1] == 20 && out[2] == 30 && out[3] == 255, "%s: drew %u,%u,%u,%u, expected 10,20,30,255",
          name, out[0], out[1], out[2], out[3]);
}

static NSBitmapImageRep *makeRep(BOOL alphaFirst) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                     pixelsWide: 1
                                                                     pixelsHigh: 1
                                                                  bitsPerSample: 8
                                                                samplesPerPixel: 4
                                                                       hasAlpha: YES
                                                                       isPlanar: NO
                                                                 colorSpaceName: NSDeviceRGBColorSpace
                                                                   bitmapFormat: alphaFirst ? NSAlphaFirstBitmapFormat : 0
                                                                    bytesPerRow: 4
                                                                   bitsPerPixel: 32] autorelease];
    unsigned char *p = [rep bitmapData];
    if (alphaFirst) {
        p[0] = 255; p[1] = 10; p[2] = 20; p[3] = 30;
    } else {
        p[0] = 10; p[1] = 20; p[2] = 30; p[3] = 255;
    }
    return rep;
}

int main(void) {
    @autoreleasepool {
        static const unsigned char rgba[4] = {10, 20, 30, 255};
        static const unsigned char argb[4] = {255, 10, 20, 30};
        static const unsigned char bgra[4] = {30, 20, 10, 255};

        // Contexts and images with no byte-order bits.
        checkContextBytes(kCGImageAlphaPremultipliedLast, rgba, "context premultiplied last");
        checkContextBytes(kCGImageAlphaPremultipliedFirst, argb, "context premultiplied first");
        checkContextBytes(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, bgra,
                          "context premultiplied first, 32 little");
        checkImageBytes(kCGImageAlphaPremultipliedLast, rgba, "image premultiplied last");
        checkImageBytes(kCGImageAlphaPremultipliedFirst, argb, "image premultiplied first");
        checkImageBytes(kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, bgra,
                        "image premultiplied first, 32 little");

        // The image of a bitmap rep.
        for (int alphaFirst = 0; alphaFirst <= 1; alphaFirst++) {
            const char *layout = alphaFirst ? "alpha first" : "alpha last";
            NSBitmapImageRep *rep = makeRep(alphaFirst);
            CGImageRef image = [rep CGImage];
            CHECK(image != NULL, "%s: CGImage", layout);
            if (image == NULL)
                continue;
            CGBitmapInfo info = CGImageGetBitmapInfo(image);
            CHECK((info & kCGBitmapByteOrderMask) == kCGBitmapByteOrderDefault, "%s: byte order bits 0x%x", layout,
                  (unsigned) (info & kCGBitmapByteOrderMask));
            CHECK((info & kCGBitmapAlphaInfoMask) ==
                          (alphaFirst ? kCGImageAlphaPremultipliedFirst : kCGImageAlphaPremultipliedLast),
                  "%s: alpha info 0x%x", layout, (unsigned) (info & kCGBitmapAlphaInfoMask));

            unsigned char out[4] = {0, 0, 0, 0};
            CGContextRef ctx = makeContext(out, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), image);
            CGContextRelease(ctx);
            CHECK(out[0] == 10 && out[1] == 20 && out[2] == 30 && out[3] == 255, "%s: drew %u,%u,%u,%u", layout,
                  out[0], out[1], out[2], out[3]);

            // A rep made from that image keeps the planes in component order.
            NSBitmapImageRep *copy = [[[NSBitmapImageRep alloc] initWithCGImage: image] autorelease];
            const unsigned char *planes = [copy bitmapData];
            const unsigned char *want = alphaFirst ? argb : rgba;
            CHECK(planes != NULL && memcmp(planes, want, 4) == 0, "%s: copy bytes %u,%u,%u,%u", layout,
                  planes ? planes[0] : 0, planes ? planes[1] : 0, planes ? planes[2] : 0, planes ? planes[3] : 0);
        }
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: the default byte order is component order and bitmap reps report no byte order");
    return 0;
}
