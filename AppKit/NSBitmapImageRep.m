/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSBitmapImageRep-Private.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSView.h>
#import <Onyx2D/O2ImageDestination.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>

NSBitmapImageRepPropertyKey NSImageCompressionFactor =
        @"NSImageCompressionFactor";
NSBitmapImageRepPropertyKey NSImageCompressionMethod =
        @"NSImageCompressionMethod";
NSBitmapImageRepPropertyKey NSImageDitherTransparency =
        @"NSImageDitherTransparency";
NSBitmapImageRepPropertyKey NSImageInterlaced = @"NSImageInterlaced";
NSBitmapImageRepPropertyKey NSImageRGBColorTable = @"NSImageRGBColorTable";
NSBitmapImageRepPropertyKey NSImageFrameCount = @"NSImageFrameCount";
NSBitmapImageRepPropertyKey NSImageColorSyncProfileData =
        @"NSImageColorSyncProfileData";
NSBitmapImageRepPropertyKey NSImageFallbackBackgroundColor =
        @"NSImageFallbackBackgroundColor";
NSBitmapImageRepPropertyKey NSImageEXIFData = @"NSImageEXIFData";
NSBitmapImageRepPropertyKey NSImageProgressive = @"NSImageProgressive";
NSBitmapImageRepPropertyKey NSImageGamma = @"NSImageGamma";
NSBitmapImageRepPropertyKey NSImageLoopCount = @"NSImageLoopCount";
NSBitmapImageRepPropertyKey NSImageCurrentFrameDuration =
        @"NSImageCurrentFrameDuration";
NSBitmapImageRepPropertyKey NSImageCurrentFrame = @"NSImageCurrentFrame";

@implementation NSBitmapImageRep

+ (NSArray *) imageUnfilteredFileTypes {
    return [NSArray arrayWithObjects:
                            // Try to order them so the most used ones are at
                            // the top of the list
                            @"png", @"tiff", @"tif", @"jpg", @"jpeg", @"icns",
                            @"gif", @"bmp", @"PNG", @"TIFF", @"TIF", @"JPG",
                            @"JPEG", @"ICNS", @"jpe", @"JPE", @"GIF", @"BMP",
                            nil];
}

+ (NSArray *) imageRepsWithContentsOfFile: (NSString *) path {
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil)
        return nil;

    if ([self canInitWithData: data])
        return [self imageRepsWithData: data];

    return nil;
}

+ (void) getTIFFCompressionTypes: (const NSTIFFCompression **) types
                           count: (int *) count
{
    NSUnimplementedMethod();
}

+ (NSString *) localizedNameForTIFFCompressionType: (NSTIFFCompression) type {
    NSUnimplementedMethod();
    return nil;
}

+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array {
    return [self TIFFRepresentationOfImageRepsInArray: array
                                     usingCompression: NSTIFFCompressionNone
                                               factor: 0.0];
}

+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array
                                 usingCompression:
                                         (NSTIFFCompression) compression
                                           factor: (float) factor
{
    NSMutableData *result = [NSMutableData data];
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
            (CFMutableDataRef) result, (CFStringRef) @"public.tiff",
            [array count], NULL);

    for (NSBitmapImageRep *bitmap in array) {
        // The resolution carries the size in points, so reading the data back gives the same size
        NSSize size = [bitmap size];
        NSDictionary *properties = nil;
        if (size.width > 0 && size.height > 0)
            properties = [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithDouble: 72.0 * [bitmap pixelsWide] / size.width], (id) kCGImagePropertyDPIWidth,
                    [NSNumber numberWithDouble: 72.0 * [bitmap pixelsHigh] / size.height], (id) kCGImagePropertyDPIHeight, nil];
        CGImageDestinationAddImage(dest, [bitmap CGImage], (CFDictionaryRef) properties);
    }

    CGImageDestinationFinalize(dest);
    CFRelease(dest);

    return result;
}

+ (NSData *) representationOfImageRepsInArray: (NSArray *) array
                                    usingType: (NSBitmapImageFileType) type
                                   properties: (NSDictionary *) properties
{
    NSUnimplementedMethod();
    return nil;
}

+ (NSArray *) imageUnfilteredPasteboardTypes {
    return [NSArray arrayWithObjects: NSTIFFPboardType, nil];
}

+ (BOOL) canInitWithData: (NSData *) data {
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);
    if (imageSource == NULL)
        return NO;
    CFRelease(imageSource);
    return YES;
}

