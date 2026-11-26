// Copyright (C) 2026 Lubos Dolezel
//
// CGContextClipToRects clips to the union of the rectangles, wherever they are (identity and flipped
// transforms, rectangles of different sizes, repeated rectangles).
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
enum { W = 420, H = 300 };
static int check(const CGRect *rs, int n, int flip, int scale2) {
    unsigned char *px = calloc(W * H, 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(px, W, H, 8, W * 4, cs, kCGImageAlphaPremultipliedLast);
    if (flip) { CGContextTranslateCTM(c, 0, H); CGContextScaleCTM(c, 1, -1); }
    CGContextClipToRects(c, rs, n);
    CGContextSetRGBFillColor(c, 1, 1, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, W, H));
    int bad = 0;
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
        double uy = flip ? y : H - 1 - y;
        int in = 0;
        for (int i = 0; i < n; i++)
            if (x >= rs[i].origin.x && x < rs[i].origin.x + rs[i].size.width && uy + 0.5 >= rs[i].origin.y && uy + 0.5 < rs[i].origin.y + rs[i].size.height) in = 1;
        int got = px[(y * W + x) * 4 + 3] != 0;
        bad += in != got;
    }
    free(px);
    return bad;
}
int main(void) {
    CGRect r[] = {{{176,170},{230,24}}, {{14,177},{7,7}}, {{14,149},{7,7}}, {{176,170},{230,24}}};
    int fails = 0;
    for (int flip = 0; flip < 2; flip++)
        for (int n = 1; n <= 4; n++) {
            int bad = check(r, n, flip, 0);
            printf("flip %d first %d rects: %d wrong pixels\n", flip, n, bad);
            fails += bad != 0;
        }
    printf(fails ? "FAILED\n" : "PASSED\n");
    return fails != 0;
}
