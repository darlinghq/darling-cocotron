#import <AppKit/NSColor.h>
#import <Foundation/Foundation.h>
#include <string.h>

// Named colors from a bundle's compiled asset catalog (Contents/Resources/Assets.car).
// The file is a BOM store: a big-endian header, a block index, named variables and B-trees. In it,
// FACETKEYS maps asset names to attribute lists (attribute 17 is the rendition identifier), KEYFORMAT lists
// the attribute order of rendition keys, APPEARANCEKEYS names appearance values, and RENDITIONS maps keys
// to "CTSI" renditions. A color rendition (layout 1009) carries a "COLR" record with its components.
// Layout reference: the BSD-licensed libbom/libcar format headers of xcbuild.

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

static NSColor *colorFromRecord(Span record) {
    // "COLR" record: tag, version, flags, component count, then little-endian doubles
    if (record.length < 16 || memcmp(record.bytes, "RLOC", 4) != 0)
        return nil;
    uint32_t count = le32(record.bytes + 12);
    if (count > (record.length - 16) / 8)
        return nil;
    const uint8_t *c = record.bytes + 16;
    // Calibrated spaces: AppKit's color conversions don't handle the space +colorWithSRGBRed: tags colors with.
    if (count == 4)
        return [NSColor colorWithCalibratedRed: leDouble(c) green: leDouble(c + 8) blue: leDouble(c + 16) alpha: leDouble(c + 24)];
    if (count == 2)
        return [NSColor colorWithCalibratedWhite: leDouble(c) alpha: leDouble(c + 8)];
    return nil;
}

// Returns name -> NSColor for every named color in the catalog (empty if the file isn't a readable catalog).
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

    // identifier -> best color: prefer non-dark appearances, then the standard display gamut
    NSMutableDictionary *byIdentifier = [NSMutableDictionary dictionary];
    NSMutableDictionary *scores = [NSMutableDictionary dictionary];
    bomTree(&bom, "RENDITIONS", ^(Span key, Span value) {
        size_t slots = key.length / 2;
        if ((size_t) identifierSlot >= slots || value.length < RenditionHeaderSize || memcmp(value.bytes, "ISTC", 4) != 0 ||
            le16(value.bytes + 36) != RenditionLayoutColor)
            return;
        Span record;
        if (!spanFrom(value, RenditionHeaderSize + (size_t) le32(value.bytes + 168), &record))
            return;
        NSColor *color = colorFromRecord(record);
        if (color == nil)
            return;
        int score = 0;
        if (appearanceSlot >= 0 && (size_t) appearanceSlot < slots &&
            [darkAppearances containsObject: [NSNumber numberWithUnsignedShort: le16(key.bytes + 2 * appearanceSlot)]])
            score += 2;
        if (gamutSlot >= 0 && (size_t) gamutSlot < slots && le16(key.bytes + 2 * gamutSlot) != 0)
            score += 1;
        NSNumber *identifier = [NSNumber numberWithUnsignedShort: le16(key.bytes + 2 * identifierSlot)];
        NSNumber *previous = [scores objectForKey: identifier];
        if (previous == nil || score < [previous intValue]) {
            [byIdentifier setObject: color forKey: identifier];
            [scores setObject: [NSNumber numberWithInt: score] forKey: identifier];
        }
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
            NSColor *color = [byIdentifier objectForKey: [NSNumber numberWithUnsignedShort: le16(pair + 2)]];
            NSString *name = [[[NSString alloc] initWithBytes: key.bytes length: key.length encoding: NSUTF8StringEncoding] autorelease];
            if (color != nil && name != nil)
                [colors setObject: color forKey: name];
        }
    });
    return colors;
}

@implementation NSColor (NSAssetCatalog)

+ (NSColor *) _colorNamedInAssetCatalog: (NSString *) name bundle: (NSBundle *) bundle {
    static NSMutableDictionary *catalogs = nil;
    NSString *path = [(bundle ? bundle : [NSBundle mainBundle]) pathForResource: @"Assets" ofType: @"car"];
    if (path == nil || name == nil)
        return nil;

    NSDictionary *colors;
    @synchronized ([NSColor class]) {
        if (catalogs == nil)
            catalogs = [[NSMutableDictionary alloc] init];
        colors = [catalogs objectForKey: path];
        if (colors == nil) {
            NSData *data = [NSData dataWithContentsOfFile: path options: NSDataReadingMappedIfSafe error: NULL];
            colors = data ? parseCatalogColors(data) : [NSDictionary dictionary];
            [catalogs setObject: colors forKey: path];
        }
    }
    return [colors objectForKey: name];
}

@end
