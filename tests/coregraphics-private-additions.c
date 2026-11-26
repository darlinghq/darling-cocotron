// Copyright (C) 2026 Lubos Dolezel
//
// Private CoreGraphics functions declared in CoreGraphicsPrivate.h for
// WebKit: context state accessors, conic gradients, drawing a path without
// touching the current path, rounded rectangles with uneven corners, region
// enumeration, copied data providers, image caching flags, premultiplied
// gradient interpolation, colour space comparison and description, colour
// transforms and image patterns. Expected values are those of Darling's
// implementation (see the comments in CoreGraphicsPrivate.h), not
// observations of macOS.
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

static int near(CGFloat a, CGFloat b, CGFloat tolerance) {
    return fabs((double) a - (double) b) <= tolerance;
}

#define SIZE 21

typedef struct {
    unsigned char pixels[SIZE * SIZE * 4];
    CGContextRef context;
    CGColorSpaceRef space;
} Bitmap;

static void bitmapInit(Bitmap *b) {
    memset(b->pixels, 0, sizeof(b->pixels));
    b->space = CGColorSpaceCreateDeviceRGB();
    b->context = CGBitmapContextCreate(b->pixels, SIZE, SIZE, 8, SIZE * 4, b->space,
                                       kCGImageAlphaPremultipliedLast);
}

static void bitmapFree(Bitmap *b) {
    CGContextRelease(b->context);
    CGColorSpaceRelease(b->space);
}

// The pixel at (x, y) in user space of an unscaled context (y up).
static const unsigned char *pixelAt(const Bitmap *b, int x, int y) {
    return b->pixels + ((SIZE - 1 - y) * SIZE + x) * 4;
}

static void testContextState(void) {
    Bitmap b;
    bitmapInit(&b);
    CGContextRef c = b.context;

    CHECK(CGAffineTransformIsIdentity(CGContextGetBaseCTM(c)), "the base CTM starts as identity");
    CGAffineTransform base = CGAffineTransformMakeScale(2, 2);
    CGContextSetBaseCTM(c, base);
    CHECK(CGAffineTransformEqualToTransform(CGContextGetBaseCTM(c), base), "the base CTM is kept");
    CHECK(CGAffineTransformIsIdentity(CGContextGetCTM(c)), "setting the base CTM leaves the CTM alone");
    CGContextSaveGState(c);
    CGContextSetBaseCTM(c, CGAffineTransformIdentity);
    CGContextRestoreGState(c);
    CHECK(CGAffineTransformEqualToTransform(CGContextGetBaseCTM(c), base), "the base CTM is saved state");
    CHECK(CGAffineTransformIsIdentity(CGContextGetBaseCTM(NULL)), "NULL context: identity base CTM");
    CGContextSetBaseCTM(NULL, base);

    CGContextSetRGBFillColor(c, 1, 0, 0, 1);
    CGContextSetRGBStrokeColor(c, 0, 1, 0, 0.5);
    CGColorRef fill = CGContextGetFillColorAsColor(c);
    CGColorRef stroke = CGContextGetStrokeColorAsColor(c);
    CHECK(fill != NULL && near(CGColorGetComponents(fill)[0], 1, 1e-4), "the fill colour");
    CHECK(stroke != NULL && near(CGColorGetAlpha(stroke), 0.5, 1e-4), "the stroke colour");
    CHECK(CGContextGetFillColorAsColor(NULL) == NULL, "NULL context: no fill colour");
    CHECK(CGContextGetStrokeColorAsColor(NULL) == NULL, "NULL context: no stroke colour");

    CHECK(CGContextGetShouldAntialias(c), "antialiasing is on by default");
    CGContextSetShouldAntialias(c, false);
    CHECK(!CGContextGetShouldAntialias(c), "antialiasing can be turned off");
    CHECK(!CGContextGetShouldAntialias(NULL), "NULL context: no antialiasing");

    CHECK(CGContextGetShouldAntialiasFonts(c), "font antialiasing is on by default");
    CGContextSetShouldAntialiasFonts(c, false);
    CHECK(!CGContextGetShouldAntialiasFonts(c), "font antialiasing can be turned off");
    CGContextSetShouldAntialiasFonts(NULL, true);
    CHECK(!CGContextGetShouldAntialiasFonts(NULL), "NULL context: no font antialiasing");

    CGColorSpaceRef device = CGContextCopyDeviceColorSpace(c);
    CHECK(device != NULL && CGColorSpaceGetModel(device) == kCGColorSpaceModelRGB,
          "a bitmap context's device space is its space");
    CGColorSpaceRelease(device);
    CHECK(CGContextCopyDeviceColorSpace(NULL) == NULL, "NULL context: no device space");
    bitmapFree(&b);
}

