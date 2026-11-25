/* Copyright (C) 2026 Lubos Dolezel */
/* Public CoreText string attribute names and the CTFontManager error constants.
 * The string values were read on macOS 26.7.3 and 10.14.4 (black-box
 * observation of the exported constants). */
#include <CoreText/CoreText.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int isString(CFStringRef s, const char *expected) {
    char buf[128];
    return s != NULL && CFStringGetCString(s, buf, sizeof buf, kCFStringEncodingUTF8) && strcmp(buf, expected) == 0;
}

int main(void) {
    CHECK(isString(kCTTrackingAttributeName, "CTTracking"));
    CHECK(isString(kCTHorizontalInVerticalFormsAttributeName, "CTHorizontalInVerticalForms"));
    CHECK(isString(kCTStrokeColorAttributeName, "CTStrokeColor"));
    CHECK(isString(kCTWritingDirectionAttributeName, "NSWritingDirection"));
    CHECK(isString(kCTTabColumnTerminatorsAttributeName, "NSTabColumnTerminatorsAttributeName"));
    /* documented as the same attribute as AppKit's NSVerticalGlyphFormAttributeName, whose string was read on macOS */
    CHECK(isString(kCTVerticalFormsAttributeName, "CTVerticalForms"));
    /* declared; its string has not been checked on macOS */
    CHECK(kCTTypesetterOptionForcedEmbeddingLevel != NULL && !CFEqual(kCTTypesetterOptionForcedEmbeddingLevel, kCTVerticalFormsAttributeName));
    /* the deprecated trait names are the traits', and the SVG table's tag is its OpenType tag */
    CHECK(kCTFontColorGlyphsTrait == kCTFontTraitColorGlyphs && kCTFontCompositeTrait == kCTFontTraitComposite);
    CHECK(kCTFontTableSVG == 'SVG ');

    /* distinct from each other and usable as attribute keys */
    CFStringRef names[] = {kCTTrackingAttributeName, kCTHorizontalInVerticalFormsAttributeName,
        kCTStrokeColorAttributeName, kCTWritingDirectionAttributeName, kCTTabColumnTerminatorsAttributeName};
    for (int i = 0; i < 5; i++)
        for (int j = i + 1; j < 5; j++)
            CHECK(!CFEqual(names[i], names[j]));

    /* declared too; their strings have not been checked on macOS */
    CHECK(kCTStrokeWidthAttributeName != NULL && !CFEqual(kCTStrokeWidthAttributeName, kCTStrokeColorAttributeName));
    CHECK(kCTLanguageAttributeName != NULL && !CFEqual(kCTLanguageAttributeName, kCTWritingDirectionAttributeName));

    CHECK(isString(kCTFontManagerErrorDomain, "com.apple.CoreText.CTFontManagerErrorDomain"));
    CHECK(isString(kCTFontManagerErrorFontURLsKey, "CTFontManagerErrorFontURLs"));
    CHECK(kCTFontManagerErrorFileNotFound == 101 && kCTFontManagerErrorAlreadyRegistered == 105);
    CHECK(kCTFontManagerErrorNotRegistered == 201 && kCTFontManagerErrorSystemRequired == 203);

    if (failures == 0) puts("PASS");
    return failures != 0;
}
