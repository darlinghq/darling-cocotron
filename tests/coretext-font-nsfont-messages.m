/* Copyright (C) 2026 Lubos Dolezel */
/* A CTFontRef is toll-free bridged to NSFont: code holding one may send it
 * NSFont's glyph messages. */
#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface NSObject (GlyphMessages)
- (CGRect)boundingRectForGlyph:(NSUInteger)glyph;
- (NSUInteger)glyphPacking;
- (BOOL)glyphIsEncoded:(NSUInteger)glyph;
- (CGSize)advancementForGlyph:(NSUInteger)glyph;
- (CGSize)maximumAdvancement;
- (NSUInteger)numberOfGlyphs;
@end

int main(void) {
    @autoreleasepool {
        CTFontRef ctFont = CTFontCreateWithName(CFSTR("Helvetica"), 24, NULL);
        CHECK(ctFont != NULL);
        id font = (id)ctFont;

        UniChar a = 'A';
        CGGlyph glyph = 0;
        CHECK(CTFontGetGlyphsForCharacters(ctFont, &a, &glyph, 1));

        CHECK([font numberOfGlyphs] == (NSUInteger)CTFontGetGlyphCount(ctFont));
        CHECK([font glyphIsEncoded:glyph]);
        CHECK(![font glyphIsEncoded:[font numberOfGlyphs]]);
        CHECK([font glyphPacking] == 0);

        CGSize advance = [font advancementForGlyph:glyph];
        CGSize expected;
        CTFontGetAdvancesForGlyphs(ctFont, kCTFontOrientationDefault, &glyph, &expected, 1);
        CHECK(advance.width > 0 && advance.width == expected.width);
        CHECK([font maximumAdvancement].width >= advance.width);

        CGRect box = [font boundingRectForGlyph:glyph];
        CHECK(box.size.width > 0 && box.size.height > 0);
        CHECK(box.size.height <= 2 * 24);

        CFRelease(ctFont);
    }
    puts(failures ? "FAILED" : "PASS");
    return failures != 0;
}
