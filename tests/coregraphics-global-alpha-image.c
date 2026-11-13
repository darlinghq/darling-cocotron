// Copyright (C) 2026 Lubos Dolezel
//
// CoreGraphics: CGContextSetAlpha scales the alpha of an image drawn into a
// bitmap context (the documented global alpha value). An opaque red image
// drawn at alpha 0.5 over a transparent bitmap leaves a pixel whose alpha is
// about half and whose premultiplied red equals its alpha.

#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(int ok, const char *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static void pixelAfterDrawing(float alpha, unsigned char out[4]) {
    unsigned char source[4 * 4 * 4];
    for (int i = 0; i < 16; i++) {
        source[i * 4 + 0] = 255; // R
        source[i * 4 + 1] = 0;
        source[i * 4 + 2] = 0;
        source[i * 4 + 3] = 255;
    }
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef sourceContext = CGBitmapContextCreate(source, 4, 4, 8, 16, rgb, kCGImageAlphaPremultipliedLast);
    CGImageRef image = CGBitmapContextCreateImage(sourceContext);

    unsigned char dest[4 * 4 * 4];
    memset(dest, 0, sizeof dest);
    CGContextRef context = CGBitmapContextCreate(dest, 4, 4, 8, 16, rgb, kCGImageAlphaPremultipliedLast);
    CGContextSetAlpha(context, alpha);
    CGContextDrawImage(context, CGRectMake(0, 0, 4, 4), image);
    memcpy(out, dest + (2 * 16 + 2 * 4), 4);

    CGContextRelease(context);
    CGContextRelease(sourceContext);
    CGImageRelease(image);
    CGColorSpaceRelease(rgb);
}

int main(void) {
    unsigned char opaque[4], half[4], clear[4];

    pixelAfterDrawing(1.0f, opaque);
    expect(opaque[0] == 255 && opaque[3] == 255, "alpha 1 draws the image unchanged");

    pixelAfterDrawing(0.5f, half);
    expect(abs(half[3] - 128) <= 2, "alpha 0.5 halves the pixel alpha");
    expect(abs(half[0] - half[3]) <= 2, "the red channel stays premultiplied");
    expect(half[1] == 0 && half[2] == 0, "other channels stay zero");

    pixelAfterDrawing(0.0f, clear);
    expect(clear[3] == 0, "alpha 0 draws nothing");

    printf("%s\n", failures ? "FAILED" : "PASSED");
    return failures != 0;
}
