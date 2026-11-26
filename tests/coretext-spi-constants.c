/* Copyright (C) 2026 Lubos Dolezel */
/* CoreText constants that macOS exports but the SDK does not declare (and
 * kCTFontOpticalSizeAttribute, which CTFontDescriptor.h declares).
 *
 * - The weights equal the NSFontWeight values (read from AppKit's exported
 *   constants on macOS 26.7.3; single-precision values widened to CGFloat).
 * - The text style, design and text style attribute strings equal those of the
 *   AppKit/UIKit constants that name the same thing (read on macOS 26.7.3).
 * - Every other string, and the widths, were read from the exported constants
 *   on macOS 26.7.3; tests/src/private_constant_values.m checks their values,
 *   and this test that they are distinct and ordered. */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

/* Not in the SDK headers. */
extern const CGFloat kCTFontWeightUltraLight, kCTFontWeightThin, kCTFontWeightLight,
        kCTFontWeightRegular, kCTFontWeightMedium, kCTFontWeightSemibold, kCTFontWeightBold,
        kCTFontWeightHeavy, kCTFontWeightBlack;
extern const CGFloat kCTFontWidthUltraCompressed, kCTFontWidthExtraCompressed,
        kCTFontWidthExtraCondensed, kCTFontWidthCondensed, kCTFontWidthSemiCondensed,
        kCTFontWidthStandard, kCTFontWidthSemiExpanded, kCTFontWidthExpanded,
        kCTFontWidthExtraExpanded;
extern const CFStringRef kCTUIFontTextStyleTitle0, kCTUIFontTextStyleTitle1,
        kCTUIFontTextStyleTitle2, kCTUIFontTextStyleTitle3, kCTUIFontTextStyleTitle4,
        kCTUIFontTextStyleHeadline, kCTUIFontTextStyleSubhead, kCTUIFontTextStyleBody,
        kCTUIFontTextStyleFootnote, kCTUIFontTextStyleCaption1, kCTUIFontTextStyleCaption2,
        kCTUIFontTextStyleShortHeadline, kCTUIFontTextStyleShortBody,
        kCTUIFontTextStyleShortSubhead, kCTUIFontTextStyleShortFootnote,
        kCTUIFontTextStyleShortCaption1, kCTUIFontTextStyleTallBody;
extern const CFStringRef kCTFontUIFontDesignTrait, kCTFontUIFontDesignDefault,
        kCTFontUIFontDesignMonospaced, kCTFontUIFontDesignRounded, kCTFontUIFontDesignSerif;
extern const CFStringRef kCTFontDescriptorTextStyleAttribute, kCTFontContentSizeCategoryL;
extern const CFStringRef kCTFontCSSFamilySerif, kCTFontCSSFamilySansSerif,
        kCTFontCSSFamilyCursive, kCTFontCSSFamilyFantasy, kCTFontCSSFamilyMonospace;
extern const CFStringRef kCTFontOpticalSizeAttribute, kCTFontReferenceURLAttribute,
        kCTFontPostScriptNameAttribute, kCTFontUserInstalledAttribute,
        kCTFontFallbackOptionAttribute, kCTFontCSSWeightAttribute, kCTFontCSSWidthAttribute,
        kCTFontGradeTrait, kCTFontIgnoreLegibilityWeightAttribute, kCTFontSizeCategoryAttribute,
        kCTFontTrackAttribute, kCTFontUnscaledTrackingAttribute, kCTFontPaletteAttribute,
        kCTFontPaletteColorsAttribute, kCTFrameMaximumNumberOfLinesAttributeName;

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int isString(CFStringRef s, const char *expected) {
    char buf[128];
    return s != NULL && CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8) && strcmp(buf, expected) == 0;
}