static void testDrawPathDirect(void) {
    Bitmap b;
    bitmapInit(&b);
    CGContextRef c = b.context;
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextMoveToPoint(c, 1, 1);
    CGContextAddLineToPoint(c, 2, 1);
    CGRect before = CGContextGetPathBoundingBox(c);

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddRect(path, NULL, CGRectMake(10, 10, 5, 5));
    CGContextTranslateCTM(c, 2, 0);
    CGContextDrawPathDirect(c, kCGPathFill, path, NULL);
    CHECK(pixelAt(&b, 13, 12)[2] > 200, "the path is drawn in user space");
    CHECK(pixelAt(&b, 11, 12)[3] == 0, "the path is drawn with the CTM");
    CHECK(!CGContextIsPathEmpty(c), "the current path is kept");
    CGContextTranslateCTM(c, -2, 0);
    CHECK(CGRectEqualToRect(CGContextGetPathBoundingBox(c), before), "the current path is unchanged");
    CGContextDrawPathDirect(c, kCGPathFill, NULL, NULL);
    CGContextDrawPathDirect(NULL, kCGPathFill, path, NULL);
    CGPathRelease(path);
    bitmapFree(&b);
}

static void testConicGradient(void) {
    Bitmap b;
    bitmapInit(&b);
    CGFloat components[8] = {1, 0, 0, 1, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(b.space, components, NULL, 2);
    CGContextDrawConicGradient(b.context, gradient, CGPointMake(10.5, 10.5), 0);

    // The colour sweeps counterclockwise from the angle: a quarter at the
    // top, half at the left, three quarters at the bottom.
    const unsigned char *top = pixelAt(&b, 10, 19);
    const unsigned char *left = pixelAt(&b, 1, 10);
    const unsigned char *bottom = pixelAt(&b, 10, 1);
    CHECK(near(top[0], 191, 25) && near(top[2], 64, 25), "a quarter of the way at the top");
    CHECK(near(left[0], 128, 25) && near(left[2], 128, 25), "half way at the left");
    CHECK(near(bottom[0], 64, 25) && near(bottom[2], 191, 25), "three quarters at the bottom");
    CHECK(top[3] == 255 && pixelAt(&b, 0, 0)[3] == 255, "the gradient covers the whole clip");

    CGContextDrawConicGradient(b.context, NULL, CGPointZero, 0);
    CGContextDrawConicGradient(NULL, gradient, CGPointZero, 0);
    CGGradientRelease(gradient);

    CHECK(CGShadingCreateConic(NULL, CGPointZero, 0, NULL) == NULL, "no conic shading without a space");
    CHECK(CGShadingCreateConic(b.space, CGPointZero, 0, NULL) == NULL, "no conic shading without a function");
    bitmapFree(&b);
}

static void testUnevenCorners(void) {
    CGSize corners[4] = {{1, 1}, {2, 2}, {3, 3}, {4, 4}};
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathAddUnevenCornersRoundedRect(path, NULL, CGRectMake(0, 0, 20, 20), corners);
    CHECK(CGRectEqualToRect(CGPathGetBoundingBox(path), CGRectMake(0, 0, 20, 20)), "the path fills the rectangle");
    CHECK(CGPathContainsPoint(path, NULL, CGPointMake(0.5, 19.5), false), "radius 1 at (minX, maxY)");
    CHECK(!CGPathContainsPoint(path, NULL, CGPointMake(0.1, 19.9), false), "the (minX, maxY) corner is round");
    CHECK(!CGPathContainsPoint(path, NULL, CGPointMake(19.5, 19.5), false), "radius 2 at (maxX, maxY)");
    CHECK(!CGPathContainsPoint(path, NULL, CGPointMake(19.5, 0.5), false), "radius 3 at (maxX, minY)");
    CHECK(!CGPathContainsPoint(path, NULL, CGPointMake(0.5, 0.5), false), "radius 4 at (minX, minY)");
    CHECK(CGPathContainsPoint(path, NULL, CGPointMake(10, 10), false), "the middle is inside");
    CGPathRelease(path);

    path = CGPathCreateMutable();
    CGPathAddUnevenCornersRoundedRect(path, NULL, CGRectMake(0, 0, 10, 10), NULL);
    CHECK(CGPathContainsPoint(path, NULL, CGPointMake(0.1, 0.1), false), "no corners: a plain rectangle");
    CGPathRelease(path);

    // radii too large for the sides are scaled down to fit
    CGSize large[4] = {{100, 100}, {100, 100}, {100, 100}, {100, 100}};
    path = CGPathCreateMutable();
    CGPathAddUnevenCornersRoundedRect(path, NULL, CGRectMake(0, 0, 10, 10), large);
    CHECK(CGRectEqualToRect(CGPathGetBoundingBox(path), CGRectMake(0, 0, 10, 10)), "scaled radii stay in the rectangle");
    CHECK(CGPathContainsPoint(path, NULL, CGPointMake(5, 5), false), "scaled radii: the middle is inside");
    CHECK(!CGPathContainsPoint(path, NULL, CGPointMake(0.5, 0.5), false), "scaled radii: corners are round");
    CGPathRelease(path);

    CGPathAddUnevenCornersRoundedRect(NULL, NULL, CGRectMake(0, 0, 1, 1), corners);
}

static void testRegionEnumerator(void) {
    CGRect rect = CGRectMake(1, 2, 3, 4);
    CGSRegionRef region = NULL;
    CHECK(CGSNewRegionWithRect(&rect, &region) == kCGErrorSuccess && region != NULL, "a region is made");
    CGSRegionEnumeratorObj e = CGSRegionEnumerator(region);
    CHECK(e != NULL, "an enumerator is made");
    CGRect *next = CGSNextRect(e);
    CHECK(next != NULL && CGRectEqualToRect(*next, rect), "the region's rectangle");
    CHECK(CGSNextRect(e) == NULL, "then no more");
    CHECK(CGSNextRect(e) == NULL, "and still no more");
    CHECK(CGSReleaseRegionEnumerator(e) == kCGErrorSuccess, "the enumerator is released");
    CHECK(CGSReleaseRegion(region) == kCGErrorSuccess, "the region is released");

    CGRect empty = CGRectZero;
    CGSNewRegionWithRect(&empty, &region);
    e = CGSRegionEnumerator(region);
    CHECK(e != NULL && CGSNextRect(e) == NULL, "an empty region has no rectangles");
    CGSReleaseRegionEnumerator(e);
    CGSReleaseRegion(region);

    CHECK(CGSRegionEnumerator(NULL) == NULL, "NULL region: no enumerator");
    CHECK(CGSNextRect(NULL) == NULL, "NULL enumerator: no rectangle");
    CHECK(CGSReleaseRegionEnumerator(NULL) == kCGErrorSuccess, "releasing NULL succeeds");
    CHECK(CGSReleaseRegion(NULL) == kCGErrorSuccess, "releasing a NULL region succeeds");
    CHECK(CGSNewRegionWithRect(NULL, &region) == kCGErrorIllegalArgument, "no region without a rectangle");
}

static void testDataProviderCopy(void) {
    unsigned char bytes[4] = {1, 2, 3, 4};
    CGDataProviderRef provider = CGDataProviderCreateWithCopyOfData(bytes, sizeof(bytes));
    bytes[0] = 99;
    CFDataRef data = CGDataProviderCopyData(provider);
    CHECK(data != NULL && CFDataGetLength(data) == 4 && CFDataGetBytePtr(data)[0] == 1,
          "the provider has a copy made when it was created");
    if (data != NULL)
        CFRelease(data);
    CGDataProviderRelease(provider);

    CHECK(CGDataProviderCreateWithCopyOfData(NULL, 4) == NULL, "no provider of NULL bytes");
    provider = CGDataProviderCreateWithCopyOfData(NULL, 0);
    CHECK(provider != NULL, "a provider of no bytes");
    data = CGDataProviderCopyData(provider);
    CHECK(data == NULL || CFDataGetLength(data) == 0, "which has no bytes");
    if (data != NULL)
        CFRelease(data);
    CGDataProviderRelease(provider);
}

static void testCachingFlags(void) {
    Bitmap b;
    bitmapInit(&b);
    CGImageRef image = CGBitmapContextCreateImage(b.context);
    CHECK(CGImageGetCachingFlags(image) == 0, "no caching flags at first");
    CGImageSetCachingFlags(image, kCGImageCachingTransient);
    CHECK(CGImageGetCachingFlags(image) == kCGImageCachingTransient, "the caching flags are kept");
    CHECK(CGImageGetCachingFlags(NULL) == 0, "NULL image: no flags");
    CGImageSetCachingFlags(NULL, kCGImageCachingTemporary);
    CGImageRelease(image);
    bitmapFree(&b);
}

static unsigned char gradientMiddleRed(CFDictionaryRef options) {
    Bitmap b;
    bitmapInit(&b);
    // transparent red to opaque blue
    CGFloat components[8] = {1, 0, 0, 0, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponentsAndOptions(b.space, components, NULL, 2, options);
    CGContextDrawLinearGradient(b.context, gradient, CGPointMake(0, 0), CGPointMake(SIZE, 0), 0);
    unsigned char red = pixelAt(&b, SIZE / 2, SIZE / 2)[0];
    CGGradientRelease(gradient);
    bitmapFree(&b);
    return red;
}

static void testGradientOptions(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[8] = {1, 0, 0, 0, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponentsAndOptions(space, components, NULL, 2, NULL);
    CHECK(gradient != NULL, "a gradient without options");
    CGGradientRelease(gradient);
    CHECK(CGGradientCreateWithColorComponentsAndOptions(NULL, components, NULL, 2, NULL) == NULL,
          "no gradient without a space");
    CGColorSpaceRelease(space);

    const void *keys[1] = {kCGGradientInterpolatesPremultiplied};
    const void *yes[1] = {kCFBooleanTrue};
    CFDictionaryRef premultiplied = CFDictionaryCreate(NULL, keys, yes, 1, &kCFTypeDictionaryKeyCallBacks,
                                                       &kCFTypeDictionaryValueCallBacks);
    // Straight interpolation mixes in the red of the transparent stop; the
    // premultiplied one does not.
    CHECK(gradientMiddleRed(NULL) > 40, "straight interpolation tints with the transparent stop");
    CHECK(gradientMiddleRed(premultiplied) < 15, "premultiplied interpolation does not");
    CFRelease(premultiplied);
}

static void testColorSpaces(void) {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    CGColorSpaceRef gray = CGColorSpaceCreateDeviceGray();
    CFDataRef icc = CGColorSpaceCopyICCData(srgb);
    CGColorSpaceRef fromICC = icc != NULL ? CGColorSpaceCreateWithICCData(icc) : NULL;

    CHECK(CGColorSpaceEqualToColorSpace(srgb, srgb), "a space equals itself");
    CHECK(CGColorSpaceEqualToColorSpace(NULL, NULL), "NULL equals NULL");
    CHECK(!CGColorSpaceEqualToColorSpace(srgb, NULL), "a space does not equal NULL");
    CHECK(!CGColorSpaceEqualToColorSpace(NULL, srgb), "NULL does not equal a space");
    CHECK(!CGColorSpaceEqualToColorSpace(srgb, p3), "different profiles are different spaces");
    CHECK(!CGColorSpaceEqualToColorSpace(srgb, gray), "different models are different spaces");
    CHECK(fromICC != NULL && CGColorSpaceEqualToColorSpace(srgb, fromICC), "a space equals one made from its profile");

    CFStringRef description = CGColorSpaceCopyICCProfileDescription(srgb);
    CHECK(description != NULL && CFStringCompare(description, CFSTR("sRGB IEC61966-2.1"), 0) == kCFCompareEqualTo,
          "the sRGB profile's description");
    if (description != NULL)
        CFRelease(description);
    description = CGColorSpaceCopyICCProfileDescription(p3);
    CHECK(description != NULL && CFStringCompare(description, CFSTR("Display P3"), 0) == kCFCompareEqualTo,
          "the Display P3 profile's description");
    if (description != NULL)
        CFRelease(description);
    description = fromICC != NULL ? CGColorSpaceCopyICCProfileDescription(fromICC) : NULL;
    CHECK(description != NULL && CFStringCompare(description, CFSTR("sRGB IEC61966-2.1"), 0) == kCFCompareEqualTo,
          "the description of a space made from a profile");
    if (description != NULL)
        CFRelease(description);
    CHECK(CGColorSpaceCopyICCProfileDescription(NULL) == NULL, "NULL space: no description");

    if (icc != NULL)
        CFRelease(icc);
    CGColorSpaceRelease(fromICC);
    CGColorSpaceRelease(gray);
    CGColorSpaceRelease(p3);
    CGColorSpaceRelease(srgb);
}

static void testColorTransform(void) {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    CGColorTransformRef toSRGB = CGColorTransformCreate(srgb, NULL);
    CGColorTransformRef toP3 = CGColorTransformCreate(p3, NULL);
    CHECK(toSRGB != NULL && CFGetTypeID(toSRGB) == CGColorTransformGetTypeID(), "a transform is a CF object");

    CGFloat in[3] = {0.2, 0.4, 0.6};
    CGFloat out[3] = {-1, -1, -1};
    CHECK(CGColorTransformConvertColorComponents(toSRGB, srgb, kCGRenderingIntentDefault, in, out),
          "a conversion to the same space succeeds");
    CHECK(near(out[0], 0.2, 1e-3) && near(out[1], 0.4, 1e-3) && near(out[2], 0.6, 1e-3),
          "and keeps the components");

    CGFloat red[3] = {1, 0, 0};
    CHECK(CGColorTransformConvertColorComponents(toP3, srgb, kCGRenderingIntentDefault, red, out),
          "sRGB to Display P3");
    CHECK(out[0] > 0.85 && out[0] < 0.95 && out[1] > 0.1, "sRGB red is inside the Display P3 gamut");

    CHECK(!CGColorTransformConvertColorComponents(NULL, srgb, kCGRenderingIntentDefault, in, out), "NULL transform");
    CHECK(!CGColorTransformConvertColorComponents(toP3, NULL, kCGRenderingIntentDefault, in, out), "NULL source");
    CHECK(!CGColorTransformConvertColorComponents(toP3, srgb, kCGRenderingIntentDefault, NULL, out), "NULL input");
    CHECK(!CGColorTransformConvertColorComponents(toP3, srgb, kCGRenderingIntentDefault, in, NULL), "NULL output");
    CHECK(CGColorTransformCreate(NULL, NULL) == NULL, "no transform without a destination");

    CFRelease(toP3);
    CFRelease(toSRGB);
    CGColorSpaceRelease(p3);
    CGColorSpaceRelease(srgb);
}

static void testImagePattern(void) {
    // a 2 by 2 image: red, blue / blue, red
    unsigned char tile[16] = {255, 0, 0, 255, 0, 0, 255, 255, 0, 0, 255, 255, 255, 0, 0, 255};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef provider = CGDataProviderCreateWithCopyOfData(tile, sizeof(tile));
    CGImageRef image = CGImageCreate(2, 2, 8, 32, 8, space, kCGImageAlphaPremultipliedLast, provider, NULL,
                                     false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGPatternRef pattern = CGPatternCreateWithImage2(image, CGAffineTransformIdentity, kCGPatternTilingConstantSpacing);
    CHECK(pattern != NULL, "an image pattern is made");
    CGImageRelease(image);

    Bitmap b;
    bitmapInit(&b);
    CGColorSpaceRef patternSpace = CGColorSpaceCreatePattern(NULL);
    CGContextSetFillColorSpace(b.context, patternSpace);
    CGFloat alpha = 1;
    CGContextSetFillPattern(b.context, pattern, &alpha);
    CGContextFillRect(b.context, CGRectMake(0, 0, SIZE, SIZE));
    const unsigned char *p00 = pixelAt(&b, 4, 4), *p10 = pixelAt(&b, 5, 4);
    const unsigned char *p20 = pixelAt(&b, 6, 4), *p02 = pixelAt(&b, 4, 6), *p11 = pixelAt(&b, 5, 5);
    CHECK(p00[3] == 255, "the pattern is drawn opaque");
    CHECK(p00[0] != p10[0], "neighbours in the tile differ");
    CHECK(p00[0] == p20[0] && p00[0] == p02[0] && p00[0] == p11[0], "the tile repeats every image size");
    CGColorSpaceRelease(patternSpace);
    CGPatternRelease(pattern);
    bitmapFree(&b);

    CHECK(CGPatternCreateWithImage2(NULL, CGAffineTransformIdentity, kCGPatternTilingConstantSpacing) == NULL,
          "no pattern without an image");
    CGColorSpaceRelease(space);
}

int main(void) {
    testContextState();
    testDrawPathDirect();
    testConicGradient();
    testUnevenCorners();
    testRegionEnumerator();
    testDataProviderCopy();
    testCachingFlags();
    testGradientOptions();
    testColorSpaces();
    testColorTransform();
    testImagePattern();
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
