// Copyright (C) 2026 Lubos Dolezel
//
// Images drawn at their own size on whole-pixel positions (the row copy path
// in Onyx2D) must give the pixels the documented drawing model gives:
// premultiplied source-over, kCGBlendModeCopy replacing, opaque formats
// forcing alpha 255, flipping and clipping honoured. Expected values are
// computed here from the source-over formula, so the test also runs on macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

enum { W = 4, H = 3, SURFACE = 8 };

// Source pixels as R, G, B, A (premultiplied).
static const unsigned char sourceRGBA[H][W][4] = {
    {{255, 0, 0, 255}, {0, 128, 0, 128}, {0, 0, 0, 0}, {10, 20, 30, 40}},
    {{1, 2, 3, 255}, {100, 0, 0, 200}, {0, 0, 64, 64}, {255, 255, 255, 255}},
    {{9, 8, 7, 255}, {50, 50, 50, 100}, {200, 100, 0, 255}, {0, 255, 0, 255}},
};

static CGContextRef makeSurface(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, SURFACE, SURFACE, 8, 0, space,
                                           kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(c, 0, 0, 1, 1); // opaque blue background
    CGContextFillRect(c, CGRectMake(0, 0, SURFACE, SURFACE));
    return c;
}

// The image in one of the pixel layouts; BGRA is the surface's own order.
static CGImageRef makeImage(int layout) {
    unsigned char *bytes = malloc(W * H * 4);
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            const unsigned char *p = sourceRGBA[y][x];
            unsigned char *q = bytes + (y * W + x) * 4;
            if (layout == 0) { // RGBA premultiplied last
                q[0] = p[0]; q[1] = p[1]; q[2] = p[2]; q[3] = p[3];
            } else if (layout == 1) { // BGRA premultiplied first, little endian
                q[0] = p[2]; q[1] = p[1]; q[2] = p[0]; q[3] = p[3];
            } else if (layout == 2) { // RGBX, alpha byte ignored
                q[0] = p[0]; q[1] = p[1]; q[2] = p[2]; q[3] = 7;
            } else { // BGRX little endian, alpha byte ignored
                q[0] = p[2]; q[1] = p[1]; q[2] = p[0]; q[3] = 7;
            }
        }
    CGBitmapInfo info[] = {
        kCGImageAlphaPremultipliedLast,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little,
        kCGImageAlphaNoneSkipLast,
        kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
    };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bytes, W * H * 4, NULL);
    CGImageRef image = CGImageCreate(W, H, 8, 32, W * 4, space, info[layout], provider, NULL, false,
                                     kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    return image;
}

static int near(int a, int b, int tolerance) {
    return abs(a - b) <= tolerance;
}

// Compare the surface with the expected result of drawing the image's top row at
// bitmap row topRow (columns from left), flipped or not, restricted to [clipLeft, clipRight).
static void verify(CGContextRef surface, int layout, int mode, double alpha, int left, int topRow, int flipped,
                   int clipLeft, int clipRight, const char *label) {
    const unsigned char *data = CGBitmapContextGetData(surface);
    size_t stride = CGBitmapContextGetBytesPerRow(surface);
    int opaque = layout >= 2;
    for (int y = 0; y < SURFACE; y++)
        for (int x = 0; x < SURFACE; x++) {
            int expected[4] = {255, 0, 0, 255}; // B, G, R, A of the blue background
            int c = x - left, r = y - topRow;
            if (c >= 0 && c < W && r >= 0 && r < H && x >= clipLeft && x < clipRight) {
                const unsigned char *p = sourceRGBA[flipped ? H - 1 - r : r][c];
                int a = opaque ? 255 : p[3];
                int src[4] = {p[2], p[1], p[0], a}; // B, G, R, A
                if (opaque || mode == kCGBlendModeCopy || alpha == 1.0) {
                    for (int i = 0; i < 4; i++)
                        expected[i] = (mode == kCGBlendModeCopy || opaque) ? src[i]
                                      : src[i] + expected[i] * (255 - a) / 255;
                }
            }
            const unsigned char *got = data + y * stride + x * 4;
            for (int i = 0; i < 4; i++)
                if (!near(got[i], expected[i], 1)) {
                    fprintf(stderr, "FAIL: %s: pixel (%d,%d) channel %d is %d, expected %d\n", label, x, y, i,
                            got[i], expected[i]);
                    failures++;
                    return;
                }
        }
}

