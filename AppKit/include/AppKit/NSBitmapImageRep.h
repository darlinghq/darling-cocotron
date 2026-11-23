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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImageRep.h>
#import <ApplicationServices/ApplicationServices.h>

@class NSImageRep;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSBitmapImageFileType) {
    NSBitmapImageFileTypeTIFF,
    NSBitmapImageFileTypeBMP,
    NSBitmapImageFileTypeGIF,
    NSBitmapImageFileTypeJPEG,
    NSBitmapImageFileTypePNG,
    NSBitmapImageFileTypeJPEG2000,

    // Names used by the macOS 10.12+ SDK.
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSTIFFFileType = NSBitmapImageFileTypeTIFF,
    NSBMPFileType = NSBitmapImageFileTypeBMP,
    NSGIFFileType = NSBitmapImageFileTypeGIF,
    NSJPEGFileType = NSBitmapImageFileTypeJPEG,
    NSPNGFileType = NSBitmapImageFileTypePNG,
    NSJPEG2000FileType = NSBitmapImageFileTypeJPEG2000,
};

typedef NS_ENUM(NSUInteger, NSTIFFCompression) {
    NSTIFFCompressionNone = 1,
    NSTIFFCompressionCCITTFAX3 = 3,
    NSTIFFCompressionCCITTFAX4 = 4,
    NSTIFFCompressionLZW = 5,
    NSTIFFCompressionJPEG = 6,
    NSTIFFCompressionNEXT = 32766,
    NSTIFFCompressionPackBits = 32773,
    NSTIFFCompressionOldJPEG = 32865,
};

typedef NS_OPTIONS(NSUInteger, NSBitmapFormat) {
    NSBitmapFormatAlphaFirst = 0x01,
    NSBitmapFormatAlphaNonpremultiplied = 0x02,
    NSBitmapFormatFloatingPointSamples = 0x04,
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSAlphaFirstBitmapFormat = NSBitmapFormatAlphaFirst,
    NSAlphaNonpremultipliedBitmapFormat = NSBitmapFormatAlphaNonpremultiplied,
    NSFloatingPointSamplesBitmapFormat = NSBitmapFormatFloatingPointSamples,
};

typedef NSString *NSBitmapImageRepPropertyKey NS_STRING_ENUM;

APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageCompressionFactor;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageCompressionMethod;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageDitherTransparency;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageInterlaced;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageRGBColorTable;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageFrameCount;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageColorSyncProfileData;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageFallbackBackgroundColor;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageEXIFData;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageProgressive;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageGamma;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageLoopCount;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageCurrentFrameDuration;
APPKIT_EXPORT NSBitmapImageRepPropertyKey NSImageCurrentFrame;

typedef NS_ENUM(NSInteger, NSImageRepLoadStatus) {
    NSImageRepLoadStatusUnknownType = -1,
    NSImageRepLoadStatusReadingHeader = -2,
    NSImageRepLoadStatusWillNeedAllData = -3,
    NSImageRepLoadStatusInvalidData = -4,
    NSImageRepLoadStatusUnexpectedEOF = -5,
    NSImageRepLoadStatusCompleted = -6,
};

// Legacy ObjC ABI (i386): instance size must stay 0x34, Apple's; the ivars
// before the extras keep their position in the original order. Add new state
// to the extra struct, never as an ivar.
@interface NSBitmapImageRep : NSImageRep <NSSecureCoding> {
    int _samplesPerPixel;
    int _bitsPerPixel;
    int _bytesPerRow;
    int _bytesPerPlane;
    NSBitmapFormat _bitmapFormat;
    NS_EXTRA_IVARS_BEGIN(NSBitmapImageRep)
        BOOL _freeWhenDone;
        BOOL _isPlanar;
        unsigned char **_bitmapPlanes;
        NSMutableDictionary *_properties;

        CGImageRef _cgImage;
        NSColorSpace *_colorSpace;
    NS_EXTRA_IVARS_END(NSBitmapImageRep)
}

