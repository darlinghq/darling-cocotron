/*
 * Copyright (C) 2026 Darling Developers
 */
#import "NSAssetCatalog.h"
#import "NSSVGRenderer.h"
#import <AppKit/NSBitmapImageRep.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPDFImageRep.h>
#include <compression.h>
#include <stdlib.h>
#include <string.h>

// A compiled asset catalog is a BOM store: a big-endian header, a block index,
// named variables and B-trees. In it, FACETKEYS maps asset names to attribute
// lists (attribute 17 is the rendition identifier), KEYFORMAT lists the
// attribute order of rendition keys, APPEARANCEKEYS names appearance values,
// and RENDITIONS maps keys to "CTSI" renditions. A color rendition (layout
// 1009) carries a "COLR" record: a tag, a version, the color space (the low
// byte of the third word), the component count and the components as
// little-endian doubles.
// Layout reference: the BSD-licensed libbom/libcar format headers of xcbuild;
// the color space numbers and component layout were checked against catalogs
// compiled from our own inputs.
//
// Image renditions, as found in catalogs that actool compiled from our own
// images (tests/fixtures/assetcatalog):
//  - The rendition header gives flags (bits 3-4: 1 for a template image), the
//    pixel size, the scale times 100 and the pixel format: "ARGB" (premultiplied
//    BGRA bytes), "GA8 " (premultiplied gray and alpha bytes) or "PDF ".
//  - A bitmap rendition's data is a "MLEC" record: a version, the compression
//    and a length (or, when the data is in "KCBC" chunks, their count). Chunks
//    have a 20 byte header ending in the row count and the compressed length.
//    The pixels are rows of a stride that is the decoded length over the height.
//  - Compression 4 is LZFSE. Compression 1 is a run-length encoding: three
//    words (a format code, the width, the height), the offset of each row's
//    runs, and the runs: a word count, with the top bit set for a run of one
//    pixel value repeated, clear for that many pixel values.
//  - Small images are packed into shared "ZZZZPackedAsset" renditions (layout
//    1004); an image's own rendition (layout 1003) then has a link record
//    (TLV 1010, starting with the bytes "KLNI") with the frame within the
//    packed image (bottom-left origin) and the attribute/value pairs of the
//    packed rendition's key.
//  - A PDF rendition (layout 9) holds the PDF in a "DWAR" record after a flags
//    word and a length.

enum {
    AttributeAppearance = 7,
    AttributeScale = 12,
    AttributeIdentifier = 17,
    AttributeDisplayGamut = 24,
    RenditionLayoutPDF = 9,
    RenditionLayoutInternalLink = 1003,
    RenditionLayoutPackedImage = 1004,
    RenditionLayoutColor = 1009,
    TLVInternalLink = 1010,
    CompressionNone = 0,
    CompressionRunLength = 1,
    CompressionLZFSE = 4,
    CompressionDeepmap2 = 11,
    PixelFormatARGB = 0x41524742,
    PixelFormatGA8 = 0x47413820,
    PixelFormatPDF = 0x50444620,
    PixelFormatSVG = 0x53564720,
    PixelFormatJPEG = 0x4a504547,
    MaxImageSide = 16384,
    RenditionHeaderSize = 184,
    MaxTreeDepth = 32,
};

typedef struct {
    const uint8_t *bytes;
    size_t length;
} Span;

typedef struct {
    Span file;
    Span index;
    uint32_t blockCount;
} BOMStore;

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t) p[0] << 24) | ((uint32_t) p[1] << 16) | ((uint32_t) p[2] << 8) | p[3];
}

static uint16_t le16(const uint8_t *p) {
    return (uint16_t) (p[0] | (p[1] << 8));
}

static uint32_t le32(const uint8_t *p) {
    return (uint32_t) p[0] | ((uint32_t) p[1] << 8) | ((uint32_t) p[2] << 16) | ((uint32_t) p[3] << 24);
}

