/* Copyright (C) 2026 Lubos Dolezel */
/* CoreText font functions that macOS exports but the SDK does not declare.
 *
 * Checked against the public functions they agree with: the glyphs for a
 * character range are those CTFontGetGlyphsForCharacters gives, a fallback
 * font covers the characters it is chosen for, shaping keeps one glyph per
 * input glyph with the font's advances. Darling draws no colour or sbix
 * glyphs and applies no feature substitutions, so those report nothing (no
 * colour coverage, an empty feature coverage, a zero sbix size). NULL
 * arguments give NULL, 0 or false. */
#include <CoreText/CoreText.h>
#include <math.h>
#include <stdio.h>

typedef CFOptionFlags CTFontFallbackOption;
enum { kCTFontFallbackOptionDefault = 3 };
typedef CFOptionFlags CTFontShapeOptions;
enum { kCTFontShapeWithKerning = 1 << 0, kCTFontShapeRightToLeft = 1 << 2 };

extern bool CTFontGetGlyphsForCharacterRange(CTFontRef, CGGlyph[], CFRange);
extern bool CTFontGetVerticalGlyphsForCharacters(CTFontRef, const UniChar[], CGGlyph[], CFIndex);
extern CFBitVectorRef CTFontCopyColorGlyphCoverage(CTFontRef);
extern CFBitVectorRef CTFontCopyGlyphCoverageForFeature(CTFontRef, CFDictionaryRef);
extern CGFloat CTFontGetSbixImageSizeForGlyphAndContentsScale(CTFontRef, const CGGlyph, CGFloat);
extern CTFontSymbolicTraits CTFontGetPhysicalSymbolicTraits(CTFontRef);
extern bool CTFontIsAppleColorEmoji(CTFontRef);
extern CTFontRef CTFontCreateForCharactersWithLanguageAndOption(CTFontRef, const UTF16Char *, CFIndex,
                                                                CFStringRef, CTFontFallbackOption, CFIndex *);
extern CGFloat CTFontGetAccessibilityBoldWeightOfWeight(CGFloat);
extern CGSize CTFontShapeGlyphs(CTFontRef, CGGlyph[], CGSize[], CGPoint[], CFIndex[], const UniChar[],
                                CFIndex, CTFontShapeOptions, CFStringRef,
                                void (^)(CFRange, CGGlyph **, CGSize **, CGPoint **, CFIndex **));
extern const CGFloat kCTFontWeightRegular, kCTFontWeightMedium, kCTFontWeightBlack, kCTFontWeightUltraLight;

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void testGlyphLookup(CTFontRef font) {
    CGGlyph range[26], direct[26];
    UniChar letters[26];
    for (int i = 0; i < 26; i++)
        letters[i] = 'a' + i;
    CHECK(CTFontGetGlyphsForCharacterRange(font, range, CFRangeMake('a', 26)));
    CHECK(CTFontGetGlyphsForCharacters(font, letters, direct, 26));
    for (int i = 0; i < 26; i++)
        CHECK(range[i] == direct[i] && range[i] != 0);
    /* surrogate code units are no characters */
    CGGlyph surrogates[2] = { 1, 1 };
    CHECK(!CTFontGetGlyphsForCharacterRange(font, surrogates, CFRangeMake(0xDBFF, 2)));
    CHECK(surrogates[0] == 0 && surrogates[1] == 0);
    CHECK(!CTFontGetGlyphsForCharacterRange(font, range, CFRangeMake(0xFFFF, 2)));
    CHECK(!CTFontGetGlyphsForCharacterRange(font, NULL, CFRangeMake('a', 1)));
    CHECK(!CTFontGetGlyphsForCharacterRange(NULL, range, CFRangeMake('a', 1)));

    /* vertical text uses the nominal glyphs (Darling has no vertical substitution) */
    CGGlyph vertical[26];
    CHECK(CTFontGetVerticalGlyphsForCharacters(font, letters, vertical, 26));
    for (int i = 0; i < 26; i++)
        CHECK(vertical[i] == direct[i]);
    CHECK(!CTFontGetVerticalGlyphsForCharacters(NULL, letters, vertical, 1));
}