int main(void) {
    const char *names[] = {"RGBA", "BGRA", "RGBX", "BGRX"};
    for (int layout = 0; layout < 4; layout++) {
        CGImageRef image = makeImage(layout);
        char label[64];
        for (int mode = 0; mode < 2; mode++) {
            CGBlendMode blend = mode ? kCGBlendModeCopy : kCGBlendModeNormal;
            // Unflipped at (2, 1) from the bottom: its top row lands on bitmap row 8 - 1 - 3 = 4.
            CGContextRef s = makeSurface();
            CGContextSetBlendMode(s, blend);
            CGContextDrawImage(s, CGRectMake(2, 1, W, H), image);
            snprintf(label, sizeof label, "%s plain, blend %d", names[layout], (int)blend);
            verify(s, layout, blend, 1.0, 2, 4, 0, 0, SURFACE, label);
            CGContextRelease(s);

            // Clipped to columns 3..5.
            s = makeSurface();
            CGContextSetBlendMode(s, blend);
            CGContextClipToRect(s, CGRectMake(3, 0, 3, SURFACE));
            CGContextDrawImage(s, CGRectMake(2, 1, W, H), image);
            snprintf(label, sizeof label, "%s clipped, blend %d", names[layout], (int)blend);
            verify(s, layout, blend, 1.0, 2, 4, 0, 3, 6, label);
            CGContextRelease(s);

            // Flipped vertically: the user space is flipped, and the image is drawn into the mirrored rect.
            s = makeSurface();
            CGContextSetBlendMode(s, blend);
            CGContextTranslateCTM(s, 0, SURFACE);
            CGContextScaleCTM(s, 1, -1);
            CGContextDrawImage(s, CGRectMake(1, 2, W, H), image);
            snprintf(label, sizeof label, "%s flipped, blend %d", names[layout], (int)blend);
            verify(s, layout, blend, 1.0, 1, 2, 1, 0, SURFACE, label);
            CGContextRelease(s);
        }
        // Partly off the surface.
        CGContextRef s = makeSurface();
        CGContextDrawImage(s, CGRectMake(-2, 6, W, H), image);
        snprintf(label, sizeof label, "%s off the edge", names[layout]);
        {
            const unsigned char *data = CGBitmapContextGetData(s);
            size_t stride = CGBitmapContextGetBytesPerRow(s);
            // Bottom-left origin (-2, 6), top row on bitmap row 8 - 6 - 3 = -1: rows 0..1 are image rows 1..2,
            // columns 0..1 are image columns 2..3.
            const unsigned char *p = sourceRGBA[1][2]; // bitmap (0, 0)
            int opaque = layout >= 2;
            int a = opaque ? 255 : p[3];
            int expectedB = opaque ? p[2] : p[2] + 255 * (255 - a) / 255;
            CHECK(near(data[0 * stride + 0 * 4 + 0], expectedB, 1), "off-edge pixel (0,0) blue");
            CHECK(near(data[0 * stride + 2 * 4 + 0], 255, 0), "pixel (2,0) untouched");
            CHECK(near(data[3 * stride + 0 * 4 + 0], 255, 0), "pixel (0,3) untouched");
        }
        CGContextRelease(s);

        // Constant alpha is applied (not a copy).
        s = makeSurface();
        CGContextSetAlpha(s, 0.5);
        CGContextDrawImage(s, CGRectMake(2, 1, W, H), image);
        {
            const unsigned char *data = CGBitmapContextGetData(s);
            size_t stride = CGBitmapContextGetBytesPerRow(s);
            const unsigned char *p = sourceRGBA[0][0]; // opaque red, bitmap (2, 4)
            const unsigned char *got = data + 4 * stride + 2 * 4;
            CHECK(near(got[2], p[0] / 2, 2) && near(got[0], 127, 2), "alpha 0.5 blends red over blue");
        }
        CGContextRelease(s);
        CGImageRelease(image);
    }
    if (failures == 0)
        printf("PASS: image drawn pixel for pixel\n");
    return failures ? 1 : 0;
}