static double leDouble(const uint8_t *p) {
    uint64_t bits = 0;
    for (int i = 7; i >= 0; i--)
        bits = (bits << 8) | p[i];
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static BOOL spanWithin(Span outer, size_t offset, size_t length, Span *out) {
    if (offset > outer.length || length > outer.length - offset)
        return NO;
    out->bytes = outer.bytes + offset;
    out->length = length;
    return YES;
}

static BOOL spanFrom(Span outer, size_t offset, Span *out) {
    return offset <= outer.length && spanWithin(outer, offset, outer.length - offset, out);
}

static BOOL bomOpen(Span file, BOMStore *bom) {
    Span index;
    if (file.length < 32 || memcmp(file.bytes, "BOMStore", 8) != 0)
        return NO;
    if (!spanWithin(file, be32(file.bytes + 16), be32(file.bytes + 20), &index) || index.length < 4)
        return NO;
    bom->file = file;
    bom->index = index;
    bom->blockCount = be32(index.bytes);
    if (bom->blockCount > (index.length - 4) / 8)
        bom->blockCount = (uint32_t) ((index.length - 4) / 8);
    return YES;
}

static BOOL bomBlock(const BOMStore *bom, uint32_t number, Span *out) {
    if (number >= bom->blockCount)
        return NO;
    const uint8_t *entry = bom->index.bytes + 4 + 8 * (size_t) number;
    return spanWithin(bom->file, be32(entry), be32(entry + 4), out);
}

static BOOL bomVariable(const BOMStore *bom, const char *name, Span *out) {
    Span vars;
    if (!spanFrom(bom->file, be32(bom->file.bytes + 24), &vars) || vars.length < 4)
        return NO;
    uint32_t count = be32(vars.bytes);
    size_t position = 4, nameLength = strlen(name);
    for (uint32_t i = 0; i < count && position + 5 <= vars.length; i++) {
        uint32_t block = be32(vars.bytes + position);
        size_t length = vars.bytes[position + 4];
        if (position + 5 + length > vars.length)
            return NO;
        if (length == nameLength && memcmp(vars.bytes + position + 5, name, length) == 0)
            return bomBlock(bom, block, out);
        position += 5 + length;
    }
    return NO;
}

typedef void (^LeafHandler)(Span key, Span value);

// Calls the handler for every entry of a tree's leaves, in order: down the first child of each inner node to
// the first leaf, then along the leaves' forward links. An inner node's own count is not used. A chain that loops
// or runs through overlapping blocks is cut off: a walk makes at most as many leaf visits as the store has blocks,
// and reads at most one entry per 8 bytes of the file, which a well-formed tree stays under.
static void bomWalk(const BOMStore *bom, uint32_t node, LeafHandler handler) {
    Span n;
    for (int depth = 0;; depth++) {
        if (depth > MaxTreeDepth || !bomBlock(bom, node, &n) || n.length < 12)
            return;
        if ((n.bytes[0] << 8 | n.bytes[1]) != 0)
            break;
        if (n.length < 20)
            return;
        node = be32(n.bytes + 12);
    }
    size_t budget = bom->file.length / 8;
    for (uint32_t visits = 0; visits < bom->blockCount && budget > 0; visits++) {
        size_t count = n.bytes[2] << 8 | n.bytes[3];
        if (count > (n.length - 12) / 8)
            count = (n.length - 12) / 8;
        if (count > budget)
            count = budget;
        budget -= count;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *entry = n.bytes + 12 + 8 * i;
            Span key, value;
            if (bomBlock(bom, be32(entry + 4), &key) && bomBlock(bom, be32(entry), &value))
                handler(key, value);
        }
        uint32_t forward = be32(n.bytes + 4);
        if (forward == 0 || !bomBlock(bom, forward, &n) || n.length < 12 || (n.bytes[0] << 8 | n.bytes[1]) == 0)
            return;
    }
}

static BOOL bomTree(const BOMStore *bom, const char *name, LeafHandler handler) {
    Span tree;
    if (!bomVariable(bom, name, &tree) || tree.length < 12 || memcmp(tree.bytes, "tree", 4) != 0)
        return NO;
    bomWalk(bom, be32(tree.bytes + 8), handler);
    return YES;
}


@implementation NSAssetCatalogColor
@end

static NSAssetCatalogColor *colorFromRecord(Span record, BOOL dark) {
    if (record.length < 16 || memcmp(record.bytes, "RLOC", 4) != 0)
        return nil;
    uint32_t space = le32(record.bytes + 8) & 0xff;
    uint32_t count = le32(record.bytes + 12);
    if (count == 0 || count > 4 || count > (record.length - 16) / 8)
        return nil;
    if (space != NSAssetCatalogColorSpaceSRGB && space != NSAssetCatalogColorSpaceGrayGamma22 &&
        space != NSAssetCatalogColorSpaceDisplayP3)
        return nil;
    if (space == NSAssetCatalogColorSpaceGrayGamma22 ? count != 2 : count != 4)
        return nil;

    NSAssetCatalogColor *color = [[[NSAssetCatalogColor alloc] init] autorelease];
    color->colorSpace = space;
    color->dark = dark;
    color->componentCount = count;
    for (uint32_t i = 0; i < count; i++)
        color->components[i] = leDouble(record.bytes + 16 + 8 * i);
    return color;
}