static void testCoverage(CTFontRef font) {
    CHECK(CTFontCopyColorGlyphCoverage(font) == NULL);
    CHECK(CTFontCopyColorGlyphCoverage(NULL) == NULL);
    CHECK(!(CTFontGetSymbolicTraits(font) & kCTFontTraitColorGlyphs));

    const void *keys[] = { kCTFontOpenTypeFeatureTag, kCTFontOpenTypeFeatureValue };
    int one = 1;
    CFNumberRef value = CFNumberCreate(NULL, kCFNumberIntType, &one);
    const void *values[] = { CFSTR("smcp"), value };
    CFDictionaryRef feature = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks,
                                                 &kCFTypeDictionaryValueCallBacks);
    CFBitVectorRef coverage = CTFontCopyGlyphCoverageForFeature(font, feature);
    CHECK(coverage != NULL);
    if (coverage != NULL) {
        CFIndex count = CFBitVectorGetCount(coverage);
        CHECK(count == CTFontGetGlyphCount(font));
        CHECK(CFBitVectorGetCountOfBit(coverage, CFRangeMake(0, count), 1) == 0);
        CFRelease(coverage);
    }
    CHECK(CTFontCopyGlyphCoverageForFeature(NULL, feature) == NULL);
    CHECK(CTFontCopyGlyphCoverageForFeature(font, NULL) == NULL);
    CFRelease(feature);
    CFRelease(value);

    UniChar a = 'a';
    CGGlyph glyph = 0;
    CTFontGetGlyphsForCharacters(font, &a, &glyph, 1);
    CHECK(CTFontGetSbixImageSizeForGlyphAndContentsScale(font, glyph, 0) == 0);
    CHECK(CTFontGetSbixImageSizeForGlyphAndContentsScale(font, glyph, 2) == 0);
    CHECK(CTFontGetSbixImageSizeForGlyphAndContentsScale(NULL, glyph, 2) == 0);
}

static void testTraits(CTFontRef font) {
    CHECK(CTFontGetPhysicalSymbolicTraits(font) == CTFontGetSymbolicTraits(font));
    CHECK(CTFontGetPhysicalSymbolicTraits(NULL) == 0);
    CHECK(!CTFontIsAppleColorEmoji(font));
    CHECK(!CTFontIsAppleColorEmoji(NULL));
}

static void testFallback(CTFontRef font) {
    const UTF16Char latin[] = { 'a', 'b', 'c' };
    CFIndex covered = -1;
    CTFontRef same = CTFontCreateForCharactersWithLanguageAndOption(font, latin, 3, NULL,
                                                                     kCTFontFallbackOptionDefault, &covered);
    CHECK(same != NULL && covered == 3);
    if (same) {
        CFStringRef a = CTFontCopyPostScriptName(same), b = CTFontCopyPostScriptName(font);
        CHECK(a && b && CFEqual(a, b));
        if (a) CFRelease(a);
        if (b) CFRelease(b);
        CFRelease(same);
    }
    /* a character the font may lack: the result covers at least it, or nothing at all */
    const UTF16Char mixed[] = { 0x4E2D, 'a' };
    covered = -1;
    CTFontRef fallback = CTFontCreateForCharactersWithLanguageAndOption(font, mixed, 2, CFSTR("zh-Hans"),
                                                                         kCTFontFallbackOptionDefault, &covered);
    CHECK(fallback != NULL && covered >= 0 && covered <= 2);
    if (fallback && covered > 0) {
        CGGlyph glyph;
        CHECK(CTFontGetGlyphsForCharacters(fallback, mixed, &glyph, 1));
    }
    if (fallback) CFRelease(fallback);
    covered = -1;
    CHECK(CTFontCreateForCharactersWithLanguageAndOption(NULL, latin, 3, NULL, 0, &covered) == NULL && covered == 0);
    covered = -1;
    CHECK(CTFontCreateForCharactersWithLanguageAndOption(font, NULL, 3, NULL, 0, &covered) == NULL && covered == 0);
    CHECK(CTFontCreateForCharactersWithLanguageAndOption(font, latin, 0, NULL, 0, NULL) == NULL);
}

