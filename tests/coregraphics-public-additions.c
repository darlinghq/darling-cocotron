// Copyright (C) 2026 Lubos Dolezel
//
// CGRectStandardize, CGImageGetTypeID/CGColorGetTypeID,
// CGDataProviderCreateWithFilename and CGContextBeginTransparencyLayerWithRect.
// The edge cases (CGRectNull and CGRectInfinite unchanged, a size of -0 becoming
// +0, a missing file giving NULL) were observed on macOS 26.7.3.
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

int main(void) {
    CGRect r = CGRectStandardize(CGRectMake(10, 20, -5, -6));
    CHECK(r.origin.x == 5 && r.origin.y == 14 && r.size.width == 5 && r.size.height == 6, "negative size");
    r = CGRectStandardize(CGRectMake(10, 20, 5, 6));
    CHECK(r.origin.x == 10 && r.origin.y == 20 && r.size.width == 5 && r.size.height == 6, "positive size unchanged");
    r = CGRectStandardize(CGRectNull);
    CHECK(CGRectIsNull(r), "CGRectNull unchanged");
    r = CGRectStandardize(CGRectInfinite);
    CHECK(CGRectEqualToRect(r, CGRectInfinite), "CGRectInfinite unchanged");
    r = CGRectStandardize(CGRectMake(1, 2, -0.0, -0.0));
    CHECK(r.origin.x == 1 && r.origin.y == 2 && !signbit(r.size.width) && !signbit(r.size.height), "-0 size becomes +0");

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 1, 1, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGColorRef color = CGColorCreateGenericRGB(0, 0, 0, 1);
    CHECK(CFGetTypeID(image) == CGImageGetTypeID(), "CGImage type ID");
    CHECK(CFGetTypeID(color) == CGColorGetTypeID(), "CGColor type ID");
    CHECK(CGImageGetTypeID() != CGColorGetTypeID(), "distinct type IDs");

    CGContextBeginTransparencyLayerWithRect(context, CGRectMake(0, 0, 1, 1), NULL);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 1, 1));
    CGContextEndTransparencyLayer(context);
    const unsigned char *pixel = CGBitmapContextGetData(context);
    CHECK(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0 && pixel[3] == 255, "layer contents drawn");

    CHECK(CGDataProviderCreateWithFilename("/nonexistent/provider-file") == NULL, "missing file gives NULL");
    CHECK(CGDataProviderCreateWithFilename(NULL) == NULL, "NULL name gives NULL");
    CGDataProviderRef provider = CGDataProviderCreateWithFilename("/etc/hosts");
    CHECK(provider != NULL, "readable file gives a provider");
    if (provider != NULL) {
        CFDataRef data = CGDataProviderCopyData(provider);
        CHECK(data != NULL && CFDataGetLength(data) > 0, "provider data");
        if (data != NULL)
            CFRelease(data);
        CGDataProviderRelease(provider);
    }

    if (failures == 0)
        printf("PASS: public CoreGraphics additions\n");
    return failures ? 1 : 0;
}
