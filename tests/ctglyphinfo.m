/*
 Copyright (C) 2026 Lubos Dolezel

 This file is part of Darling.

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// CTGlyphInfo creation and getters, CTFontGetGlyphWithName and the
// CTFontCopyGraphicsFont attributes out-parameter.
#import <CoreText/CoreText.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

// Expected values come from probing macOS 26.7.3 and 10.14.4 (see
// MAC-EVIDENCE.md section MC). Where the two differ (lookups of the glyph
// name or index in the font, identity-mapping identifiers), the permissive
// result is required.
int main(void)
{
    CTGlyphInfoRef info = CTGlyphInfoCreateWithCharacterIdentifier(
        1234, kCTCharacterCollectionAdobeJapan1, CFSTR("x"));
    CHECK(info != NULL);
    CHECK(CFGetTypeID(info) == CTGlyphInfoGetTypeID());
    CHECK(CTGlyphInfoGetCharacterIdentifier(info) == 1234);
    CHECK(CTGlyphInfoGetCharacterCollection(info) == kCTCharacterCollectionAdobeJapan1);
    CHECK(CTGlyphInfoGetGlyphName(info) == NULL);
    CHECK(CTGlyphInfoGetGlyph(info) == 0);

    CTGlyphInfoRef same = CTGlyphInfoCreateWithCharacterIdentifier(
        1234, kCTCharacterCollectionAdobeJapan1, CFSTR("x"));
    CTGlyphInfoRef otherBase = CTGlyphInfoCreateWithCharacterIdentifier(
        1234, kCTCharacterCollectionAdobeJapan1, CFSTR("y"));
    CHECK(CFEqual(info, same));
    CHECK(!CFEqual(info, otherBase));
    CFRelease(same);
    CFRelease(otherBase);
    CFRelease(info);

    info = CTGlyphInfoCreateWithCharacterIdentifier(
        77, kCTCharacterCollectionIdentityMapping, CFSTR("x"));
    CHECK(info != NULL);
    CHECK(CTGlyphInfoGetCharacterIdentifier(info) == 77);
    CHECK(CTGlyphInfoGetCharacterCollection(info) == kCTCharacterCollectionIdentityMapping);
    CFRelease(info);
    info = CTGlyphInfoCreateWithCharacterIdentifier(
        0, kCTCharacterCollectionAdobeKorea1, CFSTR("x"));
    CHECK(info != NULL);
    CHECK(CTGlyphInfoGetCharacterIdentifier(info) == 0);
    CHECK(CTGlyphInfoGetCharacterCollection(info) == kCTCharacterCollectionAdobeKorea1);
    CFRelease(info);
    CHECK(CTGlyphInfoCreateWithCharacterIdentifier(1, kCTCharacterCollectionAdobeGB1, NULL) == NULL);
    CHECK(CTGlyphInfoCreateWithCharacterIdentifier(1, (CTCharacterCollection) 99, CFSTR("x")) == NULL);

    CTFontRef font = CTFontCreateWithName(CFSTR("Helvetica"), 18, NULL);
    CHECK(font != NULL);

    CGGlyph glyph = CTFontGetGlyphWithName(font, CFSTR("A"));
    CHECK(glyph != 0);
    CHECK(CTFontGetGlyphWithName(font, CFSTR("no-such-glyph-name")) == 0);
    CHECK(CTFontGetGlyphWithName(font, NULL) == 0);
    CHECK(CTFontGetGlyphWithName(NULL, CFSTR("A")) == 0);

    info = CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, CFSTR("c"));
    CHECK(info != NULL);
    CHECK(CFGetTypeID(info) == CTGlyphInfoGetTypeID());
    CHECK(CFEqual(CTGlyphInfoGetGlyphName(info), CFSTR("copyright")));
    CHECK(CTGlyphInfoGetGlyph(info) == 0);
    CHECK(CTGlyphInfoGetCharacterIdentifier(info) == 0);
    CHECK(CTGlyphInfoGetCharacterCollection(info) == kCTCharacterCollectionIdentityMapping);
    same = CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, CFSTR("c"));
    CHECK(CFEqual(info, same));
    CFRelease(same);
    CTGlyphInfoRef differentBase = CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, CFSTR("d"));
    CHECK(!CFEqual(info, differentBase));
    CFRelease(differentBase);
    CFRelease(info);
    // An empty base string is accepted; NULL arguments are not.
    info = CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, CFSTR(""));
    CHECK(info != NULL);
    CFRelease(info);
    CHECK(CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, NULL) == NULL);
    CHECK(CTGlyphInfoCreateWithGlyphName(NULL, font, CFSTR("c")) == NULL);
    CHECK(CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), NULL, CFSTR("c")) == NULL);

    info = CTGlyphInfoCreateWithGlyph(glyph, font, CFSTR("A"));
    CHECK(info != NULL);
    CHECK(CTGlyphInfoGetGlyph(info) == glyph);
    CHECK(CTGlyphInfoGetGlyphName(info) == NULL);
    CHECK(CTGlyphInfoGetCharacterIdentifier(info) == 0);
    CHECK(CTGlyphInfoGetCharacterCollection(info) == kCTCharacterCollectionIdentityMapping);
    same = CTGlyphInfoCreateWithGlyph(glyph, font, CFSTR("A"));
    CHECK(CFEqual(info, same));
    CFRelease(same);
    CTGlyphInfoRef nameInfo = CTGlyphInfoCreateWithGlyphName(CFSTR("A"), font, CFSTR("A"));
    CHECK(!CFEqual(info, nameInfo));
    CFRelease(nameInfo);
    CTFontRef bigger = CTFontCreateWithName(CFSTR("Helvetica"), 36, NULL);
    CTGlyphInfoRef otherFont = CTGlyphInfoCreateWithGlyph(glyph, bigger, CFSTR("A"));
    CHECK(!CFEqual(info, otherFont));
    CFRelease(otherFont);
    CFRelease(bigger);
    CFRelease(info);
    CHECK(CTGlyphInfoCreateWithGlyph(glyph, NULL, CFSTR("A")) == NULL);
    CHECK(CTGlyphInfoCreateWithGlyph(glyph, font, NULL) == NULL);

    // The glyph info round-trips through an attributed string under its key.
    CHECK(CFEqual(kCTGlyphInfoAttributeName, CFSTR("NSGlyphInfo")));
    info = CTGlyphInfoCreateWithGlyphName(CFSTR("copyright"), font, CFSTR("c"));
    CFMutableAttributedStringRef text = CFAttributedStringCreateMutable(NULL, 0);
    CFAttributedStringReplaceString(text, CFRangeMake(0, 0), CFSTR("c"));
    CFAttributedStringSetAttribute(text, CFRangeMake(0, 1), kCTGlyphInfoAttributeName, info);
    CHECK(CFAttributedStringGetAttribute(text, 0, kCTGlyphInfoAttributeName, NULL) == info);
    CFRelease(text);
    CFRelease(info);

    CGFontRef graphics = CTFontCopyGraphicsFont(font, NULL);
    CHECK(graphics != NULL);
    CGFontRelease(graphics);
    CTFontDescriptorRef attributes = (CTFontDescriptorRef)0x1;
    graphics = CTFontCopyGraphicsFont(font, &attributes);
    CHECK(graphics != NULL);
    CHECK(attributes == NULL || CFGetTypeID(attributes) == CTFontDescriptorGetTypeID());
    CGFontRelease(graphics);

    CHECK(kCTGlyphInfoAttributeName != NULL);
    CFRelease(font);
    return 0;
}
