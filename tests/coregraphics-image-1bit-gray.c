// Copyright (C) 2026 Lubos Dolezel
//
// One-bit-per-pixel DeviceGray images: 1 bit per component, rows packed from
// the most significant bit, a set bit is white. Drawing such an image at
// scale 1 gives white and black opaque pixels. An image that cannot be
// created (an unsupported component size) must come back NULL without
// crashing.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

enum { W = 8, H = 2 };

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

int main(void) {
    // Row 0: 1010 0101, row 1: 0000 1111.
    static const unsigned char bits[H] = {0xA5, 0x0F};
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bits, sizeof(bits), NULL);
    CGImageRef image = CGImageCreate(W, H, 1, 1, 1, gray, kCGImageAlphaNone, provider, NULL, false,
                                     kCGRenderingIntentDefault);
    CHECK(image != NULL, "1-bit gray image created");
    if (image == NULL)
        return 1;
    CHECK(CGImageGetBitsPerComponent(image) == 1 && CGImageGetBitsPerPixel(image) == 1, "bits per component/pixel");

    unsigned char out[W * H * 4];
    memset(out, 0, sizeof(out));
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(out, W, H, 8, W * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextDrawImage(context, CGRectMake(0, 0, W, H), image);
    CGContextRelease(context);

    for (int row = 0; row < H; row++) {
        for (int x = 0; x < W; x++) {
            unsigned char expected = (bits[row] & (0x80 >> x)) ? 255 : 0;
            const unsigned char *p = out + (row * W + x) * 4;
            CHECK(p[0] == expected && p[1] == expected && p[2] == expected && p[3] == 255,
                  "pixel (%d,%d) is %u,%u,%u,%u, expected grey %u opaque", x, row, p[0], p[1], p[2], p[3],
                  expected);
        }
    }
    CGImageRelease(image);

    // 3 bits per component is not a size any image can have.
    CGImageRef bad = CGImageCreate(W, H, 3, 3, 1, gray, kCGImageAlphaNone, provider, NULL, false,
                                   kCGRenderingIntentDefault);
    CHECK(bad == NULL, "unsupported component size returns NULL");
    if (bad != NULL)
        CGImageRelease(bad);

    CGColorSpaceRelease(rgb);
    CGColorSpaceRelease(gray);
    CGDataProviderRelease(provider);
    if (failures == 0)
        printf("PASS: 1-bit gray images\n");
    return failures ? 1 : 0;
}
