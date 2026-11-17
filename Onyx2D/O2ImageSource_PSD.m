/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Foundation/NSData.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2DataProvider.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2ImageSource_PSD.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// The layout is the one of the public Photoshop file format specification:
// a 26 byte header, three length-prefixed sections (color mode data, image
// resources, layer and mask information), then the compression method and the
// flattened image as planes, one per channel.

enum {
    PSDModeBitmap = 0,
    PSDModeGray = 1,
    PSDModeIndexed = 2,
    PSDModeRGB = 3,
    PSDModeCMYK = 4,
};

enum {
    PSDCompressionRaw = 0,
    PSDCompressionRLE = 1,
};

// Images beyond these limits are refused (a 32 bit process cannot hold them).
#define PSD_MAX_DIMENSION 30000
#define PSD_MAX_PIXELS (1u << 26)
// Four color channels and one alpha channel are the most that are used.
#define PSD_MAX_USED 5

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t position;
} PSDReader;

static BOOL readBytes(PSDReader *reader, size_t count, const uint8_t **out) {
    if (reader->length - reader->position < count)
        return NO;
    *out = reader->bytes + reader->position;
    reader->position += count;
    return YES;
}

static BOOL readU16(PSDReader *reader, uint32_t *value) {
    const uint8_t *p;

    if (!readBytes(reader, 2, &p))
        return NO;
    *value = ((uint32_t) p[0] << 8) | p[1];
    return YES;
}

static BOOL readU32(PSDReader *reader, uint32_t *value) {
    const uint8_t *p;

    if (!readBytes(reader, 4, &p))
        return NO;
    *value = ((uint32_t) p[0] << 24) | ((uint32_t) p[1] << 16) |
             ((uint32_t) p[2] << 8) | p[3];
    return YES;
}

// Unpacks PackBits rows of `rowBytes` bytes each into `out`. `counts` is the
// part of the byte count table that belongs to this plane.
static BOOL unpackRLE(PSDReader *reader, uint8_t *out, size_t rowCount,
                      size_t rowBytes, const uint8_t *counts)
{
    size_t row;

    for (row = 0; row < rowCount; row++) {
        size_t packed = ((size_t) counts[row * 2] << 8) | counts[row * 2 + 1];
        const uint8_t *src;
        size_t in = 0, produced = 0;

        if (!readBytes(reader, packed, &src))
            return NO;
        while (in < packed && produced < rowBytes) {
            int8_t header = (int8_t) src[in++];

            if (header >= 0) {
                size_t run = (size_t) header + 1;

                if (run > packed - in || run > rowBytes - produced)
                    return NO;
                memcpy(out + row * rowBytes + produced, src + in, run);
                in += run;
                produced += run;
            } else if (header != -128) {
                size_t run = (size_t) (1 - header);

                if (in >= packed || run > rowBytes - produced)
                    return NO;
                memset(out + row * rowBytes + produced, src[in], run);
                in++;
                produced += run;
            }
        }
        if (produced != rowBytes)
            return NO;
    }
    return YES;
}

// The sample at pixel `index` of a plane as 8 bits: 16 bit samples keep their
// high byte and 1 bit samples (bitmap mode, 1 is black) become 0 or 255.
static inline uint8_t sampleAt(const uint8_t *plane, size_t index,
                               uint32_t depth, size_t rowBytes, size_t width)
{
    if (depth == 8)
        return plane[index];
    if (depth == 16)
        return plane[index * 2];

    size_t y = index / width, x = index % width;

    return ((plane[y * rowBytes + x / 8] >> (7 - x % 8)) & 1) ? 0 : 255;
}

@implementation O2ImageSource_PSD

+ (BOOL) isPresentInDataProvider: (O2DataProvider *) provider {
    uint8_t check[6];
    NSInteger size = [provider getBytes: check range: NSMakeRange(0, 6)];

    return size == 6 && memcmp(check, "8BPS", 4) == 0 && check[4] == 0 &&
           check[5] == 1;
}

- initWithDataProvider: (O2DataProvider *) provider
               options: (NSDictionary *) options
{
    [super initWithDataProvider: provider options: options];
    _data = (NSData *) O2DataProviderCopyData(provider);
    return self;
}