+ (NSArray *) imageRepsWithData: (NSData *) data {
    NSMutableArray *result = [NSMutableArray array];
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);

    if (imageSource == nil)
        return nil;

    size_t i, count = CGImageSourceGetCount(imageSource);

    for (i = 0; i < count; i++) {
        CGImageRef cgImage =
                CGImageSourceCreateImageAtIndex(imageSource, i, nil);

        if (cgImage == nil)
            break;

        CFDictionaryRef properties =
                CGImageSourceCopyPropertiesAtIndex(imageSource, i, nil);
        NSNumber *xres = properties ? [[(id) CFDictionaryGetValue(
                properties, kCGImagePropertyDPIWidth) copy] autorelease] : nil;
        NSNumber *yres = properties ? [[(id) CFDictionaryGetValue(
                properties, kCGImagePropertyDPIHeight) copy] autorelease] : nil;

        if (properties)
            CFRelease(properties);

        NSBitmapImageRep *imageRep = [[self alloc] initWithCGImage: cgImage];
        NSSize size = {CGImageGetWidth(cgImage), CGImageGetHeight(cgImage)};

        CGImageRelease(cgImage);

        if (xres != nil && [xres doubleValue] > 0)
            size.width *= 72.0 / [xres doubleValue];

        if (yres != nil && [yres doubleValue] > 0)
            size.height *= 72.0 / [yres doubleValue];

        [imageRep setSize: size];

        if (imageRep != nil)
            [result addObject: imageRep];

        [imageRep release];
    }

    CFRelease(imageSource);

    return result;
}

+ imageRepWithData: (NSData *) data {
    return [[[self alloc] initWithData: data] autorelease];
}

- initWithBitmapDataPlanes: (unsigned char **) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (NSString *) colorSpaceName
              bitmapFormat: (NSBitmapFormat) bitmapFormat
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel
{
    int i, numberOfPlanes = isPlanar ? samplesPerPixel : 1;

    // The documented failure result is nil; negative geometry and sizes
    // that do not fit the int accessors cannot describe a bitmap.
    if (width < 0 || height < 0 || bitsPerSample < 0 || samplesPerPixel < 0 ||
        bytesPerRow < 0 || bitsPerPixel < 0)
    {
        [self release];
        return nil;
    }

    _size = NSMakeSize(width, height);
    _colorSpaceName = [colorSpaceName copy];
    _bitsPerSample = bitsPerSample;
    _pixelsWide = width;
    _pixelsHigh = height;
    _hasAlpha = hasAlpha;

    _samplesPerPixel = samplesPerPixel;
    NS_EXTRA(NSBitmapImageRep, self)->_isPlanar = isPlanar;
    _bitmapFormat = bitmapFormat;

    int64_t pixelBits = (bitsPerPixel != 0)
                                ? bitsPerPixel
                                : (int64_t) bitsPerSample * samplesPerPixel;
    if (pixelBits > INT_MAX) {
        [self release];
        return nil;
    }
    _bitsPerPixel = (int) pixelBits;

    // A row of a planar image holds one sample per pixel: bytesPerRow is
    // the length of a scan line within one plane.
    int64_t rowBits = (int64_t)(NS_EXTRA(NSBitmapImageRep, self)->_isPlanar ? _bitsPerSample : _bitsPerPixel) *
                      _pixelsWide;
    int64_t minimumRowBytes = (rowBits + 7) / 8;

    if (bytesPerRow != 0) {
        if (bytesPerRow < minimumRowBytes) {
            [self release];
            return nil;
        }
        _bytesPerRow = bytesPerRow;
    } else {
        // QUIRK: with bytesPerRow 0, rows are padded to a multiple of 32
        // bytes (16 pixels of 1-bit planar data or 1 RGBA8 pixel give 32,
        // 17 RGBA8 pixels give 96). The documentation only says rows may be
        // padded. Evidence: black-box observation on macOS 27.0.1, arm64
        // and x86_64 (tier 2).
        // Test: appkit_image_decoding_malformed, "bytesPerRow 0" checks.
        int64_t rowBytes = (minimumRowBytes + 31) & ~(int64_t) 31;

        if (rowBytes > INT_MAX) {
            [self release];
            return nil;
        }
        _bytesPerRow = (int) rowBytes;
    }

    NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone = NO;
    if (planes == NULL)
        NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone = YES;
    else {
        int i;

        for (i = 0; i < numberOfPlanes; i++)
            if (planes[i] != NULL)
                break;

        if (i == numberOfPlanes)
            NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone = YES;
    }

    NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes = NSZoneCalloc(NULL, numberOfPlanes, sizeof(unsigned char *));
    if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes == NULL && numberOfPlanes > 0) {
        [self release];
        return nil;
    }
    if (!NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone) {
        for (i = 0; i < numberOfPlanes; i++)
            NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] = planes[i];
    } else {
        // A request too large to allocate still creates the rep; using its
        // pixels raises NSMallocException (see -_allocateOwnedPlanes).
        @try {
            [self _allocateOwnedPlanes];
        } @catch (NSException *exception) {
            if (![[exception name] isEqualToString: NSMallocException])
                @throw;
        }
    }

    return self;
}