+ (void) getTIFFCompressionTypes: (const NSTIFFCompression * _Nullable * _Nonnull) types
                           count: (null_unspecified int *) count;
+ (nullable NSString *) localizedNameForTIFFCompressionType: (NSTIFFCompression) type;
+ (nullable NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray<NSImageRep *> *) array;
+ (nullable NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray<NSImageRep *> *) array
                                 usingCompression:
                                         (NSTIFFCompression) compression
                                           factor: (float) factor;

+ (nullable NSData *) representationOfImageRepsInArray: (NSArray<NSImageRep *> *) array
                                    usingType: (NSBitmapImageFileType) type
                                   properties: (NSDictionary<NSBitmapImageRepPropertyKey, id> *) properties;

+ (NSArray<NSImageRep *> *) imageRepsWithData: (NSData *) data;
+ (null_unspecified id) imageRepWithData: (NSData *) data;

- (nullable instancetype) initWithBitmapDataPlanes: (unsigned char *_Nullable *_Nullable) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (null_unspecified NSString *) colorSpaceName
              bitmapFormat: (NSBitmapFormat) bitmapFormat
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel;

- (nullable instancetype) initWithBitmapDataPlanes: (unsigned char *_Nullable *_Nullable) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (null_unspecified NSString *) colorSpaceName
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel;

- (instancetype) initForIncrementalLoad;

- (nullable instancetype) initWithFocusedViewRect: (NSRect) rect;

- (nullable instancetype) initWithData: (NSData *) data;
- (nullable instancetype) initWithContentsOfFile: (NSString *) path;
- (instancetype) initWithCGImage: (CGImageRef) cgImage;

- (int) incrementalLoadFromData: (NSData *) data complete: (BOOL) complete;

- (int) bitsPerPixel;
- (int) samplesPerPixel;
- (int) bytesPerRow;
- (BOOL) isPlanar;
- (int) numberOfPlanes;
- (int) bytesPerPlane;

- (NSBitmapFormat) bitmapFormat;
- (nullable unsigned char *) bitmapData;

- (void) getBitmapDataPlanes: (unsigned char *_Nullable *_Nonnull) planes;

- (void) getPixel: (NSUInteger[_Nonnull]) pixel atX: (NSInteger) x y: (NSInteger) y;
- (void) setPixel: (NSUInteger[_Nonnull]) pixel atX: (NSInteger) x y: (NSInteger) y;

- (nullable NSColor *) colorAtX: (NSInteger) x y: (NSInteger) y;
- (void) setColor: (NSColor *) color atX: (NSInteger) x y: (NSInteger) y;

- (nullable id) valueForProperty: (null_unspecified NSString *) property;
- (void) setProperty: (null_unspecified NSString *) property withValue: (nullable id) value;

- (void) colorizeByMappingGray: (CGFloat) gray
                       toColor: (nullable NSColor *) color
                  blackMapping: (nullable NSColor *) blackMapping
                  whiteMapping: (nullable NSColor *) whiteMapping;

- (void) getCompression: (nullable NSTIFFCompression *) compression
                 factor: (nullable float *) factor;
- (void) setCompression: (NSTIFFCompression) compression factor: (float) factor;

- (BOOL) canBeCompressedUsing: (NSTIFFCompression) compression;

- (nullable NSData *) representationUsingType: (NSBitmapImageFileType) type
                          properties: (NSDictionary<NSBitmapImageRepPropertyKey, id> *) properties;

- (nullable NSData *) TIFFRepresentation;
- (nullable NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor;

- (nullable CGImageRef) CGImage;

@property(nullable, readonly, strong) NSColorSpace *colorSpace;

- (nullable NSBitmapImageRep *) bitmapImageRepByConvertingToColorSpace: (NSColorSpace *) targetSpace
                                                       renderingIntent: (NSColorRenderingIntent) renderingIntent;
- (nullable NSBitmapImageRep *) bitmapImageRepByRetaggingWithColorSpace: (NSColorSpace *) newSpace;

@end

NS_ASSUME_NONNULL_END
