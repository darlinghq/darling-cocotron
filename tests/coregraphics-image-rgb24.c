#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>

// An image with 8 bits per component, 24 bits per pixel and no alpha stores each pixel
// as three bytes R, G, B, and each row starts bytesPerRow bytes after the previous one.
// The colours differ per pixel and per row, so reading 4-byte pixels or a wrong row
// stride shows up as a wrong colour.
// Exits non-zero on failure.

int main(void) {
    enum { width = 3, height = 2, bytesPerRow = width * 3 };
    static const unsigned char samples[height * bytesPerRow] = {
        255, 0, 0, 0, 255, 0, 0, 0, 255,
        255, 255, 0, 0, 255, 255, 255, 0, 255,
    };
    int failures = 0;

    CFDataRef data = CFDataCreate(NULL, samples, sizeof(samples));
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CFRelease(data);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 24, bytesPerRow, space, (CGBitmapInfo)kCGImageAlphaNone,
                                     provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    if (image == NULL) {
        CGColorSpaceRelease(space);
        printf("FAIL: CGImageCreate returned NULL for a 24-bit RGB image\n");
        return 1;
    }

    unsigned char pixels[width * height * 4];
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space,
                                                 (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);

    // Both the image samples and the bitmap context have row 0 at the top.
    for (int i = 0; i < width * height; i++) {
        const unsigned char *expected = samples + (i / width) * bytesPerRow + (i % width) * 3;
        const unsigned char *got = pixels + i * 4;
        if (abs(got[0] - expected[0]) > 2 || abs(got[1] - expected[1]) > 2 || abs(got[2] - expected[2]) > 2 || got[3] != 255) {
            printf("FAIL: pixel %d is %u %u %u %u, expected %u %u %u 255\n", i, got[0], got[1], got[2], got[3],
                   expected[0], expected[1], expected[2]);
            failures++;
        }
    }
    if (failures)
        return failures;
    puts("24-bit RGB image samples passed");
    return 0;
}
