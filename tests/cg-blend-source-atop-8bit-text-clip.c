// Copyright (C) 2026 Lubos Dolezel
// SPDX-License-Identifier: MIT
// kCGBlendModeSourceAtop in an 8-bit premultiplied context where the pixels
// come from glyph drawing and from a mask clip.
//
// Documented contract (CGBlendMode): result = S*Da + D*(1 - Sa) with
// premultiplied colours, so the destination alpha is unchanged (to within the
// one step that an 8-bit coverage mix may round away) and nothing is painted
// where the destination is transparent. Glyphs and clip masks are
// composited with a coverage on top of that blend.
//
// Build (macOS or Darling): clang -o t cg-blend-source-atop-8bit-text-clip.c -framework CoreGraphics
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

#define W 96
#define H 24

static CGContextRef make(unsigned char *buf, CGColorSpaceRef cs) {
    return CGBitmapContextCreate(buf, W, H, 8, W * 4, cs,
                                 kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
}

// left half clear, right half opaque mid grey
static void fillDst(unsigned char *buf) {
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned char *p = buf + (y * W + x) * 4;
            unsigned char v = x < W / 2 ? 0 : 128, a = x < W / 2 ? 0 : 255;
            p[0] = p[1] = p[2] = v;
            p[3] = a;
        }
}

static int check(const char *what, unsigned char *buf, int expectPainted) {
    int leftNonZero = 0, rightAlphaChanged = 0, rightDarkened = 0;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            unsigned char *p = buf + (y * W + x) * 4;
            if (x < W / 2) {
                if (p[0] | p[1] | p[2] | p[3]) leftNonZero++;
            } else {
                if (p[3] < 254) rightAlphaChanged++; // coverage rounding may cost one step
                if (p[0] < 126) rightDarkened++;
            }
        }
    int ok = leftNonZero == 0 && rightAlphaChanged == 0 && (expectPainted ? rightDarkened > 0 : rightDarkened == 0);
    printf("%s %s: pixels painted over clear dst %d, opaque dst with alpha changed %d, darkened %d\n",
           ok ? "ok  " : "FAIL", what, leftNonZero, rightAlphaChanged, rightDarkened);
    return ok;
}

int main(void) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    unsigned char buf[W * H * 4];
    int ok = 1;

    // glyphs in black
    fillDst(buf);
    CGContextRef ctx = make(buf, cs);
    CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextSelectFont(ctx, "Helvetica", 20, kCGEncodingMacRoman);
    CGContextSetTextDrawingMode(ctx, kCGTextFill);
    CGContextShowTextAtPoint(ctx, 2, 6, "MMMM", 4);
    CGContextRelease(ctx);
    ok &= check("glyphs", buf, 1);

    // a path fill clipped by a mask (all mask samples fully opaque for painting)
    fillDst(buf);
    unsigned char maskBytes[W * H];
    memset(maskBytes, 0, sizeof maskBytes); // in a mask image, 0 paints
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, maskBytes, sizeof maskBytes, NULL);
    CGImageRef mask = CGImageMaskCreate(W, H, 8, 8, W, prov, NULL, false);
    ctx = make(buf, cs);
    CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
    CGContextClipToMask(ctx, CGRectMake(0, 0, W, H), mask);
    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, W, H));
    CGContextRelease(ctx);
    ok &= check("mask clip", buf, 1);
    CGImageRelease(mask);
    CGDataProviderRelease(prov);

    CGColorSpaceRelease(cs);
    printf(ok ? "PASS\n" : "FAIL\n");
    return !ok;
}