- initWithBitmapDataPlanes: (unsigned char **) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (NSString *) colorSpaceName
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel
{
    return [self initWithBitmapDataPlanes: planes
                               pixelsWide: width
                               pixelsHigh: height
                            bitsPerSample: bitsPerSample
                          samplesPerPixel: samplesPerPixel
                                 hasAlpha: hasAlpha
                                 isPlanar: isPlanar
                           colorSpaceName: colorSpaceName
                             bitmapFormat: 0
                              bytesPerRow: bytesPerRow
                             bitsPerPixel: bitsPerPixel];
}

- initForIncrementalLoad {
    NSUnimplementedMethod();
    return nil;
}

- initWithFocusedViewRect: (NSRect) rect {
    CGContextRef graphicsPort = NSCurrentGraphicsPort();

    if (graphicsPort == NULL) {
        [self dealloc];
        return nil;
    }

    [self initWithData: (NSData *) CGContextCaptureBitmap(graphicsPort, rect)];

    return self;
}

- initWithData: (NSData *) data {
    CGImageSourceRef imageSource =
            CGImageSourceCreateWithData((CFDataRef) data, nil);

    if (imageSource == nil) {
        [self dealloc];
        return nil;
    }

    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil);

    if (cgImage == nil) {
        CFRelease(imageSource);
        [self dealloc];
        return nil;
    }

    CFDictionaryRef properties =
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil);
    NSNumber *xres = properties ?
            [[(id) CFDictionaryGetValue(properties, kCGImagePropertyDPIWidth)
                    copy] autorelease] : nil;
    NSNumber *yres = properties ?
            [[(id) CFDictionaryGetValue(properties, kCGImagePropertyDPIHeight)
                    copy] autorelease] : nil;

    if (properties)
        CFRelease(properties);
    CFRelease(imageSource);

    if (cgImage == nil) {
        [self dealloc];
        return nil;
    }

    if ((self = [self initWithCGImage: cgImage]) == nil)
        return nil;

    CGImageRelease(cgImage);

    if (xres != nil && [xres doubleValue] > 0)
        _size.width *= 72.0 / [xres doubleValue];

    if (yres != nil && [yres doubleValue] > 0)
        _size.height *= 72.0 / [yres doubleValue];

    return self;
}

- initWithContentsOfFile: (NSString *) path {
    NSData *data = [NSData dataWithContentsOfFile: path];

    if (data == nil) {
        [self dealloc];
        return nil;
    }

    return [self initWithData: data];
}

- (instancetype) initWithCoder:(NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];
        return nil;
    } else {
        NSInteger version = [coder versionForClassName: @"NSImageRep"];

        if (version >= 17) {
            NSData *data = [coder decodeDataObject];
            return [self initWithData: data];
        } else {
            [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];
            return nil;
        }
    }
}

// Allocates the zero-filled planes of a rep that owns its pixel data.
// When the planes cannot be allocated this raises NSMallocException, as the
// pixel accessors do on macOS for a rep too large to back.
- (void) _allocateOwnedPlanes {
    if (!NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone || NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes == NULL)
        return;

    int i, numberOfPlanes = [self numberOfPlanes];
    size_t planeLength = 0;
    BOOL overflow = _pixelsHigh != 0 &&
                    (size_t) _bytesPerRow > SIZE_MAX / (size_t) _pixelsHigh;

    if (!overflow)
        planeLength = (size_t) _bytesPerRow * (size_t) _pixelsHigh;
    if (planeLength == 0 && !overflow)
        return;

    for (i = 0; i < numberOfPlanes; i++) {
        if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] != NULL)
            continue;
        if (!overflow)
            NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] = NSZoneCalloc(NULL, planeLength, 1);
        if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] == NULL) {
            unsigned long long total =
                    overflow ? ULLONG_MAX
                             : (unsigned long long) planeLength * numberOfPlanes;
            [NSException raise: NSMallocException
                        format: @"NSBitmapImageRep: cannot allocate %llu bytes "
                                @"of pixel data",
                                total];
        }
    }
}

