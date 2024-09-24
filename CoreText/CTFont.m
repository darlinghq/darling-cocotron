/* Copyright (c) 2008 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreText/CTFont.h>
#import <CoreText/CoreText.h>
#import <CoreText/KTFont.h>

const CFStringRef kCTFontCopyrightNameKey = @"CTFontCopyrightName";
const CFStringRef kCTFontFamilyNameKey = @"CTFontFamilyName";
const CFStringRef kCTFontSubFamilyNameKey = @"CTFontSubFamilyName";
const CFStringRef kCTFontStyleNameKey = @"CTFontSubFamilyName";
const CFStringRef kCTFontUniqueNameKey = @"CTFontUniqueName";
const CFStringRef kCTFontFullNameKey = @"CTFontFullName";
const CFStringRef kCTFontVersionNameKey = @"CTFontVersionName";
const CFStringRef kCTFontPostScriptNameKey = @"CTFontPostScriptName";
const CFStringRef kCTFontTrademarkNameKey = @"CTFontTrademarkName";
const CFStringRef kCTFontManufacturerNameKey = @"CTFontManufacturerName";
const CFStringRef kCTFontDesignerNameKey = @"CTFontDesignerName";
const CFStringRef kCTFontDescriptionNameKey = @"CTFontDescriptionName";
const CFStringRef kCTFontVendorURLNameKey = @"CTFontVendorURLName";
const CFStringRef kCTFontDesignerURLNameKey = @"CTFontDesignerURLName";
const CFStringRef kCTFontLicenseNameKey = @"CTFontLicenseNameName";
const CFStringRef kCTFontLicenseURLNameKey = @"CTFontLicenseURLName";
const CFStringRef kCTFontSampleTextNameKey = @"CTFontSampleTextName";
const CFStringRef kCTFontPostScriptCIDNameKey = @"CTFontPostScriptCIDName";

const CFStringRef kCTFontVariationAxisIdentifierKey = @"CTFontVariationAxisIdentifier";
const CFStringRef kCTFontVariationAxisMinimumValueKey = @"CTFontVariationAxisMinimumValue";
const CFStringRef kCTFontVariationAxisMaximumValueKey = @"CTFontVariationAxisMaximumValue";
const CFStringRef kCTFontVariationAxisDefaultValueKey = @"CTFontVariationAxisDefaultValue";
const CFStringRef kCTFontVariationAxisNameKey = @"CTFontVariationAxisName";
const CFStringRef kCTFontVariationAxisHiddenKey = @"CTFontVariationAxisHidden";

const CFStringRef kCTFontFeatureTypeIdentifierKey = @"CTFontFeatureTypeIdentifierKey";
const CFStringRef kCTFontFeatureTypeNameKey = @"CTFontFeatureTypeName";
const CFStringRef kCTFontFeatureTypeExclusiveKey = @"CTFontFeatureTypeExclusive";
const CFStringRef kCTFontFeatureTypeSelectorsKey = @"CTFontFeatureTypeSelectors";
const CFStringRef kCTFontFeatureSelectorIdentifierKey = @"CTFontFeatureSelectorIdentifierKey";
const CFStringRef kCTFontFeatureSelectorNameKey = @"CTFontFeatureSelectorName";
const CFStringRef kCTFontFeatureSelectorDefaultKey = @"CTFontFeatureSelectorDefault";
const CFStringRef kCTFontFeatureSelectorSettingKey = @"CTFontFeatureSelectorSetting";
const CFStringRef kCTFontFeatureSampleTextKey = @"CTFontFeatureSampleText";
const CFStringRef kCTFontFeatureTooltipTextKey = @"CTFontFeatureTooltipText";

CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size, const CGAffineTransform *matrix)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithNameAndOptions(CFStringRef name, CGFloat size,
                                         const CGAffineTransform *matrix,
                                         CTFontOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithFontDescriptor(CTFontDescriptorRef descriptor, CGFloat size,
                                         const CGAffineTransform *matrix)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithFontDescriptorAndOptions(CTFontDescriptorRef descriptor, CGFloat size,
                                                   const CGAffineTransform *matrix,
                                                   CTFontOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateUIFontForLanguage(CTFontUIFontType uiFontType,
                                        CGFloat size, CFStringRef language)
{
    return [[KTFont alloc] initWithUIFontType: uiFontType
                                         size: size
                                     language: language];
}

CTFontRef CTFontCreateCopyWithAttributes(CTFontRef font, CGFloat size,
                                         const CGAffineTransform *matrix,
                                         CTFontDescriptorRef attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size,
                                             const CGAffineTransform *matrix,
                                             CTFontSymbolicTraits symTraitValue, 
                                             CTFontSymbolicTraits symTraitMask)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size,
                                     const CGAffineTransform *matrix, CFStringRef family)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateForString(CTFontRef currentFont, CFStringRef string, CFRange range)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateForStringWithLanguage(CTFontRef currentFont, CFStringRef string,
                                            CFRange range, CFStringRef language)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CGFloat CTFontGetSize(CTFontRef self) {
    return [self pointSize];
}

CGAffineTransform CTFontGetMatrix(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFDictionaryRef CTFontCopyTraits(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef languagePrefList)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef CTFontCopyPostScriptName(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef CTFontCopyFamilyName(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef CTFontCopyFullName(CTFontRef self) {
    return [self copyName];
}

CFStringRef CTFontCopyDisplayName(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef _Nullable CTFontCopyName(CTFontRef font, CFStringRef nameKey)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey,
                                    CFStringRef  _Nullable *actualLanguage)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringEncoding CTFontGetStringEncoding(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopySupportedLanguages(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CGFloat CTFontGetAscent(CTFontRef self) {
    return [self ascender];
}

CGFloat CTFontGetDescent(CTFontRef self) {
    return [self descender];
}

CGFloat CTFontGetLeading(CTFontRef self) {
    return [self leading];
}

unsigned int CTFontGetUnitsPerEm(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

size_t CTFontGetGlyphCount(CTFontRef self) {
    return [self numberOfGlyphs];
}

CGRect CTFontGetBoundingBox(CTFontRef self) {
    return [self boundingRect];
}

CGFloat CTFontGetUnderlinePosition(CTFontRef self) {
    return [self underlinePosition];
}

CGFloat CTFontGetUnderlineThickness(CTFontRef self) {
    return [self underlineThickness];
}

CGFloat CTFontGetSlantAngle(CTFontRef self) {
    return [self italicAngle];
}

CGFloat CTFontGetCapHeight(CTFontRef self) {
    return [self capHeight];
}

CGFloat CTFontGetXHeight(CTFontRef self) {
    return [self xHeight];
}

CGPathRef CTFontCreatePathForGlyph(CTFontRef self, CGGlyph glyph,
                                   CGAffineTransform *xform)
{
    return (CGPathRef) [self createPathForGlyph: glyph transform: xform];
}

CGGlyph CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                       const CGGlyph *glyphs, CGRect *boundingRects,
                                       CFIndex count)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

void CTFontGetAdvancesForGlyphs(CTFontRef self, int orientation,
                                const CGGlyph *glyphs, CGSize *advances,
                                size_t count)
{
    [self getAdvancements: advances forGlyphs: glyphs count: count];
}

CGRect CTFontGetOpticalBoundsForGlyphs(CTFontRef font, const CGGlyph *glyphs,
                                       CGRect *boundingRects, CFIndex count,
                                       CFOptionFlags options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

void CTFontGetVerticalTranslationsForGlyphs(CTFontRef font, const CGGlyph *glyphs,
                                            CGSize *translations, CFIndex count)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

CFArrayRef CTFontCopyVariationAxes(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFDictionaryRef CTFontCopyVariation(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyFeatures(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyFeatureSettings(CTFontRef font)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

bool CTFontGetGlyphsForCharacters(CTFontRef self, const UniChar *characters,
                                  CGGlyph *glyphs, size_t count)
{
    [self getGlyphs: glyphs forCharacters: characters length: count];
    // FIXME: change getGlyphs: to return a BOOL
    return YES;
}

void CTFontDrawGlyphs(CTFontRef font, const CGGlyph *glyphs, const CGPoint *positions,
                      size_t count, CGContextRef context)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

CFIndex CTFontGetLigatureCaretPositions(CTFontRef font, CGGlyph glyph, CGFloat *positions,
                                        CFIndex maxPositions)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CGFontRef CTFontCopyGraphicsFont(CTFontRef font, CTFontDescriptorRef _Nullable *attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef
CTFontCreateWithGraphicsFont(CGFontRef cgFont, CGFloat size,
                             CGAffineTransform *xform,
                             /* CTFontDescriptorRef */ void *attributes)
{
    return [[KTFont alloc] initWithFont: cgFont size: size];
}

ATSFontRef CTFontGetPlatformFont(CTFontRef font, CTFontDescriptorRef  _Nullable *attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithPlatformFont(ATSFontRef platformFont, CGFloat size,
                                       const CGAffineTransform *matrix,
                                       CTFontDescriptorRef attributes)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CTFontRef CTFontCreateWithQuickdrawInstance(ConstStr255Param name, int16_t identifier,
                                            uint8_t style, CGFloat size)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFTypeID CTFontGetTypeID(void)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}
