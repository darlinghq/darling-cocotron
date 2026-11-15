// Copyright (C) 2026 Lubos Dolezel
//
// Private CoreGraphics functions with observable behaviour: the composite
// operation (the context's blend mode under another numbering), the dash
// pattern getters, CGFloatIsValid and CGBitmapGetAlignedBytesPerRow. Expected
// values were observed by calling the functions on macOS 26.7.3 (see the
// QUIRK comments next to the implementations).
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

static CGContextRef makeContext(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(NULL, 1, 1, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    return c;
}

static unsigned pixel(CGContextRef c) {
    const unsigned char *d = CGBitmapContextGetData(c);
    return (unsigned)d[0] << 24 | d[1] << 16 | d[2] << 8 | d[3];
}

// Premultiplied blue 0.25 destination, then red 0.75 drawn with the mode set by
// the given function.
static unsigned drawWith(int useOperation, int value) {
    CGContextRef c = makeContext();
    CGContextSetRGBFillColor(c, 0, 0, 1, 0.25);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    if (useOperation)
        CGContextSetCompositeOperation(c, value);
    else
        CGContextSetBlendMode(c, (CGBlendMode)value);
    CGContextSetRGBFillColor(c, 1, 0, 0, 0.75);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    unsigned p = pixel(c);
    CGContextRelease(c);
    return p;
}

int main(void) {
    // Observed getter values after CGContextSetBlendMode(mode), indexed by mode.
    static const int expectedOperation[28] = {
        2, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27,
        0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
    };
    CGContextRef c = makeContext();
    CHECK(CGContextGetCompositeOperation(c) == 2, "a new context reports operation 2");
    for (int mode = 0; mode < 28; mode++) {
        CGContextSetBlendMode(c, (CGBlendMode)mode);
        CHECK(CGContextGetCompositeOperation(c) == expectedOperation[mode], "operation after SetBlendMode");
    }
    // The setter draws like the blend mode that reports the same operation
    // (the modes whose engine result differs between implementations are skipped).
    for (int mode = 0; mode < 28; mode++) {
        if (mode == kCGBlendModeOverlay || mode == kCGBlendModeColorDodge || mode == kCGBlendModeColorBurn ||
            mode == kCGBlendModeSoftLight || mode == kCGBlendModeHardLight || mode == kCGBlendModeHue ||
            mode == kCGBlendModeSaturation || mode == kCGBlendModeColor || mode == kCGBlendModeLuminosity ||
            mode == kCGBlendModePlusDarker)
            continue;
        CHECK(drawWith(1, expectedOperation[mode]) == drawWith(0, mode), "SetCompositeOperation draws as the blend mode");
    }
    CGContextSetCompositeOperation(c, 5);
    CGContextSaveGState(c);
    CGContextSetCompositeOperation(c, 9);
    CGContextRestoreGState(c);
    CHECK(CGContextGetCompositeOperation(c) == 5, "restoring the state restores the operation");
    CGContextRelease(c);

    // Dash pattern: phase first, lengths up to the capacity.
    c = makeContext();
    CGFloat dashes[3] = {3, 5, 7};
    CGContextSetLineDash(c, 2, dashes, 3);
    CHECK(CGContextGetLineDashCount(c) == 3, "dash count");
    for (size_t capacity = 0; capacity <= 4; capacity++) {
        CGFloat phase = -111, lengths[4] = {-222, -222, -222, -222};
        CGContextGetLineDashPattern(c, &phase, lengths, capacity);
        CHECK(phase == 2, "phase is written regardless of the capacity");
        for (size_t i = 0; i < 4; i++) {
            double expected = i < capacity && i < 3 ? dashes[i] : -222;
            CHECK(lengths[i] == expected, "lengths up to the capacity");
        }
    }
    CGContextSetLineDash(c, 0, NULL, 0);
    CHECK(CGContextGetLineDashCount(c) == 0, "no dash: count 0");
    CGFloat phase = -1, lengths[2] = {-2, -2};
    CGContextGetLineDashPattern(c, &phase, lengths, 2);
    CHECK(phase == 0 && lengths[0] == -2, "no dash: phase 0, no lengths");
    CGContextRelease(c);

    CHECK(CGFloatIsValid(0) && CGFloatIsValid(-0.0) && CGFloatIsValid(1) && CGFloatIsValid(-1) &&
          CGFloatIsValid(5e-324) && CGFloatIsValid(1.7976931348623157e308) && CGFloatIsValid(1e39), "finite values are valid");
    CHECK(!CGFloatIsValid(NAN) && !CGFloatIsValid(-NAN) && !CGFloatIsValid(INFINITY) && !CGFloatIsValid(-INFINITY),
          "NaN and infinities are invalid");

    static const size_t in[] = {0, 1, 4, 31, 32, 33, 63, 64, 65, 100, 1000, 10000};
    static const size_t out[] = {0, 32, 32, 32, 32, 64, 64, 64, 96, 128, 1024, 10016};
    for (size_t i = 0; i < sizeof in / sizeof in[0]; i++)
        CHECK(CGBitmapGetAlignedBytesPerRow(in[i]) == out[i], "aligned bytes per row");
    CHECK(CGBitmapGetAlignedBytesPerRow(SIZE_MAX - 31) == SIZE_MAX - 31, "SIZE_MAX - 31 is aligned");
    CHECK(CGBitmapGetAlignedBytesPerRow(SIZE_MAX - 30) == 0, "wraps to 0 above SIZE_MAX - 31");
    CHECK(CGBitmapGetAlignedBytesPerRow(SIZE_MAX) == 0, "SIZE_MAX wraps to 0");

    if (failures == 0)
        printf("PASS: private CoreGraphics context functions\n");
    return failures ? 1 : 0;
}
