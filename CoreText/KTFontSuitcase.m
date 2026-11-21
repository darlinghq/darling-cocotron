/* Copyright (C) 2026 Lubos Dolezel */
#import "KTFontSuitcase.h"
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>

// Resource file layout: "Inside Macintosh: More Macintosh Toolbox", Resource
// Manager, "Resource file format" (header, data, map, type list, reference
// lists, names). 'FOND' layout, including the style mapping table:
// "Inside Macintosh: Text", Font Manager, "Font family record". All integers
// are big endian and every offset is checked against the data before use.

static uint32_t read32(const uint8_t *p) {
    return ((uint32_t) p[0] << 24) | ((uint32_t) p[1] << 16) | ((uint32_t) p[2] << 8) | p[3];
}

static uint16_t read16(const uint8_t *p) {
    return (uint16_t) ((p[0] << 8) | p[1]);
}

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t dataOffset, dataLength;
    size_t mapOffset, mapLength;
    size_t typeListOffset;        // from the start of the map
    size_t typeCount;
} Suitcase;

typedef struct {
    int16_t identifier;
    const uint8_t *contents;
    size_t length;
} Resource;

static BOOL openSuitcase(const uint8_t *bytes, size_t length, Suitcase *suitcase) {
    if (length < 16 + 28)
        return NO;
    size_t dataOffset = read32(bytes), mapOffset = read32(bytes + 4);
    size_t dataLength = read32(bytes + 8), mapLength = read32(bytes + 12);
    if (dataOffset > length || dataLength > length - dataOffset ||
        mapOffset > length || mapLength > length - mapOffset || mapLength < 30)
        return NO;
    const uint8_t *map = bytes + mapOffset;
    size_t typeListOffset = read16(map + 24);
    if (typeListOffset + 2 > mapLength)
        return NO;
    suitcase->bytes = bytes;
    suitcase->length = length;
    suitcase->dataOffset = dataOffset;
    suitcase->dataLength = dataLength;
    suitcase->mapOffset = mapOffset;
    suitcase->mapLength = mapLength;
    suitcase->typeListOffset = typeListOffset;
    // The type count is stored minus one; 0xFFFF means no types.
    suitcase->typeCount = (size_t) read16(map + typeListOffset) + 1;
    if (suitcase->typeCount > 0x10000 ||
        typeListOffset + 2 + 8 * suitcase->typeCount > mapLength)
        return NO;
    return YES;
}

// The resources of one type that lie inside the data section, in map order.
// The caller frees the array; NULL when the file has none.
static Resource *copyResources(const Suitcase *suitcase, const char *type, size_t *count) {
    const uint8_t *map = suitcase->bytes + suitcase->mapOffset;
    const uint8_t *typeList = map + suitcase->typeListOffset;
    *count = 0;
    for (size_t t = 0; t < suitcase->typeCount; t++) {
        const uint8_t *entry = typeList + 2 + 8 * t;
        if (memcmp(entry, type, 4) != 0)
            continue;
        size_t resourceCount = (size_t) read16(entry + 4) + 1;
        size_t referenceOffset = suitcase->typeListOffset + read16(entry + 6);
        if (referenceOffset > suitcase->mapLength ||
            12 * resourceCount > suitcase->mapLength - referenceOffset)
            return NULL;
        Resource *result = calloc(resourceCount, sizeof(Resource));
        size_t found = 0;
        for (size_t r = 0; r < resourceCount; r++) {
            const uint8_t *reference = map + referenceOffset + 12 * r;
            size_t offset = read32(reference + 4) & 0xFFFFFF;
            if (offset + 4 > suitcase->dataLength)
                continue;
            const uint8_t *contents = suitcase->bytes + suitcase->dataOffset + offset;
            size_t length = read32(contents);
            if (length > suitcase->dataLength - offset - 4)
                continue;
            result[found].identifier = (int16_t) read16(reference);
            result[found].contents = contents + 4;
            result[found].length = length;
            found++;
        }
        *count = found;
        return result;
    }
    return NULL;
}