// name -> NSArray of NSAssetCatalogColor (empty if the file isn't a readable catalog).
static NSDictionary *parseCatalogColors(NSData *data) {
    BOMStore bom;
    NSMutableDictionary *colors = [NSMutableDictionary dictionary];
    if (!bomOpen((Span) { [data bytes], [data length] }, &bom))
        return colors;

    Span keyFormat;
    if (!bomVariable(&bom, "KEYFORMAT", &keyFormat) || keyFormat.length < 12 || memcmp(keyFormat.bytes, "tmfk", 4) != 0)
        return colors;
    uint32_t attributeCount = le32(keyFormat.bytes + 8);
    if (attributeCount > (keyFormat.length - 12) / 4)
        return colors;
    long appearanceSlot = -1, identifierSlot = -1, gamutSlot = -1;
    for (uint32_t i = 0; i < attributeCount; i++) {
        uint32_t attribute = le32(keyFormat.bytes + 12 + 4 * i);
        if (attribute == AttributeAppearance) appearanceSlot = i;
        if (attribute == AttributeIdentifier) identifierSlot = i;
        if (attribute == AttributeDisplayGamut) gamutSlot = i;
    }
    if (identifierSlot < 0)
        return colors;

    NSMutableSet *darkAppearances = [NSMutableSet set];
    bomTree(&bom, "APPEARANCEKEYS", ^(Span key, Span value) {
        if (value.length >= 2 && key.length >= 4 && memmem(key.bytes, key.length, "Dark", 4) != NULL)
            [darkAppearances addObject: [NSNumber numberWithUnsignedShort: le16(value.bytes)]];
    });

    // identifier -> [default appearance value, dark value]; where a catalog has several gamut variants of
    // one appearance the standard gamut wins.
    NSMutableDictionary *byIdentifier = [NSMutableDictionary dictionary];
    NSMutableDictionary *gamuts = [NSMutableDictionary dictionary];
    bomTree(&bom, "RENDITIONS", ^(Span key, Span value) {
        size_t slots = key.length / 2;
        if ((size_t) identifierSlot >= slots || value.length < RenditionHeaderSize || memcmp(value.bytes, "ISTC", 4) != 0 ||
            le16(value.bytes + 36) != RenditionLayoutColor)
            return;
        Span record;
        if (!spanFrom(value, RenditionHeaderSize + (size_t) le32(value.bytes + 168), &record))
            return;
        BOOL dark = appearanceSlot >= 0 && (size_t) appearanceSlot < slots &&
                    [darkAppearances containsObject: [NSNumber numberWithUnsignedShort: le16(key.bytes + 2 * appearanceSlot)]];
        NSAssetCatalogColor *color = colorFromRecord(record, dark);
        if (color == nil)
            return;
        uint16_t gamut = (gamutSlot >= 0 && (size_t) gamutSlot < slots) ? le16(key.bytes + 2 * gamutSlot) : 0;
        NSNumber *identifier = [NSNumber numberWithUnsignedShort: le16(key.bytes + 2 * identifierSlot)];
        NSMutableArray *values = [byIdentifier objectForKey: identifier];
        if (values == nil) {
            values = [NSMutableArray array];
            [byIdentifier setObject: values forKey: identifier];
        }
        NSNumber *variant = [NSNumber numberWithUnsignedLong: (unsigned long) [identifier unsignedShortValue] * 2 + dark];
        for (NSUInteger i = 0; i < [values count]; i++) {
            if (((NSAssetCatalogColor *) [values objectAtIndex: i])->dark != dark)
                continue;
            if (gamut < [[gamuts objectForKey: variant] unsignedShortValue]) {
                [values replaceObjectAtIndex: i withObject: color];
                [gamuts setObject: [NSNumber numberWithUnsignedShort: gamut] forKey: variant];
            }
            return;
        }
        [values addObject: color];
        [gamuts setObject: [NSNumber numberWithUnsignedShort: gamut] forKey: variant];
    });

    bomTree(&bom, "FACETKEYS", ^(Span key, Span value) {
        if (value.length < 6)
            return;
        size_t count = le16(value.bytes + 4);
        if (count > (value.length - 6) / 4)
            return;
        for (size_t i = 0; i < count; i++) {
            const uint8_t *pair = value.bytes + 6 + 4 * i;
            if (le16(pair) != AttributeIdentifier)
                continue;
            NSArray *values = [byIdentifier objectForKey: [NSNumber numberWithUnsignedShort: le16(pair + 2)]];
            NSString *name = [[[NSString alloc] initWithBytes: key.bytes length: key.length encoding: NSUTF8StringEncoding] autorelease];
            if ([values count] == 0 || name == nil)
                continue;
            // The default appearance's value first.
            NSArray *sorted = [values sortedArrayUsingComparator: ^NSComparisonResult(NSAssetCatalogColor *a, NSAssetCatalogColor *b) {
                return a->dark == b->dark ? NSOrderedSame : (a->dark ? NSOrderedDescending : NSOrderedAscending);
            }];
            [colors setObject: sorted forKey: name];
        }
    });
    return colors;
}

