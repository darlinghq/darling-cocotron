// Copyright (C) 2026 Lubos Dolezel
//
// Setting a NULL fill or stroke color on a bitmap context.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 20; } } while (0)

// QUIRK test: a NULL color selects opaque black (observed on macOS 26.7); see O2ContextCreateColorForNull.
static int test_quirk_null_color_is_black(void) {
    unsigned char pixels[4 * 4 * 4];
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, 4, 4, 8, 16, rgb, kCGImageAlphaPremultipliedLast);
    CHECK(context != NULL);

    memset(pixels, 0, sizeof pixels);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextSetFillColorWithColor(context, NULL);
    CGContextFillRect(context, CGRectMake(0, 0, 4, 4));
    CHECK(pixels[0] == 0 && pixels[1] == 0 && pixels[2] == 0 && pixels[3] == 0xff);

    memset(pixels, 0, sizeof pixels);
    CGContextSetRGBStrokeColor(context, 0, 1, 0, 1);
    CGContextSetStrokeColorWithColor(context, NULL);
    CGContextSetLineWidth(context, 4);
    CGContextMoveToPoint(context, 0, 2);
    CGContextAddLineToPoint(context, 4, 2);
    CGContextStrokePath(context);
    CHECK(pixels[8] == 0 && pixels[9] == 0 && pixels[10] == 0 && pixels[11] == 0xff);

    // The context keeps working with a real color afterwards.
    memset(pixels, 0, sizeof pixels);
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 4, 4));
    CHECK(pixels[0] == 0 && pixels[1] == 0 && pixels[2] == 0xff && pixels[3] == 0xff);
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);
    return 0;
}

int main(void) {
    int status = test_quirk_null_color_is_black();
    if (status == 0)
        puts("PASS");
    return status;
}