static void testBoldWeight(void) {
    /* observed on macOS 26.7.3 for every named weight */
    const CGFloat from[] = { kCTFontWeightUltraLight, kCTFontWeightThin, kCTFontWeightLight,
        kCTFontWeightRegular, kCTFontWeightMedium, kCTFontWeightSemibold, kCTFontWeightBold,
        kCTFontWeightHeavy, kCTFontWeightBlack };
    const CGFloat to[] = { kCTFontWeightThin, kCTFontWeightLight, kCTFontWeightRegular,
        kCTFontWeightSemibold, kCTFontWeightBold, kCTFontWeightHeavy, kCTFontWeightBlack,
        kCTFontWeightBlack, kCTFontWeightBlack };
    for (size_t i = 0; i < sizeof from / sizeof from[0]; i++)
        CHECK(CTFontGetAccessibilityBoldWeightOfWeight(from[i]) == to[i]);
    /* Darling's choice for weights that are not named: as the named weight below */
    CHECK(CTFontGetAccessibilityBoldWeightOfWeight(0.1) == kCTFontWeightSemibold);
    CHECK(CTFontGetAccessibilityBoldWeightOfWeight(-1) == -1);
}

static void testShaping(CTFontRef font) {
    const UniChar text[] = { 'A', 'V', 'o' };
    CGGlyph glyphs[3], original[3];
    CTFontGetGlyphsForCharacters(font, text, glyphs, 3);
    for (int i = 0; i < 3; i++)
        original[i] = glyphs[i];
    CGSize advances[3] = { { 99, 99 }, { 99, 99 }, { 99, 99 } }, expected[3];
    CGPoint origins[3] = { { 5, 5 }, { 5, 5 }, { 5, 5 } };
    CFIndex indexes[3] = { 0, 1, 2 };
    __block int calls = 0;
    CGSize initial = CTFontShapeGlyphs(font, glyphs, advances, origins, indexes, text, 3, 0, NULL,
                                       ^(CFRange r, CGGlyph **g, CGSize **a, CGPoint **o, CFIndex **i) { calls++; });
    CTFontGetAdvancesForGlyphs(font, kCTFontOrientationHorizontal, original, expected, 3);
    CHECK(initial.width == 0 && initial.height == 0 && calls == 0);
    for (int i = 0; i < 3; i++) {
        CHECK(glyphs[i] == original[i] && indexes[i] == i);
        CHECK(advances[i].width == expected[i].width && advances[i].height == expected[i].height);
        CHECK(origins[i].x == 0 && origins[i].y == 0);
    }

    /* kerning only changes advances; right to left comes back in visual order */
    CTFontShapeGlyphs(font, glyphs, advances, origins, indexes, text, 3, kCTFontShapeWithKerning, NULL, NULL);
    for (int i = 0; i < 3; i++)
        CHECK(glyphs[i] == original[i] && isfinite(advances[i].width));
    CTFontShapeGlyphs(font, glyphs, advances, origins, indexes, text, 3, kCTFontShapeRightToLeft, NULL, NULL);
    for (int i = 0; i < 3; i++)
        CHECK(glyphs[i] == original[2 - i] && indexes[i] == 2 - i && advances[i].width == expected[2 - i].width);

    initial = CTFontShapeGlyphs(NULL, glyphs, advances, origins, indexes, text, 3, 0, NULL, NULL);
    CHECK(initial.width == 0 && initial.height == 0);
    initial = CTFontShapeGlyphs(font, NULL, advances, origins, indexes, text, 3, 0, NULL, NULL);
    CHECK(initial.width == 0 && initial.height == 0);
    initial = CTFontShapeGlyphs(font, glyphs, advances, origins, indexes, text, 0, 0, NULL, NULL);
    CHECK(initial.width == 0 && initial.height == 0);
}

int main(void) {
    CTFontRef font = CTFontCreateWithName(CFSTR("DejaVu Sans"), 16, NULL);
    CHECK(font != NULL);
    if (font != NULL) {
        testGlyphLookup(font);
        testCoverage(font);
        testTraits(font);
        testFallback(font);
        testShaping(font);
        CFRelease(font);
    }
    testBoldWeight();
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