// One rendition of an image: its key (attribute values in KEYFORMAT order) and value.
@interface NSAssetCatalogRendition : NSObject {
@public
    Span key;
    Span value;
}
@end

@implementation NSAssetCatalogRendition
@end

typedef struct {
    long slots[32]; // attribute -> key slot, -1 if absent
} KeyFormat;

static BOOL readKeyFormat(const BOMStore *bom, KeyFormat *format) {
    Span keyFormat;
    for (int i = 0; i < 32; i++)
        format->slots[i] = -1;
    if (!bomVariable(bom, "KEYFORMAT", &keyFormat) || keyFormat.length < 12 || memcmp(keyFormat.bytes, "tmfk", 4) != 0)
        return NO;
    uint32_t count = le32(keyFormat.bytes + 8);
    if (count > (keyFormat.length - 12) / 4)
        return NO;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t attribute = le32(keyFormat.bytes + 12 + 4 * i);
        if (attribute < 32)
            format->slots[attribute] = i;
    }
    return YES;
}

static uint16_t keyAttribute(const KeyFormat *format, Span key, unsigned attribute) {
    long slot = attribute < 32 ? format->slots[attribute] : -1;
    if (slot < 0 || (size_t) slot >= key.length / 2)
        return 0;
    return le16(key.bytes + 2 * slot);
}

// The TLV entry of the given tag in a rendition, between the header and the data.
static BOOL renditionTLV(Span rendition, uint32_t tag, Span *out) {
    Span tlv;
    if (!spanWithin(rendition, RenditionHeaderSize, le32(rendition.bytes + 168), &tlv))
        return NO;
    size_t position = 0;
    while (position + 8 <= tlv.length) {
        uint32_t entryTag = le32(tlv.bytes + position), length = le32(tlv.bytes + position + 4);
        if (length > tlv.length - position - 8)
            return NO;
        if (entryTag == tag)
            return spanWithin(tlv, position + 8, length, out);
        position += 8 + length;
    }
    return NO;
}

static BOOL renditionData(Span rendition, Span *out) {
    return spanFrom(rendition, RenditionHeaderSize + (size_t) le32(rendition.bytes + 168), out);
}

static size_t bytesPerPixel(uint32_t pixelFormat) {
    return pixelFormat == PixelFormatARGB ? 4 : pixelFormat == PixelFormatGA8 ? 2 : 0;
}

// Run-length encoded rows into rows of width * pixelSize bytes.
static NSMutableData *decodeRunLength(Span data, size_t pixelSize, uint32_t width, uint32_t height) {
    if (data.length < 12 || le32(data.bytes + 4) != width || le32(data.bytes + 8) != height ||
        (size_t) height > (data.length - 12) / 4)
        return nil;
    size_t stride = (size_t) width * pixelSize;
    NSMutableData *result = [NSMutableData dataWithLength: stride * height];
    uint8_t *pixels = [result mutableBytes];
    for (uint32_t row = 0; row < height; row++) {
        size_t position = le32(data.bytes + 12 + 4 * (size_t) row);
        uint8_t *out = pixels + stride * row;
        size_t filled = 0;
        while (filled < width) {
            if (position + 4 > data.length)
                return nil;
            uint32_t word = le32(data.bytes + position);
            size_t count = word & 0x7fffffff;
            BOOL repeat = (word & 0x80000000) != 0;
            position += 4;
            if (count == 0 || count > width - filled)
                return nil;
            size_t length = repeat ? pixelSize : count * pixelSize;
            if (position + length > data.length)
                return nil;
            if (repeat) {
                for (size_t i = 0; i < count; i++)
                    memcpy(out + (filled + i) * pixelSize, data.bytes + position, pixelSize);
            } else {
                memcpy(out + filled * pixelSize, data.bytes + position, length);
            }
            position += length;
            filled += count;
        }
    }
    return result;
}

static BOOL appendLZFSE(NSMutableData *output, Span input, size_t expected) {
    if (expected == 0 || expected > (size_t) MaxImageSide * MaxImageSide * 4)
        return NO;
    size_t start = [output length];
    [output setLength: start + expected];
    size_t produced = compression_decode_buffer((uint8_t *) [output mutableBytes] + start, expected, input.bytes, input.length,
                                                NULL, COMPRESSION_LZFSE);
    [output setLength: start + produced];
    return produced > 0;
}