- (void) dealloc {
    [_data release];
    [_image release];
    [super dealloc];
}

// Wraps decoded pixels (which this takes ownership of) in an image. The color
// space is consumed.
- (O2Image *) newImageWithBytes: (uint8_t *) bytes
                          width: (uint32_t) width
                         height: (uint32_t) height
                     colorSpace: (O2ColorSpaceRef) colorSpace
                   bitsPerPixel: (size_t) bitsPerPixel
                     bitmapInfo: (O2BitmapInfo) info
{
    size_t bytesPerRow = (size_t) width * bitsPerPixel / 8;
    NSData *bitmap = [[NSData alloc] initWithBytesNoCopy: bytes
                                                  length: bytesPerRow * height
                                            freeWhenDone: YES];
    O2DataProviderRef provider = O2DataProviderCreateWithCFData((CFDataRef) bitmap);
    O2Image *result = [[O2Image alloc] initWithWidth: width
                                              height: height
                                    bitsPerComponent: 8
                                        bitsPerPixel: bitsPerPixel
                                         bytesPerRow: bytesPerRow
                                          colorSpace: colorSpace
                                          bitmapInfo: info
                                             decoder: NULL
                                            provider: provider
                                              decode: NULL
                                         interpolate: NO
                                     renderingIntent: kO2RenderingIntentDefault];

    O2ColorSpaceRelease(colorSpace);
    O2DataProviderRelease(provider);
    [bitmap release];
    return result;
}