- (void) createBitmapIfNeeded {
    [self _allocateOwnedPlanes];

    if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes == NULL) {
        NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone = YES;
        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes = NSZoneCalloc(NULL, 1, sizeof(unsigned char *));
        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0] = NSZoneCalloc(NULL, _bytesPerRow * _pixelsHigh, 1);

        if (NS_EXTRA(NSBitmapImageRep, self)->_cgImage != NULL) {
            CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
            CGDataProviderRef provider = CGImageGetDataProvider(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
            // FIXME: inefficient but there is no API to get mutable bytes out
            // of an image or image source
            CFDataRef bitmapData = CGDataProviderCopyData(provider);
            const unsigned char *bytes = CFDataGetBytePtr(bitmapData);
            int i, length = _bytesPerRow * _pixelsHigh;

            // The planes use component order, with alpha first when
            // _bitmapFormat says so (see -CGBitmapInfo). Big-endian
            // premultiplied sources are already in that order.
            BOOL alphaFirst = (_bitmapFormat & NSAlphaFirstBitmapFormat) != 0;

            CGBitmapInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
            CGBitmapInfo byteOrder = bitmapInfo & kCGBitmapByteOrderMask;

            // The default byte order and the 32-bit big-endian one both mean
            // component order for 8-bit samples.
            size_t imageBitsPerPixel = CGImageGetBitsPerPixel(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);

            if (imageBitsPerPixel != 32) {
                // Images without a padding byte (24 bit RGB, 8 bit gray) already have the
                // layout of the planes
                for (i = 0; i < length; i++)
                    NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i] = bytes[i];
            } else if ((alphaInfo == kCGImageAlphaPremultipliedLast ||
                        alphaInfo == kCGImageAlphaPremultipliedFirst ||
                        alphaInfo == kCGImageAlphaNoneSkipLast ||
                        alphaInfo == kCGImageAlphaNoneSkipFirst) &&
                       (byteOrder == kCGBitmapByteOrderDefault ||
                        byteOrder == kCGBitmapByteOrder32Big)) {
                for (i = 0; i < length; i++)
                    NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i] = bytes[i];
            } else {
                for (i = 0; i < length; i += 4) {
                    unsigned char b = bytes[i + 0];
                    unsigned char g = bytes[i + 1];
                    unsigned char r = bytes[i + 2];
                    unsigned char a = bytes[i + 3];

                    if (alphaFirst) {
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 0] = a;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 1] = r;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 2] = g;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 3] = b;
                    } else {
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 0] = r;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 1] = g;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 2] = b;
                        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0][i + 3] = a;
                    }
                }
            }
            CFRelease(bitmapData);
        }
    }
}

- initWithCGImage: (CGImageRef) cgImage {
    NS_EXTRA(NSBitmapImageRep, self)->_cgImage = CGImageRetain(cgImage);
    _size.width = CGImageGetWidth(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    _size.height = CGImageGetHeight(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);

    // Only RGB and one component (gray) images are mapped to a color space name so far.
    _colorSpaceName = CGColorSpaceGetNumberOfComponents(colorSpace) == 1 ? NSDeviceWhiteColorSpace
                                                                         : NSDeviceRGBColorSpace;
    _bitsPerSample = CGImageGetBitsPerComponent(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    _pixelsWide = CGImageGetWidth(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    _pixelsHigh = CGImageGetHeight(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);

    switch (CGImageGetAlphaInfo(NS_EXTRA(NSBitmapImageRep, self)->_cgImage)) {
    case kCGImageAlphaPremultipliedLast:
    case kCGImageAlphaPremultipliedFirst:
    case kCGImageAlphaLast:
    case kCGImageAlphaFirst:
        _hasAlpha = YES;
        break;
    default:
        _hasAlpha = NO;
        break;
    }

    _samplesPerPixel = CGColorSpaceGetNumberOfComponents(colorSpace);
    if (_hasAlpha)
        _samplesPerPixel++;
    NS_EXTRA(NSBitmapImageRep, self)->_isPlanar = NO;
    _bitmapFormat = 0;
    if (CGImageGetBitmapInfo(NS_EXTRA(NSBitmapImageRep, self)->_cgImage) & kCGBitmapFloatComponents) {
        _bitmapFormat |= NSFloatingPointSamplesBitmapFormat;
    }
    switch (CGImageGetAlphaInfo(NS_EXTRA(NSBitmapImageRep, self)->_cgImage)) {
    case kCGImageAlphaNone:
        break;
    case kCGImageAlphaPremultipliedLast:
        break;
    case kCGImageAlphaPremultipliedFirst:
        _bitmapFormat |= NSAlphaFirstBitmapFormat;
        break;
    case kCGImageAlphaLast:
        _bitmapFormat |= NSAlphaNonpremultipliedBitmapFormat;
        break;
    case kCGImageAlphaFirst:
        _bitmapFormat |= NSAlphaFirstBitmapFormat;
        _bitmapFormat |= NSAlphaNonpremultipliedBitmapFormat;
        break;
    case kCGImageAlphaNoneSkipLast:
    case kCGImageAlphaNoneSkipFirst:
        break;
    case kCGImageAlphaOnly:
        break;
    }

    _bitsPerPixel = CGImageGetBitsPerPixel(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    _bytesPerRow = CGImageGetBytesPerRow(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone = NO;

    //   [self createBitmapIfNeeded];

    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSBitmapImageRep, self)) {
        if (NS_EXTRA(NSBitmapImageRep, self)->_freeWhenDone) {
            if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes != NULL) {
                int i, numberOfPlanes = [self numberOfPlanes];

                for (i = 0; i < numberOfPlanes; i++)
                    if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] != NULL)
                        NSZoneFree(NULL, NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i]);
            }
        }
        if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes != NULL) {
            NSZoneFree(NULL, NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes);
        }
        CGImageRelease(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);
    }
    NS_EXTRA_FREE(NSBitmapImageRep, self);
    [super dealloc];
}