// The pixels of a bitmap rendition, rows top first, and their stride; nil if
// the rendition is not a bitmap this reader understands.
static NSData *decodeBitmapPixels(Span rendition, size_t *strideOut) {
    uint32_t width = le32(rendition.bytes + 12), height = le32(rendition.bytes + 16);
    size_t pixelSize = bytesPerPixel(le32(rendition.bytes + 24));
    Span data;
    if (pixelSize == 0 || width == 0 || height == 0 || width > MaxImageSide || height > MaxImageSide ||
        !renditionData(rendition, &data) || data.length < 16 || memcmp(data.bytes, "MLEC", 4) != 0)
        return nil;
    uint32_t compression = le32(data.bytes + 8), lengthOrCount = le32(data.bytes + 12);
    Span body;
    spanFrom(data, 16, &body);
    // Generous room for row padding: a stride rounded up to 64 bytes.
    size_t bound = ((size_t) width * pixelSize + 63) / 64 * 64 * height;

    NSMutableData *pixels = nil;
    if (compression == CompressionRunLength) {
        pixels = decodeRunLength(body, pixelSize, width, height);
    } else if (compression == CompressionLZFSE || compression == CompressionNone) {
        pixels = [NSMutableData data];
        if (body.length >= 4 && memcmp(body.bytes, "KCBC", 4) == 0) {
            size_t position = 0;
            for (uint32_t i = 0; i < lengthOrCount; i++) {
                Span chunk;
                if (!spanWithin(body, position, 20, &chunk) || memcmp(chunk.bytes, "KCBC", 4) != 0)
                    return nil;
                uint32_t length = le32(chunk.bytes + 16);
                if (!spanWithin(body, position + 20, length, &chunk))
                    return nil;
                if (compression == CompressionNone)
                    [pixels appendBytes: chunk.bytes length: chunk.length];
                else if (!appendLZFSE(pixels, chunk, bound - [pixels length]))
                    return nil;
                position += 20 + length;
            }
        } else {
            Span stream;
            if (!spanWithin(body, 0, MIN((size_t) lengthOrCount, body.length), &stream))
                return nil;
            if (compression == CompressionNone)
                [pixels appendBytes: stream.bytes length: stream.length];
            else if (!appendLZFSE(pixels, stream, bound))
                return nil;
        }
    } else if (compression == CompressionDeepmap2) {
        if (body.length < 32 || memcmp(body.bytes + 16, "dmp2", 4) != 0)
            return nil;
        uint32_t payloadLen = le32(body.bytes + 28);
        Span stream;
        if (!spanWithin(body, 32, payloadLen, &stream))
            return nil;
        if (body.bytes[20] == 2 && pixelSize == 2) {
            size_t planeBound = (size_t) width * height * 4 + height + 4096;
            NSMutableData *raw = [NSMutableData data];
            if (!appendLZFSE(raw, stream, planeBound) || [raw length] < (size_t) width * height)
                return nil;
            // Only the alpha plane, the first, is read. The planes after it hold the grey of the pixels, which
            // are all zero for black images (the template images this form is used for); a catalog with grey
            // that varies is not decoded rather than shown with the wrong pixels.
            const uint8_t *rawBytes = [raw bytes];
            for (size_t i = (size_t) width * height; i < [raw length]; i++)
                if (rawBytes[i] != 0)
                    return nil;
            pixels = [NSMutableData dataWithLength: (size_t) width * height * 2];
            const uint8_t *alpha = [raw bytes];
            uint8_t *out = [pixels mutableBytes];
            for (size_t i = 0; i < (size_t) width * height; i++) {
                out[i * 2] = 0;
                out[i * 2 + 1] = alpha[i];
            }
        } else {
            pixels = [NSMutableData data];
            if (!appendLZFSE(pixels, stream, bound))
                return nil;
        }
    }
    if (pixels == nil || [pixels length] % height != 0 || [pixels length] / height < (size_t) width * pixelSize)
        return nil;
    *strideOut = [pixels length] / height;
    return pixels;
}