// The PostScript name a 'FOND' resource gives the face of the sfnt resource
// with this id: the base name of the style mapping table followed by the
// suffix its style indexes select. The association table lists
// (size, style, font id) triples; the scalable face has size 0. Returns nil
// when the resource has no style mapping table or does not list the id.
static NSString *postScriptNameFromFOND(const Resource *fond, int16_t sfntID) {
    const uint8_t *bytes = fond->contents;
    size_t length = fond->length;
    if (length < 54)
        return nil;
    size_t styleOffset = read32(bytes + 24);
    size_t entries = (size_t) read16(bytes + 52) + 1;
    int style = -1;
    for (size_t i = 0; i < entries && 54 + 6 * (i + 1) <= length; i++) {
        const uint8_t *entry = bytes + 54 + 6 * i;
        if (read16(entry) == 0 && (int16_t) read16(entry + 4) == sfntID) {
            style = read16(entry + 2);
            break;
        }
    }
    // Style mapping table: class (2), glyph name encoding offset (4), reserved (4),
    // one string index per style 0...47 (48 bytes), then the string count (2) and the strings.
    if (style < 0 || style >= 48 || styleOffset == 0 || styleOffset > length ||
        length - styleOffset < 10 + 48 + 2)
        return nil;
    const uint8_t *table = bytes + styleOffset;
    size_t tableLength = length - styleOffset;
    size_t stringCount = read16(table + 58);
    size_t index = table[10 + style];
    if (stringCount == 0 || stringCount > 255 || index < 1 || index > stringCount)
        return nil;

    // Strings are 1-based; the first is the base name. A suffix string made only of
    // bytes that are string indexes stands for those strings, joined.
    const uint8_t *strings[256];
    size_t sizes[256];
    size_t position = 60;
    for (size_t i = 1; i <= stringCount; i++) {
        if (position >= tableLength || position + 1 + table[position] > tableLength)
            return nil;
        sizes[i] = table[position];
        strings[i] = table + position + 1;
        position += 1 + sizes[i];
    }
    NSMutableData *name = [NSMutableData dataWithBytes: strings[1] length: sizes[1]];
    if (index > 1) {
        BOOL references = sizes[index] > 0;
        for (size_t i = 0; i < sizes[index]; i++)
            if (strings[index][i] >= 0x20 || strings[index][i] == 0 || strings[index][i] > stringCount)
                references = NO;
        if (references) {
            for (size_t i = 0; i < sizes[index]; i++) {
                size_t part = strings[index][i];
                [name appendBytes: strings[part] length: sizes[part]];
            }
        } else {
            [name appendBytes: strings[index] length: sizes[index]];
        }
    }
    return [[[NSString alloc] initWithData: name encoding: NSMacOSRomanStringEncoding] autorelease];
}

NSArray *KTFontSuitcaseCopyFaces(NSData *data) {
    Suitcase suitcase;
    if (data == nil || !openSuitcase([data bytes], [data length], &suitcase))
        return nil;
    size_t sfntCount = 0, fondCount = 0;
    Resource *sfnts = copyResources(&suitcase, "sfnt", &sfntCount);
    Resource *fonds = copyResources(&suitcase, "FOND", &fondCount);
    if (sfnts == NULL || sfntCount == 0) {
        free(sfnts);
        free(fonds);
        return nil;
    }

    // The faces the family records list come first, in the order of their association
    // tables; faces no record lists follow, in resource order.
    NSMutableArray *faces = [[NSMutableArray alloc] init];
    BOOL *listed = calloc(sfntCount, sizeof(BOOL));
    for (size_t f = 0; f < fondCount; f++) {
        const Resource *fond = &fonds[f];
        if (fond->length < 54)
            continue;
        size_t entries = (size_t) read16(fond->contents + 52) + 1;
        for (size_t e = 0; e < entries && 54 + 6 * (e + 1) <= fond->length; e++) {
            const uint8_t *entry = fond->contents + 54 + 6 * e;
            if (read16(entry) != 0)
                continue;
            for (size_t i = 0; i < sfntCount; i++) {
                if (listed[i] || sfnts[i].identifier != (int16_t) read16(entry + 4))
                    continue;
                listed[i] = YES;
                NSMutableDictionary *face = [NSMutableDictionary dictionary];
                [face setObject: [NSNumber numberWithUnsignedLong: i] forKey: @"faceIndex"];
                NSString *name = postScriptNameFromFOND(fond, sfnts[i].identifier);
                if (name != nil)
                    [face setObject: name forKey: @"postScriptName"];
                [faces addObject: face];
                break;
            }
        }
    }
    for (size_t i = 0; i < sfntCount; i++) {
        if (!listed[i])
            [faces addObject: [NSMutableDictionary dictionaryWithObject:
                    [NSNumber numberWithUnsignedLong: i] forKey: @"faceIndex"]];
    }
    free(listed);
    free(sfnts);
    free(fonds);
    return faces;
}
