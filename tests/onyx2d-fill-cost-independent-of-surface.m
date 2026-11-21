/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: filling and stroking a small path costs about the same whatever the size of the bitmap
// context it is drawn into (macOS 10.14.4 and 26.7.3: 14 to 17 microseconds for a 12 point rounded
// rectangle in contexts from 20x20 to 1920x1080 pixels). The built-in context scanned the whole
// viewport, and every edge that covers part of a row added its winding to all the pixels up to the
// viewport's right edge, so the time grew with the surface.
// Prints BENCH lines (informational), then PASS or FAIL: the cost in a 1920x1080 context must be
// less than three times the cost in a 20x20 one (it was about ten times).
#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <sys/time.h>

static double now(void) { struct timeval tv; gettimeofday(&tv, NULL); return tv.tv_sec * 1000.0 + tv.tv_usec / 1000.0; }

static double microsPerShape(int w, int h, uint8_t *probe) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 0.2, 0.4, 0.9, 1);
    CGContextSetRGBStrokeColor(ctx, 0.1, 0.1, 0.1, 1);
    CGPathRef path = CGPathCreateWithRoundedRect(CGRectMake(3.5, 3.5, 12, 12), 3, 3, NULL);
    int n = 100;
    double t = now();
    for (int i = 0; i < n; i++) {
        CGContextAddPath(ctx, path);
        CGContextFillPath(ctx);
        CGContextAddPath(ctx, path);
        CGContextStrokePath(ctx);
    }
    double micros = (now() - t) * 1000 / n;
    // the pixel in the middle of the shape
    uint8_t *data = CGBitmapContextGetData(ctx);
    size_t row = CGBitmapContextGetBytesPerRow(ctx);
    for (int i = 0; i < 4; i++) probe[i] = data[(h - 10) * row + 9 * 4 + i];
    CGPathRelease(path);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return micros;
}

int main(void) {
    @autoreleasepool {
        int failures = 0;
        uint8_t small[4], big[4];
        double a = microsPerShape(20, 20, small);
        microsPerShape(20, 20, small); // the first run includes one-time set-up
        a = microsPerShape(20, 20, small);
        double b = microsPerShape(1920, 1080, big);
        printf("BENCH 20x20: %.1f us per fill+stroke; 1920x1080: %.1f us (ratio %.1f)\n", a, b, b / a);
        if (!(b < a * 3)) {
            failures++;
            printf("FAIL: filling in a 1920x1080 context takes %.1f times as long as in a 20x20 one (limit 3)\n", b / a);
        }
        // The pixels do not depend on the context size either: the shape's own colour at its middle.
        for (int i = 0; i < 4; i++)
            if (small[i] != big[i]) {
                failures++;
                printf("FAIL: pixel byte %d is %d in the small context and %d in the large one\n", i, small[i], big[i]);
            }
        printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
        return failures != 0;
    }
}