// An NSBitmapImageRep of the given region of the pixels, converted to RGBA.
static NSBitmapImageRep *bitmapFromPixels(NSData *pixels, size_t stride, uint32_t pixelFormat, uint32_t x, uint32_t y,
                                          uint32_t width, uint32_t height, CGFloat scale) {
    size_t pixelSize = bytesPerPixel(pixelFormat);
    if (pixelSize == 0 || width == 0 || height == 0 || x + (size_t) width > stride / pixelSize ||
        (size_t) (y + height) * stride > [pixels length])
        return nil;
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                     pixelsWide: width
                                                                     pixelsHigh: height
                                                                  bitsPerSample: 8
                                                                samplesPerPixel: 4
                                                                       hasAlpha: YES
                                                                       isPlanar: NO
                                                                 colorSpaceName: NSDeviceRGBColorSpace
                                                                    bytesPerRow: width * 4
                                                                   bitsPerPixel: 32] autorelease];
    uint8_t *out = [rep bitmapData];
    const uint8_t *in = [pixels bytes];
    for (uint32_t row = 0; row < height; row++) {
        const uint8_t *source = in + (size_t) (y + row) * stride + (size_t) x * pixelSize;
        uint8_t *target = out + (size_t) row * width * 4;
        for (uint32_t column = 0; column < width; column++, source += pixelSize, target += 4) {
            if (pixelFormat == PixelFormatARGB) {
                target[0] = source[2];
                target[1] = source[1];
                target[2] = source[0];
                target[3] = source[3];
            } else {
                target[0] = target[1] = target[2] = source[0];
                target[3] = source[1];
            }
        }
    }
    [rep setSize: NSMakeSize(width / scale, height / scale)];
    return rep;
}

@implementation NSAssetCatalog

- (void) _indexImages {
    if (_renditions != nil)
        return;
    NSMutableDictionary *identifiers = [NSMutableDictionary dictionary];
    NSMutableDictionary *renditions = [NSMutableDictionary dictionary];
    BOMStore bom;
    KeyFormat format;
    if (_data != nil && bomOpen((Span) { [_data bytes], [_data length] }, &bom) && readKeyFormat(&bom, &format)) {
        bomTree(&bom, "FACETKEYS", ^(Span key, Span value) {
            if (value.length < 6)
                return;
            size_t count = le16(value.bytes + 4);
            if (count > (value.length - 6) / 4)
                return;
            for (size_t i = 0; i < count; i++) {
                const uint8_t *pair = value.bytes + 6 + 4 * i;
                if (le16(pair) != AttributeIdentifier)
                    continue;
                NSString *name = [[[NSString alloc] initWithBytes: key.bytes length: key.length encoding: NSUTF8StringEncoding] autorelease];
                if (name != nil)
                    [identifiers setObject: [NSNumber numberWithUnsignedShort: le16(pair + 2)] forKey: name];
            }
        });
        bomTree(&bom, "RENDITIONS", ^(Span key, Span value) {
            if (value.length < RenditionHeaderSize || memcmp(value.bytes, "ISTC", 4) != 0)
                return;
            NSAssetCatalogRendition *rendition = [[[NSAssetCatalogRendition alloc] init] autorelease];
            rendition->key = key;
            rendition->value = value;
            NSNumber *identifier = [NSNumber numberWithUnsignedShort: keyAttribute(&format, key, AttributeIdentifier)];
            uint16_t layout = le16(value.bytes + 36);
            if (layout == RenditionLayoutPackedImage)
                identifier = [NSNumber numberWithInt: -1];
            NSMutableArray *list = [renditions objectForKey: identifier];
            if (list == nil) {
                list = [NSMutableArray array];
                [renditions setObject: list forKey: identifier];
            }
            [list addObject: rendition];
        });
    }
    _identifiers = [identifiers copy];
    _renditions = [renditions copy];
    _packedImages = [[NSMutableDictionary alloc] init];
}

- (BOOL) _keyFormat: (KeyFormat *) format {
    BOMStore bom;
    return _data != nil && bomOpen((Span) { [_data bytes], [_data length] }, &bom) && readKeyFormat(&bom, format);
}

