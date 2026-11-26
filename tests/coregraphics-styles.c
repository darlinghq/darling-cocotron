// Copyright (C) 2026 Lubos Dolezel
//
// Styles (CGStylePrivate.h): CF objects describing a shadow, focus ring,
// Gaussian blur or colour matrix, and CGContextSetStyle, which makes a style
// the context's current one. The struct layouts follow the declarations
// WebKit (BSD licensed) makes for this private interface; the expected values
// are those of Darling's implementation, not observations of macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

static int near(CGFloat a, CGFloat b) {
    return fabs((double) a - (double) b) < 1e-4;
}

static CGColorRef makeColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[4] = {r, g, b, a};
    CGColorRef color = CGColorCreate(space, components);
    CGColorSpaceRelease(space);
    return color;
}

// QUIRK test: a shadow style describes its offset as an azimuth (degrees,
// 180 more than the offset's direction) and a height (the offset's length),
// so that offset = (cos(azimuth - 180), sin(azimuth - 180)) * height. See the
// QUIRK comment at describeShadowOffset in CoreGraphics/CGStyle.m.
static void test_quirk_shadow_azimuth_and_height(void) {
    const CGSize offsets[] = {{3, 4}, {-5, 0}, {0, -2}, {-1, -1}};
    for (size_t i = 0; i < sizeof(offsets) / sizeof(offsets[0]); i++) {
        CGStyleRef style = CGStyleCreateShadow2(offsets[i], 2, NULL);
        const CGShadowStyle *shadow = CGStyleGetData(style);
        CHECK(shadow != NULL, "a shadow style has data");
        if (shadow == NULL)
            continue;
        CGFloat angle = (shadow->azimuth - 180) * M_PI / 180;
        CHECK(near(cos(angle) * shadow->height, offsets[i].width) &&
              near(sin(angle) * shadow->height, offsets[i].height),
              "the azimuth and height give back the offset");
        CHECK(near(shadow->radius, 2), "the radius is kept");
        CGStyleRelease(style);
    }
    // the values macOS 26.7.3 gives (black-box observation)
    const struct { CGSize offset; CGFloat azimuth, height; } observed[] = {
        {{3, 4}, 233.13010235415598, 5}, {{0, 5}, 270, 5}, {{-5, 0}, 360, 5},
        {{0, -2}, 90, 2}, {{0, 0}, 180, 0},
    };
    for (size_t i = 0; i < sizeof(observed) / sizeof(observed[0]); i++) {
        CGStyleRef style = CGStyleCreateShadow2(observed[i].offset, 7, NULL);
        const CGShadowStyle *shadow = CGStyleGetData(style);
        CHECK(near(shadow->azimuth, observed[i].azimuth) && near(shadow->height, observed[i].height),
              "the azimuth and height are those macOS gives");
        CHECK(shadow->a == 0 && near(shadow->b, 45) && near(shadow->c, 0) && near(shadow->d, 1) &&
              near(shadow->radius, 7), "the other fields are those macOS gives");
        CGStyleRelease(style);
    }
}

static void testShadowStyle(void) {
    CGColorRef red = makeColor(1, 0, 0, 1);
    CGStyleRef style = CGStyleCreateShadow2(CGSizeMake(1, 2), 3, red);
    CHECK(style != NULL, "a shadow style is created");
    CHECK(CFGetTypeID(style) == CGStyleGetTypeID(), "a style is a CF object of its type");
    CHECK(CGStyleGetType(style) == kCGStyleShadow, "the style is a shadow");
    CHECK(CFEqual(CGStyleGetColor(style), red), "the colour is kept");
    CHECK(CGStyleRetain(style) == style, "retain returns the style");
    CGStyleRelease(style);
    CGStyleRelease(style);

    // a shadow made without a colour has none (observed on macOS 26.7.3); it is
    // drawn with CGContextSetShadow's default colour
    style = CGStyleCreateShadow2(CGSizeZero, 0, NULL);
    CHECK(CGStyleGetColor(style) == NULL, "a shadow without a colour has none");
    CGStyleRelease(style);
    CGColorRelease(red);
}