- (int) incrementalLoadFromData: (NSData *) data complete: (BOOL) complete {
    NSUnimplementedMethod();
    return 0;
}

- (int) bitsPerPixel {
    return _bitsPerPixel;
}

- (int) samplesPerPixel {
    return _samplesPerPixel;
}

- (int) bytesPerRow {
    return _bytesPerRow;
}

- (BOOL) isPlanar {
    return NS_EXTRA(NSBitmapImageRep, self)->_isPlanar;
}

- (int) numberOfPlanes {
    return NS_EXTRA(NSBitmapImageRep, self)->_isPlanar ? _samplesPerPixel : 1;
}

- (int) bytesPerPlane {
    return _bytesPerPlane;
}

- (NSBitmapFormat) bitmapFormat {
    return _bitmapFormat;
}

- (unsigned char *) bitmapData {
    [self createBitmapIfNeeded];

    return NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0];
}

- (void) getBitmapDataPlanes: (unsigned char **) planes {
    [self createBitmapIfNeeded];

    int i, numberOfPlanes = [self numberOfPlanes];

    for (i = 0; i < numberOfPlanes; i++)
        planes[i] = NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i];

    for (; i < 5; i++)
        planes[i] = NULL;
}

// Reads or writes the integer samples of one pixel. The pixel array holds one value per sample, in
// plane order for planar data. Samples narrower than a byte are packed most significant bit first;
// 16 and 32 bit samples use the byte order of the host. Floating point samples are not supported.
- (void) _accessPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y store: (BOOL) store {
    NSAssert(x >= 0 && x < [self pixelsWide], @"x out of bounds");
    NSAssert(y >= 0 && y < [self pixelsHigh], @"y out of bounds");

    [self createBitmapIfNeeded];

    int bitsPerSample = [self bitsPerSample];

    if ((_bitmapFormat & NSFloatingPointSamplesBitmapFormat) ||
        !(bitsPerSample == 1 || bitsPerSample == 2 || bitsPerSample == 4 || bitsPerSample == 8 ||
          bitsPerSample == 16 || bitsPerSample == 32)) {
        NSUnimplementedMethod();
        return;
    }

    int i;

    for (i = 0; i < _samplesPerPixel; i++) {
        unsigned char *row;
        NSUInteger bitOffset;

        if (NS_EXTRA(NSBitmapImageRep, self)->_isPlanar) {
            row = NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[i] + _bytesPerRow * y;
            bitOffset = (NSUInteger) x * bitsPerSample;
        } else {
            row = NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0] + _bytesPerRow * y;
            bitOffset = (NSUInteger) x * _bitsPerPixel + (NSUInteger) i * bitsPerSample;
        }

        unsigned char *bits = row + bitOffset / 8;

        if (bitsPerSample < 8) {
            int shift = 8 - bitsPerSample - (int) (bitOffset % 8);
            unsigned char mask = ((1 << bitsPerSample) - 1) << shift;

            if (store)
                *bits = (*bits & ~mask) | ((pixel[i] << shift) & mask);
            else
                pixel[i] = (*bits & mask) >> shift;
        } else if (bitsPerSample == 8) {
            if (store)
                *bits = pixel[i];
            else
                pixel[i] = *bits;
        } else if (bitsPerSample == 16) {
            uint16_t value;

            if (store) {
                value = pixel[i];
                memcpy(bits, &value, sizeof(value));
            } else {
                memcpy(&value, bits, sizeof(value));
                pixel[i] = value;
            }
        } else {
            uint32_t value;

            if (store) {
                value = pixel[i];
                memcpy(bits, &value, sizeof(value));
            } else {
                memcpy(&value, bits, sizeof(value));
                pixel[i] = value;
            }
        }
    }
}

- (void) getPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y {
    [self _accessPixel: pixel atX: x y: y store: NO];
}

- (void) setPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y {
    [self _accessPixel: pixel atX: x y: y store: YES];
}