// The bitmap of an internal link: the frame of the packed rendition whose key
// has the attribute values the link lists.
- (NSBitmapImageRep *) _linkedBitmap: (Span) rendition format: (const KeyFormat *) format scale: (CGFloat) scale {
    Span link;
    if (!renditionTLV(rendition, TLVInternalLink, &link) || link.length < 30 || memcmp(link.bytes, "KLNI", 4) != 0)
        return nil;
    uint32_t x = le32(link.bytes + 8), y = le32(link.bytes + 12), width = le32(link.bytes + 16), height = le32(link.bytes + 20);
    uint32_t keyLength = le32(link.bytes + 26);
    Span pairs;
    if (!spanWithin(link, 30, keyLength, &pairs))
        return nil;

    uint32_t expectedFormat = le32(rendition.bytes + 24);
    NSAssetCatalogRendition *packed = nil;
    for (NSAssetCatalogRendition *candidate in [_renditions objectForKey: [NSNumber numberWithInt: -1]]) {
        if (le32(candidate->value.bytes + 24) != expectedFormat)
            continue;
        BOOL matches = YES;
        size_t pairCount = 0;
        for (size_t i = 0; i + 4 <= pairs.length && matches; i += 4) {
            uint16_t attribute = le16(pairs.bytes + i), value = le16(pairs.bytes + i + 2);
            if (attribute != 0) {
                pairCount++;
                if (keyAttribute(format, candidate->key, attribute) != value)
                    matches = NO;
            }
        }
        if (!matches)
            continue;
        size_t nonZero = 0;
        for (size_t i = 0; i + 2 <= candidate->key.length; i += 2)
            if (le16(candidate->key.bytes + i) != 0)
                nonZero++;
        if (nonZero == pairCount) {
            packed = candidate;
            break;
        }
        if (packed == nil)
            packed = candidate;
    }
    if (packed == nil)
        return nil;

    NSValue *cacheKey = [NSValue valueWithPointer: packed->value.bytes];
    NSArray *decoded = [_packedImages objectForKey: cacheKey];
    if (decoded == nil) {
        size_t stride = 0;
        NSData *pixels = decodeBitmapPixels(packed->value, &stride);
        if (pixels == nil)
            return nil;
        decoded = [NSArray arrayWithObjects: pixels, [NSNumber numberWithUnsignedLong: stride], nil];
        [_packedImages setObject: decoded forKey: cacheKey];
    }
    uint32_t packedHeight = le32(packed->value.bytes + 16);
    if (y > packedHeight || height > packedHeight - y)
        return nil;
    uint32_t topY = packedHeight - y - height;
    return bitmapFromPixels([decoded objectAtIndex: 0], [[decoded objectAtIndex: 1] unsignedLongValue],
                            le32(packed->value.bytes + 24), x, topY, width, height, scale);
}

- (NSImageRep *) _representation: (NSAssetCatalogRendition *) rendition format: (const KeyFormat *) format {
    Span value = rendition->value;
    uint16_t layout = le16(value.bytes + 36);
    uint32_t pixelFormat = le32(value.bytes + 24);
    CGFloat scale = le32(value.bytes + 20) / 100.0;
    if (scale <= 0)
        scale = 1;

    if (pixelFormat == PixelFormatPDF || pixelFormat == PixelFormatSVG || pixelFormat == PixelFormatJPEG) {
        Span data;
        if (!renditionData(value, &data) || data.length < 12 || memcmp(data.bytes, "DWAR", 4) != 0)
            return nil;
        Span payload;
        if (!spanWithin(data, 12, le32(data.bytes + 8), &payload))
            return nil;
        if (pixelFormat == PixelFormatPDF)
            return [NSPDFImageRep imageRepWithData: [NSData dataWithBytes: payload.bytes length: payload.length]];
        if (pixelFormat == PixelFormatJPEG) {
            // The payload is the JPEG file as it was given to actool, with the same wrapper as a PDF.
            NSBitmapImageRep *jpeg = [NSBitmapImageRep imageRepWithData: [NSData dataWithBytes: payload.bytes
                                                                                         length: payload.length]];
            if (jpeg != nil && scale > 1)
                [jpeg setSize: NSMakeSize([jpeg pixelsWide] / scale, [jpeg pixelsHigh] / scale)];
            return jpeg;
        }

        NSData *svgData = nil;
        if (payload.length >= 4 && memcmp(payload.bytes, "bvx", 3) == 0) {
            size_t expected = payload.length >= 8 ? le32(payload.bytes + 4) : 0;
            if (expected == 0 || expected > 16 * 1024 * 1024)
                expected = 65536;
            NSMutableData *decoded = [NSMutableData dataWithLength: expected];
            size_t produced = compression_decode_buffer([decoded mutableBytes], expected,
                                                        payload.bytes, payload.length, NULL, COMPRESSION_LZFSE);
            if (produced > 0) {
                [decoded setLength: produced];
                svgData = decoded;
            }
        } else {
            svgData = [NSData dataWithBytes: payload.bytes length: payload.length];
        }
        NSSize pointSize = NSMakeSize(le32(value.bytes + 12) / scale, le32(value.bytes + 16) / scale);
        return NSRenderSVGData(svgData, pointSize, scale);
    }
    if (layout == RenditionLayoutInternalLink)
        return [self _linkedBitmap: value format: format scale: scale];
    size_t stride = 0;
    NSData *pixels = decodeBitmapPixels(value, &stride);
    if (pixels == nil)
        return nil;
    return bitmapFromPixels(pixels, stride, pixelFormat, 0, 0, le32(value.bytes + 12), le32(value.bytes + 16), scale);
}