static void testOtherStyles(void) {
    CGColorRef blue = makeColor(0, 0, 1, 1);
    CGFocusRingStyle ring;
    memset(&ring, 0, sizeof(ring));
    ring.ordering = kCGFocusRingOrderingAbove;
    ring.alpha = 0.5;
    ring.radius = 3;
    CGStyleRef style = CGStyleCreateFocusRingWithColor(&ring, blue);
    CHECK(CGStyleGetType(style) == kCGStyleFocusRing, "a focus ring style");
    const CGFocusRingStyle *data = CGStyleGetData(style);
    CHECK(data != NULL && near(data->radius, 3) && data->ordering == kCGFocusRingOrderingAbove,
          "the focus ring is kept");
    CGStyleRelease(style);
    CHECK(CGStyleCreateFocusRingWithColor(NULL, blue) == NULL, "no focus ring without a description");
    CHECK(CGStyleCreateFocusRingWithColor(&ring, NULL) == NULL, "no focus ring without a colour");

    CGGaussianBlurStyle blur = {0, 4};
    style = CGStyleCreateGaussianBlur(&blur);
    CHECK(CGStyleGetType(style) == kCGStyleGaussianBlur, "a blur style");
    CHECK(near(((const CGGaussianBlurStyle *) CGStyleGetData(style))->radius, 4), "the blur radius is kept");
    CGStyleRelease(style);
    CHECK(CGStyleCreateGaussianBlur(NULL) == NULL, "no blur without a description");

    CGColorMatrixStyle matrix;
    memset(&matrix, 0, sizeof(matrix));
    matrix.matrix[0] = 1;
    matrix.matrix[19] = 0.5;
    style = CGStyleCreateColorMatrix(&matrix);
    CHECK(CGStyleGetType(style) == kCGStyleColorMatrix, "a colour matrix style");
    CHECK(near(((const CGColorMatrixStyle *) CGStyleGetData(style))->matrix[19], 0.5), "the matrix is kept");
    CGStyleRelease(style);
    CHECK(CGStyleCreateColorMatrix(NULL) == NULL, "no colour matrix without a description");

    CHECK(CGStyleGetType(NULL) == kCGStyleUnknown, "NULL style: unknown type");
    CHECK(CGStyleGetData(NULL) == NULL, "NULL style: no data");
    CHECK(CGStyleGetColor(NULL) == NULL, "NULL style: no colour");
    CHECK(CGStyleRetain(NULL) == NULL, "retaining NULL gives NULL");
    CGStyleRelease(NULL);
    CGColorRelease(blue);
}

// The style a delegate sees in the graphics state.
static CGStyleType seenType;
static CGFloat seenRadius;

static CGError recordStyle(CGContextDelegateRef delegate, CGRenderingStateRef rstate, CGGStateRef gstate,
                           CGPathDrawingMode mode, CGPathRef path) {
    CGStyleRef style = CGGStateGetStyle(gstate);
    seenType = style != NULL ? CGStyleGetType(style) : kCGStyleUnknown;
    seenRadius = -1;
    if (seenType == kCGStyleShadow)
        seenRadius = ((const CGShadowStyle *) CGStyleGetData(style))->radius;
    return kCGErrorSuccess;
}

static void testStyleInState(void) {
    CGContextDelegateRef delegate = CGContextDelegateCreate(NULL);
    CGContextDelegateSetCallback(delegate, deDrawPath, (CGContextDelegateCallback) recordStyle);
    CGContextRef c = CGContextCreateWithDelegate(delegate, kCGContextTypeUnknown, NULL, NULL);

    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleUnknown, "no style at first");

    CGStyleRef style = CGStyleCreateShadow2(CGSizeMake(1, 1), 6, NULL);
    CGContextSetStyle(c, style);
    CGStyleRelease(style);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleShadow && near(seenRadius, 6), "the set style is in the state");

    CGContextSaveGState(c);
    CGContextSetStyle(c, NULL);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleUnknown, "setting NULL removes the style");
    CGContextRestoreGState(c);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleShadow, "the style is part of the saved state");

    // a shadow set the public way is reported as a shadow style
    CGContextSetShadow(c, CGSizeMake(2, 2), 9);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleShadow && near(seenRadius, 9), "a shadow is reported as a style");
    CGContextSetShadowWithColor(c, CGSizeZero, 0, NULL);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(seenType == kCGStyleUnknown, "no shadow, no style");

    CGContextSetStyle(NULL, NULL);
    CGContextRelease(c);
    CGContextDelegateRelease(delegate);
}

static void testShadowDrawn(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    unsigned char pixels[40 * 40 * 4];
    memset(pixels, 0, sizeof(pixels));
    CGContextRef c = CGBitmapContextCreate(pixels, 40, 40, 8, 40 * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorRef red = makeColor(1, 0, 0, 1);
    CGStyleRef style = CGStyleCreateShadow2(CGSizeMake(20, 0), 1, red);
    CGContextSetStyle(c, style);
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(5, 10, 10, 20));
    // the shape at x 5..15, its shadow at x 25..35
    const unsigned char *shape = pixels + (20 * 40 + 10) * 4;
    const unsigned char *shadow = pixels + (20 * 40 + 30) * 4;
    const unsigned char *clear = pixels + (20 * 40 + 20) * 4;
    CHECK(shape[2] > 200 && shape[0] < 50, "the shape is drawn");
    CHECK(shadow[0] > 200 && shadow[3] > 200, "the shadow of a shadow style is drawn at its offset");
    CHECK(clear[3] < 50, "nothing between the shape and its shadow");
    CGStyleRelease(style);
    CGColorRelease(red);
    CGContextRelease(c);
    CGColorSpaceRelease(space);
}

int main(void) {
    test_quirk_shadow_azimuth_and_height();
    testShadowStyle();
    testOtherStyles();
    testStyleInState();
    testShadowDrawn();
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
