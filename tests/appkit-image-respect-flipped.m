/* Copyright (C) 2026 Lubos Dolezel */
// -[NSImage drawInRect:fromRect:operation:fraction:respectFlipped:hints:]: with respectFlipped YES a flipped
// graphics context shows the image upright; with NO the image keeps the context's raw orientation (upside down in a
// flipped context). In an unflipped context both give the same upright picture. Pixel test into a bitmap context,
// no window needed. Observed behaviour on macOS 26.7.3 and 10.14.4 matches the expectations below.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { W = 20, H = 20 };

static void expect(BOOL condition, const char *message) {
    if (!condition) { printf("FAIL: %s\n", message); exit(1); }
}

static NSImage *testImage(void) {
    // 2x2 pixels: top row red, bottom row blue (CGImage data starts at the top row).
    static const unsigned char pixels[16] = {
        255, 0, 0, 255, 255, 0, 0, 255,
        0, 0, 255, 255, 0, 0, 255, 255,
    };
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, sizeof(pixels), NULL);
    CGImageRef cgImage = CGImageCreate(2, 2, 8, 32, 8, rgb, kCGImageAlphaPremultipliedLast, provider, NULL, false,
                                       kCGRenderingIntentDefault);
    NSImage *image = [[[NSImage alloc] initWithCGImage: cgImage size: NSMakeSize(2, 2)] autorelease];
    CGImageRelease(cgImage);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(rgb);
    return image;
}

// Draws the image into the 10x10 rect at the visual top-left of a 20x20 bitmap and returns whether the visual top
// of the drawn area is red (YES) or blue (NO); fails if neither.
static BOOL topIsRed(BOOL flipped, BOOL respectFlipped) {
    unsigned char *data = calloc(W * H * 4, 1);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef cg = CGBitmapContextCreate(data, W, H, 8, W * 4, rgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(rgb);
    if (flipped) {
        CGContextTranslateCTM(cg, 0, H);
        CGContextScaleCTM(cg, 1, -1);
    }
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithCGContext: cg flipped: flipped];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    // The rect at the visual top: y 0 when flipped, y 10 (bottom-left origin) otherwise.
    NSRect rect = NSMakeRect(0, flipped ? 0 : 10, 10, 10);
    [testImage() drawInRect: rect
                   fromRect: NSZeroRect
                  operation: NSCompositingOperationSourceOver
                   fraction: 1
             respectFlipped: respectFlipped
                      hints: nil];
    [NSGraphicsContext restoreGraphicsState];

    // Bitmap data row 0 is the visual top.
    const unsigned char *top = data + (2 * W + 5) * 4;
    const unsigned char *bottom = data + (7 * W + 5) * 4;
    BOOL red = top[0] == 255 && top[2] == 0 && top[3] == 255 && bottom[2] == 255 && bottom[0] == 0;
    BOOL blue = top[2] == 255 && top[0] == 0 && top[3] == 255 && bottom[0] == 255 && bottom[2] == 0;
    CGContextRelease(cg);
    free(data);
    expect(red || blue, "the drawn area is red over blue or blue over red");
    return red;
}

int main(void) {
    @autoreleasepool {
        expect(topIsRed(NO, NO), "unflipped, respectFlipped NO: upright");
        expect(topIsRed(NO, YES), "unflipped, respectFlipped YES: upright");
        expect(!topIsRed(YES, NO), "flipped, respectFlipped NO: upside down");
        expect(topIsRed(YES, YES), "flipped, respectFlipped YES: upright");
    }
    printf("PASS: NSImage respectFlipped\n");
    return 0;
}
