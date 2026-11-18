// Copyright (C) 2026 Lubos Dolezel
//
// -[NSImageRep drawInRect:fromRect:operation:fraction:respectFlipped:hints:] (public AppKit API since 10.6,
// declared on NSImageRep and so available on every representation, NSBitmapImageRep included): draws the
// given part of the representation, or all of it for an empty rectangle, into the destination rectangle with
// the given opacity, and returns YES when it drew (also for an empty destination, which draws nothing; observed on macOS 26.7.3). The 2x1 source has a red left pixel and a blue right pixel;
// the interpolation hint is NSImageInterpolationNone so edges are exact. Passes on macOS. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Repeats the public declaration so the test also builds against SDK headers that lack it.
@interface NSImageRep (DrawFromRectHintsTest)
- (BOOL) drawInRect: (NSRect) rect
           fromRect: (NSRect) fromRect
          operation: (NSCompositingOperation) operation
           fraction: (CGFloat) fraction
     respectFlipped: (BOOL) respectFlipped
              hints: (NSDictionary<NSString *, id> *) hints;
@end

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

static NSBitmapImageRep *newBitmap(NSInteger width, NSInteger height) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                    pixelsWide: width
                                                                    pixelsHigh: height
                                                                 bitsPerSample: 8
                                                               samplesPerPixel: 4
                                                                      hasAlpha: YES
                                                                      isPlanar: NO
                                                                colorSpaceName: NSDeviceRGBColorSpace
                                                                   bytesPerRow: 0
                                                                  bitsPerPixel: 32];
    memset([rep bitmapData], 0, [rep bytesPerRow] * height);
    return rep;
}

static NSBitmapImageRep *newSource(void) {
    NSBitmapImageRep *rep = newBitmap(2, 1);
    unsigned char *p = [rep bitmapData];
    p[0] = 255; p[1] = 0; p[2] = 0; p[3] = 255;
    p[4] = 0; p[5] = 0; p[6] = 255; p[7] = 255;
    return rep;
}

// Draws the source with the given arguments into a fresh 4x4 destination; returns the destination.
static NSBitmapImageRep *draw(NSBitmapImageRep *source, NSRect from, CGFloat fraction, BOOL flipped, BOOL *result) {
    NSBitmapImageRep *destination = newBitmap(4, 4);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: destination];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    BOOL drew = [source drawInRect: NSMakeRect(0, 0, 4, 4)
                          fromRect: from
                         operation: NSCompositingOperationSourceOver
                          fraction: fraction
                    respectFlipped: flipped
                             hints: @{NSImageHintInterpolation : @(NSImageInterpolationNone)}];
    [NSGraphicsContext restoreGraphicsState];
    if (result != NULL)
        *result = drew;
    return destination;
}

static unsigned char *pixel(NSBitmapImageRep *rep, int x, int y) {
    return [rep bitmapData] + y * [rep bytesPerRow] + x * 4;
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSBitmapImageRep *source = newSource();

    CHECK([source respondsToSelector: @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:)],
          "NSBitmapImageRep does not respond to drawInRect:fromRect:operation:fraction:respectFlipped:hints:");
    CHECK([NSImageRep instancesRespondToSelector: @selector(drawInRect:fromRect:operation:fraction:respectFlipped:hints:)],
          "NSImageRep does not declare the selector");
    if (failures)
        return 1;

    BOOL drew = NO;
    NSBitmapImageRep *whole = draw(source, NSZeroRect, 1.0, NO, &drew);
    CHECK(drew, "whole source: returned NO");
    CHECK(pixel(whole, 0, 1)[0] > 250 && pixel(whole, 0, 1)[2] < 5, "whole source: left half is not red");
    CHECK(pixel(whole, 3, 2)[2] > 250 && pixel(whole, 3, 2)[0] < 5, "whole source: right half is not blue");
    CHECK(pixel(whole, 1, 0)[0] > 250, "whole source: x=1 is not red");
    CHECK(pixel(whole, 2, 0)[2] > 250, "whole source: x=2 is not blue");

    // A part of the source fills the destination.
    NSBitmapImageRep *part = draw(source, NSMakeRect(1, 0, 1, 1), 1.0, NO, &drew);
    CHECK(drew, "source part: returned NO");
    CHECK(pixel(part, 0, 0)[2] > 250 && pixel(part, 0, 0)[0] < 5, "source part: left edge is not blue");
    CHECK(pixel(part, 3, 3)[2] > 250 && pixel(part, 3, 3)[0] < 5, "source part: right edge is not blue");

    // The opacity applies to the whole drawing.
    NSBitmapImageRep *half = draw(source, NSZeroRect, 0.5, NO, &drew);
    CHECK(drew, "half fraction: returned NO");
    CHECK(abs(pixel(half, 0, 0)[3] - 128) <= 3, "half fraction: alpha is %d", pixel(half, 0, 0)[3]);

    // Flipping is about the vertical axis only; the columns keep their places.
    NSBitmapImageRep *flipped = draw(source, NSZeroRect, 1.0, YES, &drew);
    CHECK(drew, "respectFlipped: returned NO");
    CHECK(pixel(flipped, 0, 0)[0] > 250 && pixel(flipped, 3, 0)[2] > 250, "respectFlipped: columns changed");

    // An empty destination draws nothing.
    NSBitmapImageRep *destination = newBitmap(4, 4);
    NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep: destination];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    BOOL emptyResult = [source drawInRect: NSZeroRect
                                 fromRect: NSZeroRect
                                operation: NSCompositingOperationSourceOver
                                 fraction: 1.0
                           respectFlipped: NO
                                    hints: nil];
    [NSGraphicsContext restoreGraphicsState];
    CHECK(emptyResult, "empty destination: returned NO (macOS 26.7.3 returns YES and draws nothing)");
    CHECK(pixel(destination, 0, 0)[3] == 0, "empty destination: pixels were written");

    [pool drain];
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
