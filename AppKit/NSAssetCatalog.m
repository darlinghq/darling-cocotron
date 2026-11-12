/*
 * Copyright (C) 2026 Darling Developers
 */
#import "NSAssetCatalog.h"
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

enum {
    AttributeAppearance = 7,
    AttributeIdentifier = 17,
    AttributeDisplayGamut = 24,
    RenditionLayoutColor = 1009,
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

static void bomWalk(const BOMStore *bom, uint32_t node, int depth, LeafHandler handler) {
    Span n;
    if (depth > MaxTreeDepth || !bomBlock(bom, node, &n) || n.length < 12)
        return;
    BOOL isLeaf = (n.bytes[0] << 8 | n.bytes[1]) != 0;
    size_t count = n.bytes[2] << 8 | n.bytes[3];
    if (count > (n.length - 12) / 8)
        count = (n.length - 12) / 8;
    for (size_t i = 0; i < count; i++) {
        const uint8_t *entry = n.bytes + 12 + 8 * i;
        uint32_t valueBlock = be32(entry), keyBlock = be32(entry + 4);
        if (!isLeaf) {
            bomWalk(bom, valueBlock, depth + 1, handler);
            continue;
        }
        Span key, value;
        if (bomBlock(bom, keyBlock, &key) && bomBlock(bom, valueBlock, &value))
            handler(key, value);
    }
}

static BOOL bomTree(const BOMStore *bom, const char *name, LeafHandler handler) {
    Span tree;
    if (!bomVariable(bom, name, &tree) || tree.length < 12 || memcmp(tree.bytes, "tree", 4) != 0)
        return NO;
    bomWalk(bom, be32(tree.bytes + 8), 0, handler);
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

@implementation NSAssetCatalog

- initWithData: (NSData *) data {
    _colors = [parseCatalogColors(data) retain];
    return self;
}

- (void) dealloc {
    [_colors release];
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
