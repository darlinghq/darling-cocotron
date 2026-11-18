// Copyright (C) 2026 Lubos Dolezel
//
// NSBitmapImageRep colour-space API: -colorSpace of reps made from CGImages and from colour space names,
// -bitmapImageRepByConvertingToColorSpace:renderingIntent: (pixels are converted by CoreGraphics) and
// -bitmapImageRepByRetaggingWithColorSpace: (pixels are kept), plus the NSColorSpace accessors they rely on.
// Expected values come from black-box runs on macOS 26.7.3 x86_64 (tier 2): sRGB (200,100,50) is
// (187,105,62) in Display P3 and the other way round; the same colour in a Generic Gray bitmap is 111; rep
// color-space names after conversion are the calibrated ones; converting to the space a rep already has returns
// the rep itself; retagging to a space with another number of components gives nil. Tolerance 3 covers the
// quantisation of the ICC-based spaces. Also passes on macOS. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static BOOL near(int a, int b) { return abs(a - b) <= 3; }

static BOOL pixelNear(NSBitmapImageRep *rep, int r, int g, int b) {
    unsigned char *p = [rep bitmapData];
    return near(p[0], r) && near(p[1], g) && near(p[2], b);
}

static void releaseBytes(void *info, const void *data, size_t size) { free(info); }

// A 1x1 RGBA image whose four bytes are used as they are in the given space.
static CGImageRef newImage(CFStringRef spaceName, unsigned char r, unsigned char g, unsigned char b) {
    unsigned char *bytes = malloc(4);
    bytes[0] = r; bytes[1] = g; bytes[2] = b; bytes[3] = 255;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(spaceName);
    CGDataProviderRef provider = CGDataProviderCreateWithData(bytes, bytes, 4, releaseBytes);
    CGImageRef image = CGImageCreate(1, 1, 8, 32, 4, space, kCGImageAlphaPremultipliedLast, provider, NULL, NO,
                                     kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(space);
    return image;
}

static NSBitmapImageRep *newDeviceRep(int samples, BOOL alpha, NSString *name, int r, int g, int b, int a) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                     pixelsWide: 1
                                                                     pixelsHigh: 1
                                                                  bitsPerSample: 8
                                                                samplesPerPixel: samples
                                                                       hasAlpha: alpha
                                                                       isPlanar: NO
                                                                 colorSpaceName: name
                                                                    bytesPerRow: 0
                                                                   bitsPerPixel: 0] autorelease];
    unsigned char *p = [rep bitmapData];
    p[0] = r;
    if (samples > 1) { p[1] = g; p[2] = b; }
    if (alpha) p[3] = a;
    return rep;
}

static BOOL spaceIs(NSColorSpace *space, NSColorSpace *expected) {
    return space != nil && [space isEqual: expected];
}