- (NSImage *) imageNamed: (NSString *) name {
    KeyFormat format;
    if (name == nil || ![self _keyFormat: &format])
        return nil;
    @synchronized(self) {
        [self _indexImages];
        NSNumber *identifier = [_identifiers objectForKey: name];
        NSArray *renditions = identifier ? [_renditions objectForKey: identifier] : nil;

        // For each variant (the key without the appearance and the display
        // gamut), the rendition of the default appearance and the standard
        // gamut if there is one.
        NSMutableDictionary *chosen = [NSMutableDictionary dictionary];
        for (NSAssetCatalogRendition *rendition in renditions) {
            uint32_t pixelFormat = le32(rendition->value.bytes + 24);
            uint16_t layout = le16(rendition->value.bytes + 36);
            if (layout == RenditionLayoutColor ||
                (bytesPerPixel(pixelFormat) == 0 && pixelFormat != PixelFormatPDF && pixelFormat != PixelFormatSVG &&
                 pixelFormat != PixelFormatJPEG))
                continue;
            NSMutableData *variant = [NSMutableData dataWithBytes: rendition->key.bytes length: rendition->key.length];
            uint16_t zero = 0;
            for (unsigned attribute = 0; attribute < 32; attribute++) {
                long slot = format.slots[attribute];
                if ((attribute == AttributeAppearance || attribute == AttributeDisplayGamut) && slot >= 0 &&
                    (size_t) slot < [variant length] / 2)
                    [variant replaceBytesInRange: NSMakeRange(2 * slot, 2) withBytes: &zero];
            }
            [variant appendBytes: &pixelFormat length: sizeof(pixelFormat)];
            NSAssetCatalogRendition *previous = [chosen objectForKey: variant];
            unsigned rank = keyAttribute(&format, rendition->key, AttributeAppearance) * 2 +
                            (keyAttribute(&format, rendition->key, AttributeDisplayGamut) != 0);
            if (previous == nil ||
                rank < keyAttribute(&format, previous->key, AttributeAppearance) * 2 +
                               (keyAttribute(&format, previous->key, AttributeDisplayGamut) != 0))
                [chosen setObject: rendition forKey: variant];
        }

        NSMutableArray *ordered = [NSMutableArray arrayWithArray: [chosen allValues]];
        [ordered sortUsingComparator: ^NSComparisonResult(NSAssetCatalogRendition *a, NSAssetCatalogRendition *b) {
            uint32_t sa = le32(a->value.bytes + 20), sb = le32(b->value.bytes + 20);
            return sa < sb ? NSOrderedAscending : sa > sb ? NSOrderedDescending : NSOrderedSame;
        }];

        NSImage *image = nil;
        BOOL template = NO;
        for (NSAssetCatalogRendition *rendition in ordered) {
            NSImageRep *rep = [self _representation: rendition format: &format];
            if (rep == nil)
                continue;
            if (image == nil)
                image = [[[NSImage alloc] initWithSize: [rep size]] autorelease];
            [image addRepresentation: rep];
            uint32_t pixelFormat = le32(rendition->value.bytes + 24);
            if ((bytesPerPixel(pixelFormat) != 0 || pixelFormat == PixelFormatSVG) &&
                ((le32(rendition->value.bytes + 8) >> 3) & 3) == 1)
                template = YES;
        }
        [image setTemplate: template];
        return image;
    }
}

- initWithData: (NSData *) data {
    _colors = [parseCatalogColors(data) retain];
    _data = [data retain];
    return self;
}

- (void) dealloc {
    [_colors release];
    [_data release];
    [_identifiers release];
    [_renditions release];
    [_packedImages release];
    [super dealloc];
}

+ (NSAssetCatalog *) catalogForBundle: (NSBundle *) bundle {
    static NSMutableDictionary *catalogs = nil;
    NSString *path = [(bundle ? bundle : [NSBundle mainBundle]) pathForResource: @"Assets" ofType: @"car"];
    if (path == nil)
        return nil;

    @synchronized([NSAssetCatalog class]) {
        if (catalogs == nil)
            catalogs = [[NSMutableDictionary alloc] init];
        NSAssetCatalog *catalog = [catalogs objectForKey: path];
        if (catalog == nil) {
            NSData *data = [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe error: NULL];
            catalog = [[[self alloc] initWithData: data ? data : [NSData data]] autorelease];
            [catalogs setObject: catalog forKey: path];
        }
        return catalog;
    }
}

- (NSArray *) colorsNamed: (NSString *) name {
    return name == nil ? nil : [_colors objectForKey: name];
}

@end
