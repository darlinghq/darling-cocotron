#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { Width = 4, Height = 3, BytesPerRow = 20, BackingLength = BytesPerRow * Height };

// The source bytes are followed by a sentinel region inside the same allocation, so an
// unbounded crop reads sentinel bytes instead of unmapped memory.
static unsigned char backing[256];

static void pixel(int x, int y, unsigned char out[4]) {
    unsigned char base = (unsigned char)(10 * y + x + 1);
    out[0] = base;
    out[1] = (unsigned char)(base + 100);
    out[2] = (unsigned char)(base + 50);
    out[3] = 255;
}

static int expect_crop(CGImageRef source, CGRect rect, int x0, int y0, size_t width, size_t height,
                       const char *name) {
    CGImageRef crop = CGImageCreateWithImageInRect(source, rect);
    if (crop == NULL) {
        fprintf(stderr, "%s: NULL, expected %zux%zu\n", name, width, height);
        return 1;
    }
    int failures = 0;
    if (CGImageGetWidth(crop) != width || CGImageGetHeight(crop) != height) {
        fprintf(stderr, "%s: got %zux%zu, expected %zux%zu\n", name, CGImageGetWidth(crop),
                CGImageGetHeight(crop), width, height);
        failures++;
    } else {
        CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(crop));
        size_t stride = CGImageGetBytesPerRow(crop);
        if (data == NULL || CFDataGetLength(data) < stride * (height - 1) + width * 4) {
            fprintf(stderr, "%s: pixel data missing or short\n", name);
            failures++;
        } else {
            const unsigned char *bytes = CFDataGetBytePtr(data);
            for (size_t y = 0; y < height; y++) {
                for (size_t x = 0; x < width; x++) {
                    unsigned char want[4];
                    pixel(x0 + (int)x, y0 + (int)y, want);
                    if (memcmp(bytes + y * stride + x * 4, want, 4) != 0) {
                        fprintf(stderr, "%s: pixel (%zu,%zu) differs\n", name, x, y);
                        failures++;
                    }
                }
            }
        }
        if (data != NULL)
            CFRelease(data);
    }
    CGImageRelease(crop);
    return failures;
}

static int expect_null(CGImageRef source, CGRect rect, const char *name) {
    CGImageRef crop = CGImageCreateWithImageInRect(source, rect);
    if (crop != NULL) {
        fprintf(stderr, "%s: expected NULL, got %zux%zu\n", name, CGImageGetWidth(crop),
                CGImageGetHeight(crop));
        CGImageRelease(crop);
        return 1;
    }
    return 0;
}

int main(void) {
    memset(backing, 0xEE, sizeof backing);
    memset(backing, 0, BackingLength);
    for (int y = 0; y < Height; y++)
        for (int x = 0; x < Width; x++)
            pixel(x, y, backing + y * BytesPerRow + x * 4);

    CGDataProviderRef provider =
            CGDataProviderCreateWithData(NULL, backing, BackingLength, NULL);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef source = CGImageCreate(Width, Height, 8, 32, BytesPerRow, space,
                                      kCGImageAlphaPremultipliedLast, provider, NULL, false,
                                      kCGRenderingIntentDefault);
    if (source == NULL) {
        fprintf(stderr, "could not create the source image\n");
        return 2;
    }

    int failures = 0;
    failures += expect_crop(source, CGRectMake(1, 1, 2, 2), 1, 1, 2, 2, "interior");
    failures += expect_crop(source, CGRectMake(2, 1, 10, 10), 2, 1, 2, 2, "right-bottom overflow");
    failures += expect_crop(source, CGRectMake(-2, -1, 4, 3), 0, 0, 2, 2, "negative origin");
    failures += expect_crop(source, CGRectMake(0.5, 0.5, 1.2, 1.2), 0, 0, 2, 2, "fractional");
    failures += expect_crop(source, CGRectMake(0, 0, Width, Height), 0, 0, Width, Height, "whole");
    failures += expect_null(source, CGRectMake(10, 10, 2, 2), "fully outside");
    failures += expect_null(source, CGRectMake(1, 1, 0, 0), "empty");

    CGImageRelease(source);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    if (failures != 0) {
        fprintf(stderr, "%d crop check(s) failed\n", failures);
        return 1;
    }
    printf("crop bounds ok\n");
    return 0;
}