int main(void) {
    /* observed values (through AppKit's NSFontWeight constants) */
    CHECK(kCTFontWeightUltraLight == (CGFloat) -0.8f);
    CHECK(kCTFontWeightThin == (CGFloat) -0.6f);
    CHECK(kCTFontWeightLight == (CGFloat) -0.4f);
    CHECK(kCTFontWeightRegular == 0);
    CHECK(kCTFontWeightMedium == (CGFloat) 0.23f);
    CHECK(kCTFontWeightSemibold == (CGFloat) 0.3f);
    CHECK(kCTFontWeightBold == (CGFloat) 0.4f);
    CHECK(kCTFontWeightHeavy == (CGFloat) 0.56f);
    CHECK(kCTFontWeightBlack == (CGFloat) 0.62f);

    /* widths: ordered from narrowest to widest, within -1 ... 1, standard 0 */
    const CGFloat widths[] = { kCTFontWidthUltraCompressed, kCTFontWidthExtraCompressed,
        kCTFontWidthExtraCondensed, kCTFontWidthCondensed, kCTFontWidthSemiCondensed,
        kCTFontWidthStandard, kCTFontWidthSemiExpanded, kCTFontWidthExpanded,
        kCTFontWidthExtraExpanded };
    for (int i = 0; i + 1 < 9; i++)
        CHECK(widths[i] < widths[i + 1]);
    CHECK(widths[0] >= -1 && widths[8] <= 1 && kCTFontWidthStandard == 0);

    /* observed strings (through the AppKit/UIKit constants of the same meaning) */
    CHECK(isString(kCTUIFontTextStyleTitle0, "UICTFontTextStyleTitle0"));
    CHECK(isString(kCTUIFontTextStyleTitle1, "UICTFontTextStyleTitle1"));
    CHECK(isString(kCTUIFontTextStyleTitle2, "UICTFontTextStyleTitle2"));
    CHECK(isString(kCTUIFontTextStyleTitle3, "UICTFontTextStyleTitle3"));
    CHECK(isString(kCTUIFontTextStyleHeadline, "UICTFontTextStyleHeadline"));
    CHECK(isString(kCTUIFontTextStyleSubhead, "UICTFontTextStyleSubhead"));
    CHECK(isString(kCTUIFontTextStyleBody, "UICTFontTextStyleBody"));
    CHECK(isString(kCTUIFontTextStyleFootnote, "UICTFontTextStyleFootnote"));
    CHECK(isString(kCTUIFontTextStyleCaption1, "UICTFontTextStyleCaption1"));
    CHECK(isString(kCTUIFontTextStyleCaption2, "UICTFontTextStyleCaption2"));
    CHECK(isString(kCTFontUIFontDesignTrait, "NSCTFontUIFontDesignTrait"));
    CHECK(isString(kCTFontUIFontDesignDefault, "NSCTFontUIFontDesignDefault"));
    CHECK(isString(kCTFontUIFontDesignMonospaced, "NSCTFontUIFontDesignMonospaced"));
    CHECK(isString(kCTFontUIFontDesignRounded, "NSCTFontUIFontDesignRounded"));
    CHECK(isString(kCTFontUIFontDesignSerif, "NSCTFontUIFontDesignSerif"));
    CHECK(isString(kCTFontDescriptorTextStyleAttribute, "NSCTFontUIUsageAttribute"));

    /* the other strings: present, and distinct from each other and from the
     * documented attribute names */
    CFStringRef names[] = {
        kCTUIFontTextStyleTitle0, kCTUIFontTextStyleTitle1, kCTUIFontTextStyleTitle2,
        kCTUIFontTextStyleTitle3, kCTUIFontTextStyleTitle4, kCTUIFontTextStyleHeadline,
        kCTUIFontTextStyleSubhead, kCTUIFontTextStyleBody, kCTUIFontTextStyleFootnote,
        kCTUIFontTextStyleCaption1, kCTUIFontTextStyleCaption2, kCTUIFontTextStyleShortHeadline,
        kCTUIFontTextStyleShortBody, kCTUIFontTextStyleShortSubhead,
        kCTUIFontTextStyleShortFootnote, kCTUIFontTextStyleShortCaption1,
        kCTUIFontTextStyleTallBody, kCTFontUIFontDesignTrait, kCTFontUIFontDesignDefault,
        kCTFontUIFontDesignMonospaced, kCTFontUIFontDesignRounded, kCTFontUIFontDesignSerif,
        kCTFontDescriptorTextStyleAttribute, kCTFontContentSizeCategoryL,
        kCTFontCSSFamilySerif, kCTFontCSSFamilySansSerif, kCTFontCSSFamilyCursive,
        kCTFontCSSFamilyFantasy, kCTFontCSSFamilyMonospace, kCTFontOpticalSizeAttribute,
        kCTFontReferenceURLAttribute, kCTFontPostScriptNameAttribute,
        kCTFontUserInstalledAttribute, kCTFontFallbackOptionAttribute,
        kCTFontCSSWeightAttribute, kCTFontCSSWidthAttribute, kCTFontGradeTrait,
        kCTFontIgnoreLegibilityWeightAttribute, kCTFontSizeCategoryAttribute,
        kCTFontTrackAttribute, kCTFontUnscaledTrackingAttribute, kCTFontPaletteAttribute,
        kCTFontPaletteColorsAttribute, kCTFrameMaximumNumberOfLinesAttributeName,
        kCTFontNameAttribute, kCTFontURLAttribute, kCTFontFamilyNameAttribute,
        kCTFontSizeAttribute, kCTFontTraitsAttribute, kCTFontWeightTrait, kCTFontWidthTrait,
    };
    const int count = sizeof(names) / sizeof(names[0]);
    for (int i = 0; i < count; i++) {
        CHECK(names[i] != NULL && CFGetTypeID(names[i]) == CFStringGetTypeID() &&
              CFStringGetLength(names[i]) > 0);
        for (int j = i + 1; j < count; j++)
            if (CFEqual(names[i], names[j])) {
                fprintf(stderr, "FAIL: constants %d and %d are equal\n", i, j);
                failures++;
            }
    }

    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