- (O2Image *) decode {
    PSDReader reader = {[_data bytes], [_data length], 0};
    const uint8_t *signature, *palette = NULL;
    uint32_t version, channels, height, width, depth, mode, sectionLength;
    uint32_t colorChannels;

    if (!readBytes(&reader, 4, &signature) || memcmp(signature, "8BPS", 4) != 0)
        return nil;
    if (!readU16(&reader, &version) || version != 1)
        return nil;
    reader.position += 6;
    if (!readU16(&reader, &channels) || !readU32(&reader, &height) ||
        !readU32(&reader, &width) || !readU16(&reader, &depth) ||
        !readU16(&reader, &mode))
        return nil;
    if (channels < 1 || channels > 56 || width < 1 || height < 1 ||
        width > PSD_MAX_DIMENSION || height > PSD_MAX_DIMENSION ||
        (uint64_t) width * height > PSD_MAX_PIXELS)
        return nil;
    if (depth != 1 && depth != 8 && depth != 16)
        return nil;

    switch (mode) {
        case PSDModeBitmap:
            colorChannels = 1;
            break;
        case PSDModeGray:
            colorChannels = 1;
            break;
        case PSDModeIndexed:
            colorChannels = 1;
            break;
        case PSDModeRGB:
            colorChannels = 3;
            break;
        case PSDModeCMYK:
            colorChannels = 4;
            break;
        default:
            return nil;
    }
    // 1 bit samples exist in bitmap mode only, indexed color is 8 bit only.
    if ((depth == 1) != (mode == PSDModeBitmap) ||
        (mode == PSDModeIndexed && depth != 8) || channels < colorChannels)
        return nil;

    // color mode data: the palette (768 bytes) in indexed mode
    if (!readU32(&reader, &sectionLength) ||
        !readBytes(&reader, sectionLength, &palette))
        return nil;
    if (mode == PSDModeIndexed && sectionLength != 768)
        return nil;
    for (int i = 0; i < 2; i++) { // image resources, layer and mask information
        if (!readU32(&reader, &sectionLength) ||
            !readBytes(&reader, sectionLength, &signature))
            return nil;
    }

    uint32_t compression;

    if (!readU16(&reader, &compression))
        return nil;
    if (compression != PSDCompressionRaw && compression != PSDCompressionRLE)
        return nil;

    size_t rowBytes = depth == 1 ? (width + 7) / 8
                                 : (size_t) width * (depth / 8);
    size_t planeBytes = rowBytes * height;
    size_t pixels = (size_t) width * height;
    // The first channel after the color ones is the transparency; the others
    // are not part of the picture and are not read.
    uint32_t used = channels > colorChannels ? colorChannels + 1 : colorChannels;
    uint8_t *planes = malloc(planeBytes * used);
    BOOL ok = YES;

    if (planes == NULL)
        return nil;

    if (compression == PSDCompressionRaw) {
        for (uint32_t c = 0; c < used && ok; c++) {
            const uint8_t *src;

            ok = readBytes(&reader, planeBytes, &src);
            if (ok)
                memcpy(planes + c * planeBytes, src, planeBytes);
        }
    } else {
        const uint8_t *counts;

        // one 16 bit byte count per row of every channel of the document
        ok = readBytes(&reader, (size_t) channels * height * 2, &counts);
        for (uint32_t c = 0; c < used && ok; c++)
            ok = unpackRLE(&reader, planes + c * planeBytes, height, rowBytes,
                           counts + (size_t) c * height * 2);
    }
    if (!ok) {
        free(planes);
        return nil;
    }

    BOOL hasAlpha = used > colorChannels;

    if (!hasAlpha && (mode == PSDModeGray || mode == PSDModeBitmap)) {
        // A gray image without transparency stays a one component image.
        uint8_t *gray = malloc(pixels);

        if (gray == NULL) {
            free(planes);
            return nil;
        }
        for (size_t i = 0; i < pixels; i++)
            gray[i] = sampleAt(planes, i, depth, rowBytes, width);
        free(planes);
        return [self newImageWithBytes: gray
                                 width: width
                                height: height
                           colorSpace: O2ColorSpaceCreateDeviceGray()
                         bitsPerPixel: 8
                           bitmapInfo: kO2ImageAlphaNone];
    }

    uint8_t *rgba = malloc(pixels * 4);

    if (rgba == NULL) {
        free(planes);
        return nil;
    }

    for (size_t i = 0; i < pixels; i++) {
        uint8_t v[PSD_MAX_USED];
        uint8_t r, g, b, a = 255;

        for (uint32_t c = 0; c < used; c++)
            v[c] = sampleAt(planes + c * planeBytes, i, depth, rowBytes, width);

        switch (mode) {
            case PSDModeBitmap:
            case PSDModeGray:
                r = g = b = v[0];
                break;
            case PSDModeIndexed:
                r = palette[v[0]];
                g = palette[256 + v[0]];
                b = palette[512 + v[0]];
                break;
            case PSDModeCMYK:
                // Photoshop stores CMYK with 255 meaning no ink.
                r = (uint8_t) ((v[0] * v[3] + 127) / 255);
                g = (uint8_t) ((v[1] * v[3] + 127) / 255);
                b = (uint8_t) ((v[2] * v[3] + 127) / 255);
                break;
            default:
                r = v[0];
                g = v[1];
                b = v[2];
                break;
        }
        if (hasAlpha)
            a = v[colorChannels];
        rgba[i * 4 + 0] = (uint8_t) ((r * a + 127) / 255);
        rgba[i * 4 + 1] = (uint8_t) ((g * a + 127) / 255);
        rgba[i * 4 + 2] = (uint8_t) ((b * a + 127) / 255);
        rgba[i * 4 + 3] = a;
    }
    free(planes);

    return [self newImageWithBytes: rgba
                             width: width
                            height: height
                       colorSpace: O2ColorSpaceCreateDeviceRGB()
                     bitsPerPixel: 32
                       bitmapInfo: kO2BitmapByteOrder32Big |
                                   (hasAlpha ? kO2ImageAlphaPremultipliedLast
                                             : kO2ImageAlphaNoneSkipLast)];
}

- (void) parseIfNeeded {
    if (!_parsed) {
        _parsed = YES;
        _image = [self decode];
    }
}

- (CFStringRef) type {
    return (CFStringRef) @"com.adobe.photoshop-image";
}

- (NSUInteger) count {
    [self parseIfNeeded];
    return _image != nil ? 1 : 0;
}

- (O2Image *) createImageAtIndex: (NSUInteger) index
                         options: (NSDictionary *) options
{
    [self parseIfNeeded];
    if (index != 0 || _image == nil)
        return nil;
    return [_image retain];
}

@end