// The color of a pixel of an integer-sample bitmap: gray, RGB or CMYK samples, with an optional
// alpha sample before or after them; premultiplied color samples are divided by the alpha.
- (NSColor *) colorAtX: (NSInteger) x y: (NSInteger) y {
    if (x < 0 || y < 0 || x >= _pixelsWide || y >= _pixelsHigh)
        [NSException raise: NSRangeException
                    format: @"-[NSBitmapImageRep colorAtX:y:]: (%ld, %ld) is outside the %ld x %ld image", (long) x, (long) y,
                            (long) _pixelsWide, (long) _pixelsHigh];

    int samples = _samplesPerPixel;
    if (samples < 1 || samples > 8 || _bitsPerSample < 1 || _bitsPerSample > 32 ||
        (_bitmapFormat & NSFloatingPointSamplesBitmapFormat) != 0)
        return nil;

    NSUInteger pixel[8];
    [self getPixel: pixel atX: x y: y];

    BOOL alphaFirst = [self hasAlpha] && (_bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
    int colorCount = [self hasAlpha] ? samples - 1 : samples;
    int offset = alphaFirst ? 1 : 0;
    double maximum = _bitsPerSample >= 32 ? 4294967295.0 : (double) ((1ULL << _bitsPerSample) - 1);

    CGFloat alpha = 1.0;
    if ([self hasAlpha])
        alpha = pixel[alphaFirst ? 0 : samples - 1] / maximum;

    CGFloat c[4] = { 0, 0, 0, 0 };
    if (colorCount < 1 || colorCount > 4)
        return nil;
    for (int i = 0; i < colorCount; i++) {
        c[i] = pixel[offset + i] / maximum;
        if ([self hasAlpha] && (_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) == 0 && alpha > 0.0)
            c[i] = MIN(1.0, c[i] / alpha);
    }

    switch (colorCount) {
    case 1:
        return [NSColor colorWithCalibratedWhite: c[0] alpha: alpha];
    case 3:
        return [NSColor colorWithCalibratedRed: c[0] green: c[1] blue: c[2] alpha: alpha];
    case 4:
        return [NSColor colorWithDeviceCyan: c[0] magenta: c[1] yellow: c[2] black: c[3] alpha: alpha];
    default:
        return nil;
    }
}

- (void) setColor: (NSColor *) color atX: (NSInteger) x y: (NSInteger) y {
    // Convert the color to a compatible format
    color = [color colorUsingColorSpaceName: [self colorSpaceName]];

    NSInteger i, numberOfComponents = [color numberOfComponents];
    CGFloat components[numberOfComponents];
    NSUInteger pixels[numberOfComponents];

    // Extract the RGBA components
    [color getComponents: components];

    if (!_hasAlpha) {
        // No alpha - then drop the component count
        numberOfComponents--;
    } else {
        // Deal with the alpha component
        if ((_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat) ==
            NO) { // premultiplied
            CGFloat alpha = components[numberOfComponents - 1];

            // Multiply through the alpha
            for (i = 0; i < numberOfComponents - 1; i++) {
                components[i] *= alpha;
            }
        }

        if (_bitmapFormat & NSAlphaFirstBitmapFormat) {
            // Swap the location of the alpha component
            CGFloat alpha = components[numberOfComponents - 1];

            for (i = numberOfComponents; --i >= 1;) {
                components[i] = components[i - 1];
            }
            components[0] = alpha;
        }
    }

    if (_bitmapFormat & NSFloatingPointSamplesBitmapFormat) {
        for (i = 0; i < numberOfComponents; i++) {
            ((CGFloat *) pixels)[i] =
                    MAX(0.0f, MIN(1.0f, components[i])); // clamp just in case
        }
    } else {
        int maxValue = (1 << [self bitsPerSample]) - 1;

        for (i = 0; i < numberOfComponents; i++) {
#ifdef __LITTLE_ENDIAN__
            pixels[i] =
                    MAX(0, MIN(maxValue,
                               (int) (components[(numberOfComponents - 1) - i] *
                                      maxValue))); // clamp just in case
#else
            pixels[i] = MAX(
                    0, MIN(maxValue, (int) (components[i] *
                                            maxValue))); // clamp just in case
#endif
        }
    }

    [self setPixel: pixels atX: x y: y];
}

- valueForProperty: (NSString *) property {
    return [NS_EXTRA(NSBitmapImageRep, self)->_properties objectForKey: property];
}

- (void) setProperty: (NSString *) property withValue: value {
    [NS_EXTRA(NSBitmapImageRep, self)->_properties setObject: value forKey: property];
}

- (void) colorizeByMappingGray: (CGFloat) gray
                       toColor: (NSColor *) color
                  blackMapping: (NSColor *) blackMapping
                  whiteMapping: (NSColor *) whiteMapping
{
    NSUnimplementedMethod();
}

- (void) getCompression: (NSTIFFCompression *) compression
                 factor: (float *) factor
{
    NSUnimplementedMethod();
}

- (void) setCompression: (NSTIFFCompression) compression
                 factor: (float) factor
{
    NSUnimplementedMethod();
}

- (BOOL) canBeCompressedUsing: (NSTIFFCompression) compression {
    NSUnimplementedMethod();
    return NO;
}

- (NSData *) representationUsingType: (NSBitmapImageFileType) type
                          properties: (NSDictionary *) properties
{
    CFStringRef uti;

    switch (type) {

    case NSTIFFFileType:
        uti = (CFStringRef) @"public.tiff";
        break;

    case NSBMPFileType:
        uti = (CFStringRef) @"com.microsoft.bmp";
        break;

    case NSGIFFileType:
        uti = (CFStringRef) @"com.compuserve.gif";
        break;

    case NSJPEGFileType:
        uti = (CFStringRef) @"public.jpeg";
        break;

    case NSPNGFileType:
        uti = (CFStringRef) @"public.png";
        break;

    case NSJPEG2000FileType:
        uti = (CFStringRef) @"public.jpeg-2000";
        break;

    default:
        return nil;
    }

    int dpi = 72;
    if (_size.width > 0) {
        dpi = ceilf(72 * _pixelsWide / _size.width);
    }
    NSMutableData *result = [NSMutableData data];
    // Convert the NS options to CG options - just NSImageCompressionFactor for
    // now
    NSDictionary *CGProperties = [NSMutableDictionary dictionary];

    [CGProperties setValue: [NSNumber numberWithInt: dpi]
                    forKey: (id) kO2ImageDestinationDPI];

    if ([properties count]) {
        id compressionFactor =
                [properties valueForKey: NSImageCompressionFactor];
        if (compressionFactor) {
            [CGProperties
                    setValue: compressionFactor
                      forKey: (id) kCGImageDestinationLossyCompressionQuality];
        }
    }
    CGImageDestinationRef dest = CGImageDestinationCreateWithData(
            (CFMutableDataRef) result, uti, 1, (CFDictionaryRef) CGProperties);

    CGImageDestinationAddImage(dest, [self CGImage],
                               (CFDictionaryRef) CGProperties);

    CGImageDestinationFinalize(dest);
    CFRelease(dest);

    return result;
}

- (NSData *) TIFFRepresentation {
    return [self TIFFRepresentationUsingCompression: NSTIFFCompressionNone
                                             factor: 0.0];
}

- (NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor
{
    return [[self class]
            TIFFRepresentationOfImageRepsInArray: [NSArray
                                                          arrayWithObject: self]
                                usingCompression: compression
                                          factor: factor];
}

// Converts a planar 1-bit gray image with a 1-bit alpha plane (the layout
// of classic cursor and icon masks) to premultiplied 32-bit RGBA. Returns
// NULL when the planes are missing, the row length cannot hold a row, or
// the converted image cannot be allocated.
- (CGImageRef) _createCGImageFromOneBitPlanes {
    if (_pixelsWide <= 0 || _pixelsHigh <= 0)
        return NULL;
    // A caller can supply some planes and leave others NULL. macOS 27.0.1
    // then returns an image that faults when drawn; we return no image
    // instead, since reading a missing plane is never safe.
    if (NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes == NULL || NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0] == NULL ||
        NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[1] == NULL)
        return NULL;

    const size_t width = (size_t) _pixelsWide;
    const size_t height = (size_t) _pixelsHigh;
    const size_t rowBytes = (size_t) _bytesPerRow;

    if (rowBytes < (width + 7) / 8)
        return NULL;
    if (width > SIZE_MAX / sizeof(uint32_t) / height)
        return NULL;

    const size_t length = width * height * sizeof(uint32_t);
    uint32_t *rgba = (uint32_t *) NSZoneMalloc(NULL, length);
    if (rgba == NULL)
        return NULL;

    const BOOL alphaFirst = (_bitmapFormat & NSAlphaFirstBitmapFormat) != 0;
    const uint8_t *grayPlane = NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[alphaFirst ? 1 : 0];
    const uint8_t *alphaPlane = NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[alphaFirst ? 0 : 1];

    // A set gray sample is white in the white color spaces and black in
    // the black ones. A set alpha sample is opaque.
    const BOOL blackSpace =
            [_colorSpaceName isEqualToString: NSDeviceBlackColorSpace] ||
            [_colorSpaceName isEqualToString: NSCalibratedBlackColorSpace];

    for (size_t y = 0; y < height; y++) {
        const uint8_t *grayRow = grayPlane + y * rowBytes;
        const uint8_t *alphaRow = alphaPlane + y * rowBytes;

        for (size_t x = 0; x < width; x++) {
            unsigned shift = 7 - (unsigned) (x % 8);
            BOOL graySet = (grayRow[x / 8] >> shift) & 1;
            BOOL opaque = (alphaRow[x / 8] >> shift) & 1;
            uint32_t value = (opaque && graySet != blackSpace) ? 0xFF : 0x00;

            rgba[y * width + x] = (opaque ? 0xFF000000u : 0) | (value << 16) |
                                  (value << 8) | value;
        }
    }

    NSData *data = [[NSData alloc] initWithBytesNoCopy: rgba
                                                length: length
                                          freeWhenDone: YES];
    CGDataProviderRef provider =
            CGDataProviderCreateWithCFData((CFDataRef) data);
    [data release];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(
            width, height, 8, 32, width * sizeof(uint32_t), colorSpace,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host,
            provider, NULL, NO, kCGRenderingIntentDefault);

    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    return image;
}

- (CGImageRef) createCGImageIfNeeded {
    if (NS_EXTRA(NSBitmapImageRep, self)->_cgImage != NULL)
        return CGImageRetain(NS_EXTRA(NSBitmapImageRep, self)->_cgImage);

    [self _allocateOwnedPlanes];

    if (NS_EXTRA(NSBitmapImageRep, self)->_isPlanar) {
        if (_bitsPerSample == 1 && _samplesPerPixel == 2 && _hasAlpha)
            return [self _createCGImageFromOneBitPlanes];
        NSUnimplementedMethod();
        return NULL;
    }

    CGDataProviderRef provider = CGDataProviderCreateWithData(
            NULL, NS_EXTRA(NSBitmapImageRep, self)->_bitmapPlanes[0], _bytesPerRow * _pixelsHigh, NULL);

    size_t bpc = _bitsPerSample ? _bitsPerSample : (_bitsPerPixel / _samplesPerPixel);

    CGImageRef image = CGImageCreate(
            _pixelsWide, _pixelsHigh, bpc,
            _bitsPerPixel, _bytesPerRow, [self CGColorSpace],
            [self CGBitmapInfo], provider, NULL, NO, kCGRenderingIntentDefault);

    CGDataProviderRelease(provider);

    return image;
}

- (CGImageRef) CGImage {
    if (NS_EXTRA(NSBitmapImageRep, self)->_cgImage != NULL)
        return NS_EXTRA(NSBitmapImageRep, self)->_cgImage;

    return (CGImageRef)[(id)[self createCGImageIfNeeded] autorelease];
}

- (BOOL) draw {
    CGContextRef context = NSCurrentGraphicsPort();
    if (context == NULL)
        return NO;
    NSSize size = [self size];
    CGImageRef image = [self createCGImageIfNeeded];
    if (image == NULL)
        return NO;

    CGContextDrawImage(context, NSMakeRect(0, 0, size.width, size.height),
                       image);

    CGImageRelease(image);

    return YES;
}

- (CGColorSpaceRef) CGColorSpace {
    if ([_colorSpaceName isEqualToString: NSDeviceRGBColorSpace])
        return (CGColorSpaceRef)[(id) CGColorSpaceCreateDeviceRGB()
                                         autorelease];
    if ([_colorSpaceName isEqualToString: NSCalibratedRGBColorSpace])
        return (CGColorSpaceRef)[(id) CGColorSpaceCreateDeviceRGB()
                                         autorelease];

    return NULL;
}

- (CGBitmapInfo) CGBitmapInfo {
    // The bitmap planes store samples in component order (RGBA, ARGB with NSAlphaFirstBitmapFormat), which is what
    // the default byte order means for 8-bit samples; createBitmapIfNeeded copies CGImage data in that layout. As on
    // macOS, no byte order is reported for the image of such a rep.
    CGBitmapInfo result = kCGBitmapByteOrderDefault;

    if (![self hasAlpha]) {
        if (_bitsPerPixel == 32 && _samplesPerPixel == 3) {
            result |= (_bitmapFormat & NSAlphaFirstBitmapFormat) ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaNoneSkipLast;
        } else {
            result |= kCGImageAlphaNone;
        }
    } else {
        if (_bitmapFormat & NSAlphaFirstBitmapFormat) {
            if (_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat)
                result |= kCGImageAlphaFirst;
            else
                result |= kCGImageAlphaPremultipliedFirst;
        } else {
            if (_bitmapFormat & NSAlphaNonpremultipliedBitmapFormat)
                result |= kCGImageAlphaLast;
            else
                result |= kCGImageAlphaPremultipliedLast;
        }
    }
    if (_bitmapFormat & NSFloatingPointSamplesBitmapFormat)
        result |= kCGBitmapFloatComponents;

    return result;
}

- (NSBitmapImageRep *) bitmapImageRepByRetaggingWithColorSpace: (NSColorSpace *) newSpace {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

@end
