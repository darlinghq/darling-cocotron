// Copyright (C) 2026 Lubos Dolezel
//
// CGContextClip and CGContextEOClip clip to the shape of the path (not to its bounding box): the corners of
// a rounded or circular clip stay untouched, edge pixels get partial coverage, nested clips intersect, and the
// even-odd rule leaves holes. A gradient drawn through a clip is cut by it too. The expected values follow
// the documented contract and were confirmed by running the same calls on Mac OS X 10.14.4.
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

#define N 100

// A 100 x 100 RGBA context (premultiplied), transparent; y of the pixel array is the top row first.
static CGContextRef makeContext(unsigned char **data) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    *data = calloc(N * N, 4);
    CGContextRef ctx = CGBitmapContextCreate(*data, N, N, 8, N * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return ctx;
}

// alpha of the pixel at user space (x, y), y up
static int alphaAt(unsigned char *data, int x, int y) {
    return data[((N - 1 - y) * N + x) * 4 + 3];
}

static void fillRed(CGContextRef ctx) {
    CGContextSetRGBFillColor(ctx, 1, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, N, N));
}

int main(void)
{
    unsigned char *d;
    CGContextRef ctx;

    // a circle of radius 40 centred at (50, 50): inside, outside, the corner of its bounding box, the edge
    ctx = makeContext(&d);
    CGContextAddEllipseInRect(ctx, CGRectMake(10, 10, 80, 80));
    CGContextClip(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 50, 50) == 255);
    CHECK(alphaAt(d, 20, 50) == 255);
    CHECK(alphaAt(d, 11, 11) == 0);      // inside the bounding box, outside the circle
    CHECK(alphaAt(d, 89, 89) == 0);
    CHECK(alphaAt(d, 5, 50) == 0);       // outside the bounding box
    CHECK(alphaAt(d, 50, 91) == 0);
    CHECK(alphaAt(d, 50, 89) > 0);       // the top edge pixel, covered by the circle's rim
    CHECK(alphaAt(d, 22, 72) == 255);    // inside, near a diagonal part of the rim (distance 36 < 40)
    CHECK(alphaAt(d, 15, 78) == 0);      // outside it (distance 49 > 40)
    CGContextRelease(ctx);
    free(d);

    // rounded rectangle: the corner is cut, the straight edges are not
    ctx = makeContext(&d);
    CGPathRef rounded = CGPathCreateWithRoundedRect(CGRectMake(10, 10, 80, 60), 15, 15, NULL);
    CGContextAddPath(ctx, rounded);
    CGPathRelease(rounded);
    CGContextClip(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 11, 11) == 0);
    CHECK(alphaAt(d, 88, 68) == 0);
    CHECK(alphaAt(d, 40, 11) == 255);
    CHECK(alphaAt(d, 11, 40) == 255);
    CHECK(alphaAt(d, 40, 40) == 255);
    CGContextRelease(ctx);
    free(d);

    // nested clips intersect: two overlapping circles leave their lens only
    ctx = makeContext(&d);
    CGContextAddEllipseInRect(ctx, CGRectMake(5, 20, 60, 60));    // centre (35, 50)
    CGContextClip(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(35, 20, 60, 60));   // centre (65, 50)
    CGContextClip(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 50, 50) == 255);
    CHECK(alphaAt(d, 15, 50) == 0);   // only in the first circle
    CHECK(alphaAt(d, 85, 50) == 0);   // only in the second
    CGContextRelease(ctx);
    free(d);

    // even-odd rule: a ring (outer and inner circle in one path) has a hole; the nonzero rule with the same
    // directions has none
    ctx = makeContext(&d);
    CGContextAddEllipseInRect(ctx, CGRectMake(10, 10, 80, 80));
    CGContextAddEllipseInRect(ctx, CGRectMake(30, 30, 40, 40));
    CGContextEOClip(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 50, 50) == 0);
    CHECK(alphaAt(d, 15, 50) == 255);
    CHECK(alphaAt(d, 11, 11) == 0);
    CGContextRelease(ctx);
    free(d);
    ctx = makeContext(&d);
    CGContextAddEllipseInRect(ctx, CGRectMake(10, 10, 80, 80));
    CGContextAddEllipseInRect(ctx, CGRectMake(30, 30, 40, 40));
    CGContextClip(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 50, 50) == 255);
    CGContextRelease(ctx);
    free(d);

    // a gradient drawn through a rounded clip is cut by it
    ctx = makeContext(&d);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = {1, 0, 0, 1, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    CGContextAddEllipseInRect(ctx, CGRectMake(10, 10, 80, 80));
    CGContextClip(ctx);
    CGContextDrawLinearGradient(ctx, gradient, CGPointMake(0, 100), CGPointMake(0, 0), 0);
    CHECK(alphaAt(d, 50, 50) == 255);
    CHECK(alphaAt(d, 11, 11) == 0);
    CHECK(alphaAt(d, 89, 89) == 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRelease(ctx);
    free(d);

    // after a save and restore the clip is the earlier one again
    ctx = makeContext(&d);
    CGContextAddEllipseInRect(ctx, CGRectMake(10, 10, 80, 80));
    CGContextClip(ctx);
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, CGRectMake(40, 40, 20, 20));
    CGContextClip(ctx);
    CGContextRestoreGState(ctx);
    fillRed(ctx);
    CHECK(alphaAt(d, 20, 50) == 255);
    CHECK(alphaAt(d, 11, 11) == 0);
    CGContextRelease(ctx);
    free(d);

    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
