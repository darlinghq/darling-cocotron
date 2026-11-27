// Copyright (C) 2026 Lubos Dolezel
//
// A CGImage whose pixels have a non-premultiplied alpha channel first (kCGImageAlphaFirst, ARGB) is a valid
// image: it reports that alpha info, and drawing it composites the colour at the stated alpha. Observed
// through the public API on macOS 26.7.3: an ARGB pixel (A=128, R=255, G=0, B=0) drawn onto a transparent
// premultiplied context reads back as RGBA (128, 0, 0, 128) (premultiplied), and an opaque pixel (255, 10,
// 20, 30) stays as it is.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

int main(void)
{
    // Two pixels: opaque (A=255, R=10, G=20, B=30) and half transparent red (A=128, R=255, G=0, B=0).
    static const unsigned char argb[8] = { 255, 10, 20, 30, 128, 255, 0, 0 };
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, argb, sizeof argb, NULL);
    CGImageRef image = CGImageCreate(2, 1, 8, 32, 8, rgb, kCGImageAlphaFirst | kCGBitmapByteOrderDefault, provider,
                                     NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    expect(image != NULL, "an image with non-premultiplied alpha first can be created");
    if (image == NULL)
        return 1;
    expect(CGImageGetAlphaInfo(image) == kCGImageAlphaFirst, "the image reports kCGImageAlphaFirst");

    unsigned char out[8];
    memset(out, 0, sizeof out);
    CGContextRef context = CGBitmapContextCreate(out, 2, 1, 8, 8, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
    CGContextDrawImage(context, CGRectMake(0, 0, 2, 1), image);
    printf("pixel0 RGBA=%d,%d,%d,%d pixel1 RGBA=%d,%d,%d,%d\n", out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7]);
    expect(abs(out[0] - 10) <= 1 && abs(out[1] - 20) <= 1 && abs(out[2] - 30) <= 1 && out[3] == 255, "the opaque pixel keeps its colour");
    expect(abs(out[4] - 128) <= 2 && out[5] == 0 && out[6] == 0 && abs(out[7] - 128) <= 1, "the half transparent pixel is premultiplied at 50%");
    CGContextRelease(context);
    CGImageRelease(image);
    CGColorSpaceRelease(rgb);
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
