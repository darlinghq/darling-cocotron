// Copyright (C) 2026 Lubos Dolezel
//
// A transparency layer composites its content as a group and then draws the group at the context's alpha,
// whatever the pixel format of the bitmap it is in: a surface that has no alpha channel of its own
// (kCGImageAlphaNoneSkipFirst) gives the same result as one with premultiplied alpha. Observed through the
// public API on macOS 26.7.3: blue drawn in a layer at alpha 0.5 over opaque red gives (R=127, G=0, B=128,
// A=255) on both formats. (Blending mode kCGBlendModeCopy with a clear colour clears the pixel to zero on
// both formats on that system, and is not changed by this test's subject.)
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

static void layerOver(CGImageAlphaInfo info, const char *name)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    unsigned char buf[8 * 8 * 4];
    memset(buf, 0, sizeof buf);
    CGContextRef c = CGBitmapContextCreate(buf, 8, 8, 8, 32, rgb, info | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(rgb);
    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 8, 8));
    CGContextSetAlpha(c, 0.5);
    CGContextBeginTransparencyLayer(c, NULL);
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 4, 8));
    CGContextEndTransparencyLayer(c);
    // BGRA byte order: bytes are B, G, R, A.
    unsigned char *left = buf + 1 * 4, *right = buf + 6 * 4;
    char msg[96];
    snprintf(msg, sizeof msg, "%s: blue at 50%% in a layer over red", name);
    expect(abs(left[0] - 128) <= 2 && left[1] == 0 && abs(left[2] - 127) <= 2 && left[3] == 255, msg);
    snprintf(msg, sizeof msg, "%s: outside the layer content stays red", name);
    expect(right[0] == 0 && right[1] == 0 && right[2] == 255 && right[3] == 255, msg);
    CGContextRelease(c);
}

int main(void)
{
    layerOver(kCGImageAlphaPremultipliedFirst, "premultiplied alpha first");
    layerOver(kCGImageAlphaNoneSkipFirst, "no alpha channel (skip first)");
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
