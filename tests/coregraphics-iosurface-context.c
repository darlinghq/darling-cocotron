// Copyright (C) 2026 Lubos Dolezel
//
// IOSurface contexts (CGIOSurfaceContext.h): a bitmap context that draws
// straight into an IOSurface's memory. Expected values are those of Darling's
// implementation, not observations of macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <CoreGraphics/CGIOSurfaceContext.h>
#include <IOSurface/IOSurface.h>
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

static void setInt(CFMutableDictionaryRef d, CFStringRef key, int value) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &value);
    CFDictionarySetValue(d, key, number);
    CFRelease(number);
}

static IOSurfaceRef makeSurface(int width, int height) {
    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                                  &kCFTypeDictionaryValueCallBacks);
    setInt(properties, kIOSurfaceWidth, width);
    setInt(properties, kIOSurfaceHeight, height);
    setInt(properties, kIOSurfaceBytesPerElement, 4);
    setInt(properties, kIOSurfacePixelFormat, 'BGRA');
    IOSurfaceRef surface = IOSurfaceCreate(properties);
    CFRelease(properties);
    return surface;
}

int main(void) {
    IOSurfaceRef surface = makeSurface(8, 6);
    CHECK(surface != NULL, "a surface is made");
    if (surface == NULL)
        return 1;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo info = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;

    CGContextRef c = CGIOSurfaceContextCreate(surface, 8, 6, 8, 32, space, info);
    CHECK(c != NULL, "a context is made for the surface");
    if (c == NULL)
        return 1;
    CHECK(CGContextGetType(c) == kCGContextTypeIOSurface, "it is an IOSurface context");
    CHECK(CGIOSurfaceContextGetSurface(c) == surface, "it draws into the surface");
    CHECK(CGIOSurfaceContextGetColorSpace(c) != NULL &&
          CGColorSpaceGetModel(CGIOSurfaceContextGetColorSpace(c)) == kCGColorSpaceModelRGB, "its colour space");
    CHECK(CGIOSurfaceContextGetBitmapInfo(c) == info, "its bitmap info");
    CHECK(CGBitmapContextGetWidth(c) == 8 && CGBitmapContextGetHeight(c) == 6, "its size");
    CGColorSpaceRef device = CGContextCopyDeviceColorSpace(c);
    CHECK(device != NULL && CGColorSpaceGetModel(device) == kCGColorSpaceModelRGB, "its device space");
    CGColorSpaceRelease(device);
    CGIOSurfaceContextSetDisplayMask(c, 1);

    // drawing lands in the surface's memory: BGRA little endian, so blue first
    CGContextSetRGBFillColor(c, 0, 0, 1, 1);
    CGContextFillRect(c, CGRectMake(0, 0, 8, 6));
    const unsigned char *bytes = IOSurfaceGetBaseAddress(surface);
    CHECK(bytes[0] == 255 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 255, "the surface holds the drawing");

    CGImageRef image = CGIOSurfaceContextCreateImage(c);
    CGImageRef reference = CGIOSurfaceContextCreateImageReference(c);
    CHECK(image != NULL && CGImageGetWidth(image) == 8 && CGImageGetHeight(image) == 6, "an image of the context");
    CHECK(reference != NULL && CGImageGetWidth(reference) == 8, "an image reference of the context");
    CGImageRelease(reference);
    CGImageRelease(image);
    CGContextRelease(c);

    CHECK(CGIOSurfaceContextCreate(NULL, 8, 6, 8, 32, space, info) == NULL, "no context without a surface");
    CHECK(CGIOSurfaceContextCreate(surface, 8, 6, 8, 32, NULL, info) == NULL, "no context without a space");
    CHECK(CGIOSurfaceContextCreate(surface, 9, 6, 8, 32, space, info) == NULL, "no context wider than the surface");
    CHECK(CGIOSurfaceContextCreate(surface, 8, 7, 8, 32, space, info) == NULL, "no context taller than the surface");
    CHECK(CGIOSurfaceContextCreate(surface, 0, 6, 8, 32, space, info) == NULL, "no empty context");

    // a plain bitmap context is not an IOSurface context
    CGContextRef bitmap = CGBitmapContextCreate(NULL, 2, 2, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CHECK(CGIOSurfaceContextGetSurface(bitmap) == NULL, "a bitmap context has no surface");
    CHECK(CGIOSurfaceContextGetColorSpace(bitmap) == NULL, "nor an IOSurface colour space");
    CHECK(CGIOSurfaceContextGetBitmapInfo(bitmap) == 0, "nor IOSurface bitmap info");
    CHECK(CGIOSurfaceContextCreateImage(bitmap) == NULL, "nor an IOSurface image");
    CGIOSurfaceContextSetDisplayMask(bitmap, 1);
    CGContextRelease(bitmap);
    CHECK(CGIOSurfaceContextGetSurface(NULL) == NULL, "NULL context: no surface");
    CHECK(CGIOSurfaceContextCreateImage(NULL) == NULL, "NULL context: no image");

    CGColorSpaceRelease(space);
    CFRelease(surface);
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