int main(void) {
    @autoreleasepool {
        // colorSpace of reps made from CGImages
        CGImageRef srgbImage = newImage(kCGColorSpaceSRGB, 200, 100, 50);
        CGImageRef p3Image = newImage(kCGColorSpaceDisplayP3, 187, 105, 62);
        NSBitmapImageRep *srgb = [[[NSBitmapImageRep alloc] initWithCGImage: srgbImage] autorelease];
        NSBitmapImageRep *p3 = [[[NSBitmapImageRep alloc] initWithCGImage: p3Image] autorelease];
        CHECK(spaceIs([srgb colorSpace], [NSColorSpace sRGBColorSpace]), "sRGB image: colorSpace is not sRGB");
        CHECK(spaceIs([p3 colorSpace], [NSColorSpace displayP3ColorSpace]), "P3 image: colorSpace is not Display P3");
        CHECK(![[srgb colorSpace] isEqual: [p3 colorSpace]], "sRGB and P3 reps have equal spaces");
        CHECK([[srgb colorSpaceName] isEqualToString: NSCalibratedRGBColorSpace], "sRGB image: name %s",
              [[srgb colorSpaceName] UTF8String]);
        CHECK([[p3 colorSpaceName] isEqualToString: NSCalibratedRGBColorSpace], "P3 image: name");
        CHECK(pixelNear(srgb, 200, 100, 50), "sRGB image bytes changed");
        CHECK(pixelNear(p3, 187, 105, 62), "P3 image bytes changed");

        // colorSpace of reps made from colour space names
        NSBitmapImageRep *dev = newDeviceRep(4, YES, NSDeviceRGBColorSpace, 200, 100, 50, 255);
        NSBitmapImageRep *cal = newDeviceRep(4, YES, NSCalibratedRGBColorSpace, 200, 100, 50, 255);
        NSBitmapImageRep *gray = newDeviceRep(1, NO, NSDeviceWhiteColorSpace, 128, 0, 0, 0);
        NSBitmapImageRep *calGray = newDeviceRep(1, NO, NSCalibratedWhiteColorSpace, 128, 0, 0, 0);
        NSBitmapImageRep *cmyk = newDeviceRep(4, NO, NSDeviceCMYKColorSpace, 0, 0, 0, 0);
        CHECK(spaceIs([dev colorSpace], [NSColorSpace deviceRGBColorSpace]), "device RGB rep: colorSpace");
        CHECK(spaceIs([cal colorSpace], [NSColorSpace genericRGBColorSpace]), "calibrated RGB rep: colorSpace");
        CHECK(spaceIs([gray colorSpace], [NSColorSpace deviceGrayColorSpace]), "device white rep: colorSpace");
        CHECK(spaceIs([calGray colorSpace], [NSColorSpace genericGrayColorSpace]), "calibrated white rep: colorSpace");
        CHECK(spaceIs([cmyk colorSpace], [NSColorSpace deviceCMYKColorSpace]), "device CMYK rep: colorSpace");
        CHECK([[dev colorSpace] colorSpaceModel] == NSColorSpaceModelRGB, "device RGB model");
        CHECK([[dev colorSpace] numberOfColorComponents] == 3, "device RGB components");
        CHECK([[gray colorSpace] colorSpaceModel] == NSColorSpaceModelGray, "gray model");
        CHECK([[gray colorSpace] numberOfColorComponents] == 1, "gray components");
        CHECK([[cmyk colorSpace] colorSpaceModel] == NSColorSpaceModelCMYK, "CMYK model");
        CHECK([[cmyk colorSpace] numberOfColorComponents] == 4, "CMYK components");

        // -CGImageForProposedRect:context:hints: of an NSImageRep gives the image, in the rep's space
        CGImageRef proposed = [(NSImageRep *) p3 CGImageForProposedRect: NULL context: nil hints: nil];
        CHECK(proposed != NULL && CGImageGetWidth(proposed) == 1 &&
                      CFEqual(CGImageGetColorSpace(proposed), [[NSColorSpace displayP3ColorSpace] CGColorSpace]),
              "CGImageForProposedRect: of a P3 bitmap rep");

        // NSColorSpace equality and hash follow the CoreGraphics space
        CGColorSpaceRef raw = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        NSColorSpace *wrapped = [[[NSColorSpace alloc] initWithCGColorSpace: raw] autorelease];
        CGColorSpaceRelease(raw);
        CHECK([wrapped isEqual: [NSColorSpace sRGBColorSpace]], "equal spaces compare unequal");
        CHECK([wrapped hash] == [[NSColorSpace sRGBColorSpace] hash], "equal spaces hash differently");
        CHECK(![wrapped isEqual: [NSColorSpace displayP3ColorSpace]], "sRGB equals P3");
        CHECK(![wrapped isEqual: @"sRGB"], "space equals a string");

        // ICC profile data
        NSData *icc = [[NSColorSpace sRGBColorSpace] ICCProfileData];
        CHECK([icc length] > 128, "sRGB ICCProfileData is empty");
        NSColorSpace *fromICC = icc != nil ? [[[NSColorSpace alloc] initWithICCProfileData: icc] autorelease] : nil;
        CHECK(fromICC != nil && [fromICC colorSpaceModel] == NSColorSpaceModelRGB, "initWithICCProfileData: nil");
        CHECK([[NSColorSpace deviceRGBColorSpace] ICCProfileData] == nil, "device RGB has ICC data");

        // conversion
        NSBitmapImageRep *toP3 = [srgb bitmapImageRepByConvertingToColorSpace: [NSColorSpace displayP3ColorSpace]
                                                              renderingIntent: NSColorRenderingIntentDefault];
        CHECK(toP3 != nil && toP3 != srgb, "sRGB to P3: no new rep");
        CHECK(spaceIs([toP3 colorSpace], [NSColorSpace displayP3ColorSpace]), "sRGB to P3: colorSpace");
        CHECK([[toP3 colorSpaceName] isEqualToString: NSCalibratedRGBColorSpace], "sRGB to P3: name");
        CHECK(pixelNear(toP3, 187, 105, 62), "sRGB to P3: bytes %d %d %d", [toP3 bitmapData][0], [toP3 bitmapData][1],
              [toP3 bitmapData][2]);
        CHECK([toP3 hasAlpha] && [toP3 samplesPerPixel] == 4 && [toP3 bitsPerPixel] == 32, "sRGB to P3: layout");
        CHECK([toP3 bitmapData][3] == 255, "sRGB to P3: alpha");
        CHECK(pixelNear(srgb, 200, 100, 50) && spaceIs([srgb colorSpace], [NSColorSpace sRGBColorSpace]),
              "conversion changed the source");
        CGImageRef toP3Image = [toP3 CGImage];
        CHECK(toP3Image != NULL &&
                      CFEqual(CGImageGetColorSpace(toP3Image), [[NSColorSpace displayP3ColorSpace] CGColorSpace]),
              "CGImage of the converted rep is not in P3");

        NSBitmapImageRep *toSRGB = [p3 bitmapImageRepByConvertingToColorSpace: [NSColorSpace sRGBColorSpace]
                                                              renderingIntent: NSColorRenderingIntentDefault];
        CHECK(toSRGB != nil && pixelNear(toSRGB, 200, 100, 50), "P3 to sRGB: bytes");
        CHECK(spaceIs([toSRGB colorSpace], [NSColorSpace sRGBColorSpace]), "P3 to sRGB: colorSpace");

        NSBitmapImageRep *same = [srgb bitmapImageRepByConvertingToColorSpace: [NSColorSpace sRGBColorSpace]
                                                              renderingIntent: NSColorRenderingIntentDefault];
        CHECK(same == srgb, "conversion to the current space does not return the rep");

        NSBitmapImageRep *devToSRGB = [dev bitmapImageRepByConvertingToColorSpace: [NSColorSpace sRGBColorSpace]
                                                                  renderingIntent: NSColorRenderingIntentDefault];
        CHECK(devToSRGB != nil && pixelNear(devToSRGB, 200, 100, 50), "device RGB to sRGB: bytes");
        CHECK(devToSRGB != nil && [[devToSRGB colorSpaceName] isEqualToString: NSCalibratedRGBColorSpace],
              "device RGB to sRGB: name");

        NSBitmapImageRep *noAlpha = newDeviceRep(3, NO, NSDeviceRGBColorSpace, 200, 100, 50, 0);
        NSBitmapImageRep *noAlphaP3 = [noAlpha bitmapImageRepByConvertingToColorSpace: [NSColorSpace displayP3ColorSpace]
                                                                      renderingIntent: NSColorRenderingIntentDefault];
        CHECK(noAlphaP3 != nil && ![noAlphaP3 hasAlpha] && [noAlphaP3 samplesPerPixel] == 3 &&
                      [noAlphaP3 bitsPerPixel] == 32,
              "opaque RGB to P3: layout");
        CHECK(noAlphaP3 != nil && pixelNear(noAlphaP3, 187, 105, 62), "opaque RGB to P3: bytes");

        NSBitmapImageRep *toGray = [srgb bitmapImageRepByConvertingToColorSpace: [NSColorSpace genericGrayColorSpace]
                                                                renderingIntent: NSColorRenderingIntentDefault];
        CHECK(toGray != nil, "sRGB to gray: nil");
        if (toGray != nil) {
            CHECK([toGray samplesPerPixel] == 1 && [toGray bitsPerPixel] == 8 && ![toGray hasAlpha],
                  "sRGB to gray: layout %d spp %d bpp alpha %d", [toGray samplesPerPixel], [toGray bitsPerPixel],
                  [toGray hasAlpha]);
            CHECK([[toGray colorSpaceName] isEqualToString: NSCalibratedWhiteColorSpace], "sRGB to gray: name");
            CHECK(near([toGray bitmapData][0], 111), "sRGB to gray: sample %d", [toGray bitmapData][0]);
        }

        CHECK([(id) srgb bitmapImageRepByConvertingToColorSpace: nil renderingIntent: NSColorRenderingIntentDefault] == nil,
              "conversion to nil space");

        // retagging
        NSBitmapImageRep *tagged = [srgb bitmapImageRepByRetaggingWithColorSpace: [NSColorSpace displayP3ColorSpace]];
        CHECK(tagged != nil && tagged != srgb, "retag: no new rep");
        CHECK(spaceIs([tagged colorSpace], [NSColorSpace displayP3ColorSpace]), "retag: colorSpace");
        CHECK(pixelNear(tagged, 200, 100, 50) && [tagged bitmapData][3] == 255, "retag changed the samples");
        CHECK([tagged pixelsWide] == 1 && [tagged pixelsHigh] == 1 && [tagged hasAlpha] &&
                      [tagged bitsPerPixel] == [srgb bitsPerPixel] && [tagged bytesPerRow] == [srgb bytesPerRow],
              "retag changed the layout");
        CHECK(spaceIs([srgb colorSpace], [NSColorSpace sRGBColorSpace]), "retag changed the source");
        CGImageRef taggedImage = [tagged CGImage];
        CHECK(taggedImage != NULL &&
                      CFEqual(CGImageGetColorSpace(taggedImage), [[NSColorSpace displayP3ColorSpace] CGColorSpace]),
              "CGImage of the retagged rep is not in P3");
        NSBitmapImageRep *devTagged = [dev bitmapImageRepByRetaggingWithColorSpace: [NSColorSpace sRGBColorSpace]];
        CHECK(devTagged != nil && spaceIs([devTagged colorSpace], [NSColorSpace sRGBColorSpace]) &&
                      [[devTagged colorSpaceName] isEqualToString: NSCalibratedRGBColorSpace],
              "retag of a device RGB rep");
        CHECK([srgb bitmapImageRepByRetaggingWithColorSpace: [NSColorSpace genericGrayColorSpace]] == nil,
              "retag RGB to gray");
        CHECK([dev bitmapImageRepByRetaggingWithColorSpace: [NSColorSpace deviceCMYKColorSpace]] == nil,
              "retag RGB to CMYK");
        CHECK([gray bitmapImageRepByRetaggingWithColorSpace: [NSColorSpace sRGBColorSpace]] == nil, "retag gray to RGB");
        CHECK([(id) srgb bitmapImageRepByRetaggingWithColorSpace: nil] == nil, "retag to nil space");

        CGImageRelease(srgbImage);
        CGImageRelease(p3Image);
    }
    if (failures == 0)
        printf("PASS\n");
    else
        printf("FAIL: %d\n", failures);
    return failures != 0;
}
