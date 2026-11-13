// Copyright (C) 2026 Lubos Dolezel
//
// Drawing an opaque image of one colour scaled up must reproduce that colour
// exactly at every interpolation quality: interpolating between identical
// pixels cannot change the value. A 1x1 red image drawn into a 2x2 context
// and a 2x2 uniform image drawn into 7x5 and 3x3 into 8x8 contexts are checked
// for every pixel.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static CGImageRef makeImage(size_t w, size_t h, const unsigned char rgba[4]) {
    unsigned char *px = malloc(w * h * 4);
    for (size_t i = 0; i < w * h; i++)
        for (int c = 0; c < 4; c++)
            px[i * 4 + c] = rgba[c];
    CFDataRef data = CFDataCreate(NULL, px, w * h * 4);
    free(px);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(w, h, 8, 32, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

static void check(size_t sw, size_t sh, size_t dw, size_t dh, const unsigned char rgba[4], CGInterpolationQuality q,
                  const char *qname) {
    CGImageRef image = makeImage(sw, sh, rgba);
    unsigned char *out = calloc(dw * dh, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(out, dw, dh, 8, dw * 4, space,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGContextSetInterpolationQuality(ctx, q);
    CGContextDrawImage(ctx, CGRectMake(0, 0, dw, dh), image);
    CGContextRelease(ctx);
    CGImageRelease(image);

    for (size_t i = 0; i < dw * dh; i++) {
        if (memcmp(out + i * 4, rgba, 4) != 0) {
            printf("FAIL: %zux%zu -> %zux%zu %s alpha %u: pixel %zu is %u,%u,%u,%u, expected %u,%u,%u,%u\n", sw, sh, dw,
                   dh, qname, rgba[3], i, out[i * 4], out[i * 4 + 1], out[i * 4 + 2], out[i * 4 + 3], rgba[0],
                   rgba[1], rgba[2], rgba[3]);
            failures++;
            break;
        }
    }
    free(out);
}

int main(void) {
    static const unsigned char red[4] = {255, 0, 0, 255};
    static const unsigned char grey[4] = {200, 200, 200, 255};
    static const struct { CGInterpolationQuality q; const char *name; } qualities[] = {
        {kCGInterpolationDefault, "default"}, {kCGInterpolationNone, "none"},
        {kCGInterpolationLow, "low"}, {kCGInterpolationHigh, "high"},
    };
    for (size_t i = 0; i < sizeof(qualities) / sizeof(qualities[0]); i++) {
        check(1, 1, 2, 2, red, qualities[i].q, qualities[i].name);
        check(2, 2, 7, 5, grey, qualities[i].q, qualities[i].name);
        check(3, 3, 8, 8, red, qualities[i].q, qualities[i].name);
    }
    if (failures) {
        printf("%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: scaled uniform images keep their exact colour");
    return 0;
}
