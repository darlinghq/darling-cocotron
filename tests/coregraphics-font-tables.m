#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

static uint16_t read16(const uint8_t *bytes)
{
    return ((uint16_t)bytes[0] << 8) | bytes[1];
}

static uint32_t read32(const uint8_t *bytes)
{
    return ((uint32_t)read16(bytes) << 16) | read16(bytes + 2);
}

static bool sameTags(CFArrayRef tags, NSDictionary *expected)
{
    if (!tags || CFArrayGetCount(tags) != (CFIndex)[expected count]) return false;
    NSMutableSet *seen = [NSMutableSet set];
    for (CFIndex index = 0; index < CFArrayGetCount(tags); ++index) {
        uintptr_t value = (uintptr_t)CFArrayGetValueAtIndex(tags, index);
        if (value > UINT32_MAX) return false;
        NSNumber *key = [NSNumber numberWithUnsignedInt:(uint32_t)value];
        if (![expected objectForKey:key] || [seen containsObject:key]) return false;
        [seen addObject:key];
    }
    return true;
}

int main(int argc, const char **argv)
{
    if (argc != 2) return 2;
    NSAutoreleasePool *outer = [NSAutoreleasePool new];
    NSMutableDictionary *expected = [NSMutableDictionary new];
    NSMutableDictionary *outputs = [NSMutableDictionary new];
    NSAutoreleasePool *inner = [NSAutoreleasePool new];
    NSData *input = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    CHECK([input length] >= 12);
    const uint8_t *bytes = [input bytes];
    CHECK(read32(bytes) == 0x00010000);
    uint16_t count = read16(bytes + 4);
    CHECK(count > 0 && 12 + (size_t)count * 16 <= [input length]);
    for (size_t index = 0; index < count; ++index) {
        const uint8_t *entry = bytes + 12 + index * 16;
        uint32_t tag = read32(entry), offset = read32(entry + 8), length = read32(entry + 12);
        CHECK(offset <= [input length] && length <= [input length] - offset);
        // FreeType documents zero-length SFNT tables as missing.
        if (!length) continue;
        NSNumber *key = [NSNumber numberWithUnsignedInt:tag];
        CHECK([expected objectForKey:key] == nil);
        NSData *table = [[NSData alloc] initWithBytes:bytes + offset length:length];
        [expected setObject:table forKey:key];
        [table release];
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((CFDataRef)input);
    CHECK(provider != NULL);
    CGFontRef graphics = CGFontCreateWithDataProvider(provider);
    CHECK(graphics != NULL);
    CTFontRef font = CTFontCreateWithGraphicsFont(graphics, 18, NULL, NULL);
    CHECK(font != NULL);
    CFArrayRef tags = CGFontCopyTableTags(graphics);
    if (!tags) {
        fprintf(stderr, "CGFontCopyTableTags returned NULL for an SFNT font\n");
        return 10;
    }
    CHECK(CFGetTypeID(tags) == CFArrayGetTypeID() && sameTags(tags, expected));
    CFArrayRef ctTags = CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions);
    CFArrayRef nativeTags = CTFontCopyAvailableTables(font, kCTFontTableOptionExcludeSynthetic);
    CHECK(sameTags(ctTags, expected) && sameTags(nativeTags, expected));
    for (NSNumber *key in expected) {
        uint32_t tag = [key unsignedIntValue];
        CFDataRef cg = CGFontCopyTableForTag(graphics, tag);
        CFDataRef ct = CTFontCopyTable(font, tag, kCTFontTableOptionNoOptions);
        CFDataRef native = CTFontCopyTable(font, tag, kCTFontTableOptionExcludeSynthetic);
        CHECK(cg && ct && native && CFGetTypeID(cg) == CFDataGetTypeID());
        NSData *wanted = [expected objectForKey:key];
        CHECK([(NSData *)cg isEqualToData:wanted]);
        CHECK([(NSData *)ct isEqualToData:wanted] && [(NSData *)native isEqualToData:wanted]);
        [outputs setObject:(id)cg forKey:key];
        CFRelease(cg); CFRelease(ct); CFRelease(native);
    }
    CHECK(CGFontCopyTableTags(NULL) == NULL);
    CHECK(CTFontCopyAvailableTables(NULL, 0) == NULL);
    CHECK(CTFontCopyAvailableTables(font, (CTFontTableOptions)2) == NULL);
    CHECK(CTFontCopyTable(font, 'head', (CTFontTableOptions)2) == NULL);
    CHECK(CGFontCopyTableForTag(NULL, 'head') == NULL);
    CHECK(CTFontCopyTable(NULL, 'head', 0) == NULL);
    const uint32_t missing[] = {'ZZZZ', 0, 1};
    for (size_t index = 0; index < sizeof(missing) / sizeof(missing[0]); ++index) {
        CHECK(CGFontCopyTableForTag(graphics, missing[index]) == NULL);
        CHECK(CTFontCopyTable(font, missing[index], 0) == NULL);
    }
    CFRelease(font);
    CGFontRelease(graphics);
    CGDataProviderRelease(provider);
    [inner drain];
    CHECK(sameTags(tags, expected) && sameTags(ctTags, expected) && sameTags(nativeTags, expected));
    for (NSNumber *key in expected)
        CHECK([[outputs objectForKey:key] isEqualToData:[expected objectForKey:key]]);
    CFRelease(tags); CFRelease(ctTags); CFRelease(nativeTags);
    [outputs release]; [expected release];
    [outer drain];
    puts("Native unboxed table tags, exact bytes, options, and owned lifetime passed");
    return 0;
}
