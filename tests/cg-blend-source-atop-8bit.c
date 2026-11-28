// Copyright (C) 2026 Lubos Dolezel
// SPDX-License-Identifier: MIT
// kCGBlendModeSourceAtop into an 8-bit premultiplied context.
//
// Documented contract (Quartz 2D Programming Guide / CGBlendMode): the result
// is R = S*Da + D*(1 - Sa), with premultiplied S and D; the result alpha is
// the destination alpha. The test fills 1x4 premultiplied BGRA bitmaps whose
// four pixels hold different destinations with one source colour each and
// compares to the formula with a tolerance of one 8-bit step per channel
// (implementations round differently). The alpha channel must be exact.
//
// Build (macOS or Darling): clang -o t cg-blend-source-atop-8bit.c -framework CoreGraphics
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { unsigned char a, r, g, b; } px; // premultiplied

static const px dsts[4] = {
    {255, 200, 100, 50},  // opaque
    {128, 100, 50, 25},   // half transparent, valid premultiplied
    {0, 0, 0, 0},         // clear
    {64, 64, 32, 0},      // quarter alpha
};

static const double srcs[][4] = { // r g b a, non-premultiplied
    {1.0, 0.0, 0.0, 1.0},
    {0.0, 1.0, 0.0, 0.5},
    {0.2, 0.4, 0.6, 0.25},
    {1.0, 1.0, 1.0, 0.0},
    {0.0, 0.0, 1.0, 0.75},
};

static int absdiff(int a, int b) { return a > b ? a - b : b - a; }

int main(void) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    int failures = 0;
    for (size_t s = 0; s < sizeof srcs / sizeof srcs[0]; s++) {
        unsigned char buf[4 * 4]; // BGRA bytes (little-endian ARGB32)
        for (int i = 0; i < 4; i++) {
            buf[i * 4 + 0] = dsts[i].b;
            buf[i * 4 + 1] = dsts[i].g;
            buf[i * 4 + 2] = dsts[i].r;
            buf[i * 4 + 3] = dsts[i].a;
        }
        CGContextRef ctx = CGBitmapContextCreate(buf, 4, 1, 8, 16, cs,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        if (!ctx) { printf("FAIL: no 8-bit context\n"); return 1; }
        CGContextSetBlendMode(ctx, kCGBlendModeSourceAtop);
        CGContextSetRGBFillColor(ctx, srcs[s][0], srcs[s][1], srcs[s][2], srcs[s][3]);
        CGContextFillRect(ctx, CGRectMake(0, 0, 4, 1));
        CGContextRelease(ctx);
        for (int i = 0; i < 4; i++) {
            double sa = srcs[s][3];
            double sp[3] = {srcs[s][0] * sa, srcs[s][1] * sa, srcs[s][2] * sa};
            double dp[3] = {dsts[i].r, dsts[i].g, dsts[i].b};
            double da = dsts[i].a / 255.0;
            int exp[4];
            exp[0] = (int)(255 * (sp[0] * da) + dp[0] * (1 - sa) + 0.5);
            exp[1] = (int)(255 * (sp[1] * da) + dp[1] * (1 - sa) + 0.5);
            exp[2] = (int)(255 * (sp[2] * da) + dp[2] * (1 - sa) + 0.5);
            exp[3] = dsts[i].a;
            int got[4] = {buf[i * 4 + 2], buf[i * 4 + 1], buf[i * 4 + 0], buf[i * 4 + 3]};
            int ok = absdiff(got[0], exp[0]) <= 1 && absdiff(got[1], exp[1]) <= 1 &&
                     absdiff(got[2], exp[2]) <= 1 && got[3] == exp[3];
            printf("%s src#%zu dst#%d got rgba=%3d,%3d,%3d,%3d expected %3d,%3d,%3d,%3d\n",
                   ok ? "ok  " : "FAIL", s, i, got[0], got[1], got[2], got[3],
                   exp[0], exp[1], exp[2], exp[3]);
            if (!ok) failures++;
        }
    }
    CGColorSpaceRelease(cs);
    printf(failures ? "FAIL: %d mismatches\n" : "PASS\n", failures);
    return failures ? 1 : 0;
}
