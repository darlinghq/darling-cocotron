// Drawing a gradient under a clip path must not keep memory per draw: the path
// the clip is filled from is released with the draw. Counts the bytes malloc has
// handed out before and after many draws and allows a generous margin for
// one-time caches (the leak is a path with all its edges, per draw).
#include <CoreGraphics/CoreGraphics.h>
#include <malloc/malloc.h>
#include <stdio.h>
#include <stdlib.h>

#define W 64
#define H 64
#define DRAWS 4000

static size_t bytesInUse(void)
{
    malloc_statistics_t stats;
    malloc_zone_statistics(NULL, &stats);
    return stats.size_in_use;
}

static void drawOnce(CGContextRef context, CGGradientRef gradient)
{
    CGContextSaveGState(context);
    CGContextAddEllipseInRect(context, CGRectMake(4, 4, W - 8, H - 8));
    CGContextClip(context);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(W, 0), 0);
    CGContextRestoreGState(context);
}

int main(void)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    unsigned char *pixels = calloc(W * H, 4);
    CGContextRef context = CGBitmapContextCreate(pixels, W, H, 8, W * 4, rgb,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGFloat colors[8] = {1, 0, 0, 1, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(rgb, colors, NULL, 2);

    // warm-up: lazily created tables and caches
    for (int i = 0; i < 50; i++)
        drawOnce(context, gradient);

    size_t before = bytesInUse();
    for (int i = 0; i < DRAWS; i++)
        drawOnce(context, gradient);
    size_t after = bytesInUse();

    // the leaked path of an ellipse is several KB (vertices and flags): 4000 draws would add megabytes
    long grown = (long) after - (long) before;
    if (grown > 1024 * 1024) {
        printf("FAIL: %ld bytes more in use after %d clipped gradient draws\n", grown, DRAWS);
        return 1;
    }
    puts("PASS: onyx2d-shading-clip-path-leak");
    return 0;
}
