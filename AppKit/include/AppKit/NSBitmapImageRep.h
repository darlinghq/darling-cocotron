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
#import <AppKit/NSImageRep.h>
#import <ApplicationServices/ApplicationServices.h>

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
@interface NSBitmapImageRep : NSImageRep {
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
    NS_EXTRA_IVARS_END(NSBitmapImageRep)
}

+ (void) getTIFFCompressionTypes: (const NSTIFFCompression **) types
                           count: (int *) count;
+ (NSString *) localizedNameForTIFFCompressionType: (NSTIFFCompression) type;
+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array;
+ (NSData *) TIFFRepresentationOfImageRepsInArray: (NSArray *) array
                                 usingCompression:
                                         (NSTIFFCompression) compression
                                           factor: (float) factor;

+ (NSData *) representationOfImageRepsInArray: (NSArray *) array
                                    usingType: (NSBitmapImageFileType) type
                                   properties: (NSDictionary *) properties;

+ (NSArray *) imageRepsWithData: (NSData *) data;
+ imageRepWithData: (NSData *) data;

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
              bitsPerPixel: (int) bitsPerPixel;

- initWithBitmapDataPlanes: (unsigned char **) planes
                pixelsWide: (int) width
                pixelsHigh: (int) height
             bitsPerSample: (int) bitsPerSample
           samplesPerPixel: (int) samplesPerPixel
                  hasAlpha: (BOOL) hasAlpha
                  isPlanar: (BOOL) isPlanar
            colorSpaceName: (NSString *) colorSpaceName
               bytesPerRow: (int) bytesPerRow
              bitsPerPixel: (int) bitsPerPixel;

- initForIncrementalLoad;

- initWithFocusedViewRect: (NSRect) rect;

- initWithData: (NSData *) data;
- initWithContentsOfFile: (NSString *) path;
- initWithCGImage: (CGImageRef) cgImage;

- (int) incrementalLoadFromData: (NSData *) data complete: (BOOL) complete;

- (int) bitsPerPixel;
- (int) samplesPerPixel;
- (int) bytesPerRow;
- (BOOL) isPlanar;
- (int) numberOfPlanes;
- (int) bytesPerPlane;

- (NSBitmapFormat) bitmapFormat;
- (unsigned char *) bitmapData;

- (void) getBitmapDataPlanes: (unsigned char **) planes;

- (void) getPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y;
- (void) setPixel: (NSUInteger[]) pixel atX: (NSInteger) x y: (NSInteger) y;

- (NSColor *) colorAtX: (NSInteger) x y: (NSInteger) y;
- (void) setColor: (NSColor *) color atX: (NSInteger) x y: (NSInteger) y;

- valueForProperty: (NSString *) property;
- (void) setProperty: (NSString *) property withValue: value;

- (void) colorizeByMappingGray: (CGFloat) gray
                       toColor: (NSColor *) color
                  blackMapping: (NSColor *) blackMapping
                  whiteMapping: (NSColor *) whiteMapping;

- (void) getCompression: (NSTIFFCompression *) compression
                 factor: (float *) factor;
- (void) setCompression: (NSTIFFCompression) compression factor: (float) factor;

- (BOOL) canBeCompressedUsing: (NSTIFFCompression) compression;

- (NSData *) representationUsingType: (NSBitmapImageFileType) type
                          properties: (NSDictionary *) properties;

- (NSData *) TIFFRepresentation;
- (NSData *) TIFFRepresentationUsingCompression: (NSTIFFCompression) compression
                                         factor: (float) factor;

- (CGImageRef) CGImage;

- (NSBitmapImageRep *) bitmapImageRepByRetaggingWithColorSpace: (NSColorSpace *) newSpace;

@end
