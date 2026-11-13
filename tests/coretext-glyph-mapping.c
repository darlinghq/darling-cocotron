/* Copyright (C) 2026 Lubos Dolezel */
/* CTFontGetGlyphsForCharacters: the documented return value and UTF-16
 * surrogate handling; argument validation. */
#include <CoreText/CoreText.h>
#include <stdio.h>

static int failures;

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); failures++; } } while (0)

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 18, NULL);
    CHECK(font != NULL);

    UniChar a = 'A';
    CGGlyph glyph = 0;
    CHECK(CTFontGetGlyphsForCharacters(font, &a, &glyph, 1));
    CHECK(glyph != 0);

    // The glyph for a character is not changed by the characters around it.
    UniChar ab[2] = {'A', 'B'};
    CGGlyph both[2] = {0, 0};
    CHECK(CTFontGetGlyphsForCharacters(font, ab, both, 2));
    CHECK(both[0] == glyph && both[1] != 0);

    // A lone surrogate is not a character: the call reports failure and the
    // glyph is 0.
    UniChar lone = 0xD800;
    CGGlyph loneGlyph = 7;
    CHECK(!CTFontGetGlyphsForCharacters(font, &lone, &loneGlyph, 1));
    CHECK(loneGlyph == 0);

    // A surrogate pair keeps UTF-16 indexing: the low half has no glyph of its
    // own. U+10FFFF is a non-character no font covers, so the call fails, but
    // both entries are 0 and a following character is still mapped.
    UniChar pair[3] = {0xDBFF, 0xDFFF, 'A'};
    CGGlyph pairGlyphs[3] = {9, 9, 9};
    CHECK(!CTFontGetGlyphsForCharacters(font, pair, pairGlyphs, 3));
    CHECK(pairGlyphs[0] == 0 && pairGlyphs[1] == 0);
    CHECK(pairGlyphs[2] == glyph);

    // A string of covered characters succeeds.
    UniChar word[3] = {'A', 'B', 'A'};
    CGGlyph wordGlyphs[3];
    CHECK(CTFontGetGlyphsForCharacters(font, word, wordGlyphs, 3));

    // Argument validation.
    CHECK(CTFontGetGlyphsForCharacters(font, &a, &glyph, 0));
    CHECK(!CTFontGetGlyphsForCharacters(font, &a, &glyph, -1));
    CHECK(!CTFontGetGlyphsForCharacters(font, NULL, &glyph, 1));
    CHECK(!CTFontGetGlyphsForCharacters(font, &a, NULL, 1));

    CFRelease(font);
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
