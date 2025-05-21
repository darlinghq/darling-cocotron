/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files(the "Software"), to deal in the
Software without restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGContext.h>
#import <CoreText/CTFontDescriptor.h>
#import <CoreText/CTParagraphStyle.h>
#import <CoreText/CoreTextExport.h>
#import <ATS/ATS.h>

typedef struct CF_BRIDGED_TYPE(id) KTFont *CTFontRef;

CORETEXT_EXPORT const CFStringRef kCTFontCopyrightNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontFamilyNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontSubFamilyNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontStyleNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontUniqueNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontFullNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontVersionNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontPostScriptNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontTrademarkNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontManufacturerNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontDesignerNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontDescriptionNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontVendorURLNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontDesignerURLNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontLicenseNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontLicenseURLNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontSampleTextNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontPostScriptCIDNameKey;

CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisIdentifierKey;
CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisMinimumValueKey;
CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisMaximumValueKey;
CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisDefaultValueKey;
CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontVariationAxisHiddenKey;

CORETEXT_EXPORT const CFStringRef kCTFontFeatureTypeIdentifierKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureTypeNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureTypeExclusiveKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureTypeSelectorsKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureSelectorIdentifierKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureSelectorNameKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureSelectorDefaultKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureSelectorSettingKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureSampleTextKey;
CORETEXT_EXPORT const CFStringRef kCTFontFeatureTooltipTextKey;

typedef enum CTFontUIFontType : uint32_t {
    kCTFontUIFontNone = (uint32_t)-1,
    kCTFontUIFontUser = 0,
    kCTFontUserFontType = 0, // Deprecated
    kCTFontUIFontUserFixedPitch = 1,
    kCTFontUserFixedPitchFontType = 1,
    kCTFontUIFontSystem = 2,
    kCTFontSystemFontType = 2, // Deprecated
    kCTFontUIFontEmphasizedSystem = 3,
    kCTFontEmphasizedSystemFontType = 3, // Deprecated
    kCTFontUIFontSmallSystem = 4,
    kCTFontSmallSystemFontType = 4, // Deprecated
    kCTFontUIFontSmallEmphasizedSystem = 5,
    kCTFontSmallEmphasizedSystemFontType = 5, // Deprecated
    kCTFontUIFontMiniSystem = 6,
    kCTFontMiniSystemFontType = 6, // Deprecated
    kCTFontUIFontMiniEmphasizedSystem = 7,
    kCTFontMiniEmphasizedSystemFontType = 7, // Deprecated
    kCTFontUIFontViews = 8,
    kCTFontViewsFontType = 8, // Deprecated
    kCTFontUIFontApplication = 9,
    kCTFontApplicationFontType = 9, // Deprecated
    kCTFontUIFontLabel = 10,
    kCTFontLabelFontType = 10, // Deprecated
    kCTFontUIFontMenuTitle = 11,
    kCTFontMenuTitleFontType = 11, // Deprecated
    kCTFontUIFontMenuItem = 12,
    kCTFontMenuItemFontType = 12, // Deprecated
    kCTFontUIFontMenuItemMark = 13,
    kCTFontMenuItemMarkFontType = 13, // Deprecated
    kCTFontUIFontMenuItemCmdKey = 14,
    kCTFontMenuItemCmdKeyFontType = 14, // Deprecated
    kCTFontUIFontWindowTitle = 15,
    kCTFontWindowTitleFontType = 15, // Deprecated
    kCTFontUIFontPushButton = 16,
    kCTFontPushButtonFontType = 16, // Deprecated
    kCTFontUIFontUtilityWindowTitle = 17,
    kCTFontUtilityWindowTitleFontType = 17, // Deprecated
    kCTFontUIFontAlertHeader = 18,
    kCTFontAlertHeaderFontType = 18, // Deprecated
    kCTFontUIFontSystemDetail = 19,
    kCTFontSystemDetailFontType = 19, // Deprecated
    kCTFontUIFontEmphasizedSystemDetail = 20,
    kCTFontEmphasizedSystemDetailFontType = 20, // Deprecated
    kCTFontUIFontToolbar = 21,
    kCTFontToolbarFontType = 21, // Deprecated
    kCTFontUIFontSmallToolbar = 22,
    kCTFontSmallToolbarFontType = 22, // Deprecated
    kCTFontUIFontMessage = 23,
    kCTFontMessageFontType = 23, // Deprecated
    kCTFontUIFontPalette = 24,
    kCTFontPaletteFontType = 24, // Deprecated
    kCTFontUIFontToolTip = 25,
    kCTFontToolTipFontType = 25, // Deprecated
    kCTFontUIFontControlContent = 26,
    kCTFontControlContentFontType = 26 // Deprecated
} CTFontUIFontType;

typedef CF_OPTIONS(uint32_t, CTFontTableOptions) {
    kCTFontTableOptionNoOptions        = 0,
    kCTFontTableOptionExcludeSynthetic = 1, // Deprecated
};

enum : unsigned int {
    kCTFontTableBASE = 'BASE',
    kCTFontTableCFF  = 'CFF ',
    kCTFontTableDSIG = 'DSIG',
    kCTFontTableEBDT = 'EBDT',
    kCTFontTableEBLC = 'EBLC',
    kCTFontTableEBSC = 'EBSC',
    kCTFontTableGDEF = 'GDEF',
    kCTFontTableGPOS = 'GPOS',
    kCTFontTableGSUB = 'GSUB',
    kCTFontTableJSTF = 'JSTF',
    kCTFontTableLTSH = 'LTSH',
    kCTFontTableOS2  = 'OS/2',
    kCTFontTablePCLT = 'PCLT',
    kCTFontTableVDMX = 'VDMX',
    kCTFontTableVORG = 'VORG',
    kCTFontTableZapf = 'Zapf',
    kCTFontTableAcnt = 'acnt',
    kCTFontTableAvar = 'avar',
    kCTFontTableBdat = 'bdat',
    kCTFontTableBhed = 'bhed',
    kCTFontTableBloc = 'bloc',
    kCTFontTableBsln = 'bsln',
    kCTFontTableCmap = 'cmap',
    kCTFontTableCvar = 'cvar',
    kCTFontTableCvt  = 'cvt ',
    kCTFontTableFdsc = 'fdsc',
    kCTFontTableFeat = 'feat',
    kCTFontTableFmtx = 'fmtx',
    kCTFontTableFpgm = 'fpgm',
    kCTFontTableFvar = 'fvar',
    kCTFontTableGasp = 'gasp',
    kCTFontTableGlyf = 'glyf',
    kCTFontTableGvar = 'gvar',
    kCTFontTableHdmx = 'hdmx',
    kCTFontTableHead = 'head',
    kCTFontTableHhea = 'hhea',
    kCTFontTableHmtx = 'hmtx',
    kCTFontTableHsty = 'hsty',
    kCTFontTableJust = 'just',
    kCTFontTableKern = 'kern',
    kCTFontTableKerx = 'kerx',
    kCTFontTableLcar = 'lcar',
    kCTFontTableLoca = 'loca',
    kCTFontTableMaxp = 'maxp',
    kCTFontTableMort = 'mort',
    kCTFontTableMorx = 'morx',
    kCTFontTableName = 'name',
    kCTFontTableOpbd = 'opbd',
    kCTFontTablePost = 'post',
    kCTFontTablePrep = 'prep',
    kCTFontTableProp = 'prop',
    kCTFontTableSbit = 'sbit',
    kCTFontTableSbix = 'sbix',
    kCTFontTableTrak = 'trak',
    kCTFontTableVhea = 'vhea',
    kCTFontTableVmtx = 'vmtx'
};
typedef FourCharCode CTFontTableTag;

typedef enum CTFontOptions : CFOptionFlags {
    kCTFontOptionsDefault = 0,
    kCTFontOptionsPreventAutoActivation = 1 << 0,
    kCTFontOptionsPreventAutoDownload = 1 << 1,
    kCTFontOptionsPreferSystemFont = 1 << 2,
} CTFontOptions;

CF_IMPLICIT_BRIDGING_ENABLED

CORETEXT_EXPORT CTFontRef CTFontCreateWithName(CFStringRef name, CGFloat size,
                                               const CGAffineTransform *matrix);
CORETEXT_EXPORT CTFontRef CTFontCreateWithNameAndOptions(
        CFStringRef name, CGFloat size, const CGAffineTransform *matrix,
        CTFontOptions options);
CORETEXT_EXPORT CTFontRef CTFontCreateWithFontDescriptor(
        CTFontDescriptorRef descriptor, CGFloat size,
        const CGAffineTransform *matrix);
CORETEXT_EXPORT CTFontRef CTFontCreateWithFontDescriptorAndOptions(
        CTFontDescriptorRef descriptor, CGFloat size,
        const CGAffineTransform *matrix, CTFontOptions options);
CORETEXT_EXPORT CTFontRef CTFontCreateUIFontForLanguage(
        CTFontUIFontType uiFontType, CGFloat size, CFStringRef language);
CORETEXT_EXPORT CTFontRef CTFontCreateCopyWithAttributes(
        CTFontRef font, CGFloat size, const CGAffineTransform *matrix,
        CTFontDescriptorRef attributes);
CORETEXT_EXPORT CTFontRef CTFontCreateCopyWithSymbolicTraits(CTFontRef font, CGFloat size, const CGAffineTransform *matrix, CTFontSymbolicTraits symTraitValue, CTFontSymbolicTraits symTraitMask);
CORETEXT_EXPORT CTFontRef CTFontCreateCopyWithFamily(CTFontRef font, CGFloat size, const CGAffineTransform *matrix, CFStringRef family);
CORETEXT_EXPORT CTFontRef CTFontCreateForString(CTFontRef currentFont, CFStringRef string, CFRange range);
CORETEXT_EXPORT CTFontRef CTFontCreateForStringWithLanguage(CTFontRef currentFont, CFStringRef string, CFRange range, CFStringRef language);

CORETEXT_EXPORT CTFontDescriptorRef CTFontCopyFontDescriptor(CTFontRef font);
CORETEXT_EXPORT CFTypeRef CTFontCopyAttribute(CTFontRef font, CFStringRef attribute);
CORETEXT_EXPORT CGFloat CTFontGetSize(CTFontRef self);
CORETEXT_EXPORT CGAffineTransform CTFontGetMatrix(CTFontRef font);
CORETEXT_EXPORT CTFontSymbolicTraits CTFontGetSymbolicTraits(CTFontRef font);

CORETEXT_EXPORT CFDictionaryRef CTFontCopyTraits(CTFontRef font);
CORETEXT_EXPORT CFArrayRef CTFontCopyDefaultCascadeListForLanguages(CTFontRef font, CFArrayRef languagePrefList);

CORETEXT_EXPORT CFStringRef CTFontCopyPostScriptName(CTFontRef font);
CORETEXT_EXPORT CFStringRef CTFontCopyFamilyName(CTFontRef font);
CORETEXT_EXPORT CFStringRef CTFontCopyFullName(CTFontRef self);
CORETEXT_EXPORT CFStringRef CTFontCopyDisplayName(CTFontRef font);
CORETEXT_EXPORT CFStringRef CTFontCopyName(CTFontRef font, CFStringRef nameKey);
CORETEXT_EXPORT CFStringRef CTFontCopyLocalizedName(CTFontRef font, CFStringRef nameKey, CFStringRef  _Nullable *actualLanguage);

CORETEXT_EXPORT CFCharacterSetRef CTFontCopyCharacterSet(CTFontRef font);
CORETEXT_EXPORT CFStringEncoding CTFontGetStringEncoding(CTFontRef font);
CORETEXT_EXPORT CFArrayRef CTFontCopySupportedLanguages(CTFontRef font);

CORETEXT_EXPORT CGFloat CTFontGetAscent(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetDescent(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetLeading(CTFontRef self);
CORETEXT_EXPORT unsigned int CTFontGetUnitsPerEm(CTFontRef font);
CORETEXT_EXPORT CFIndex CTFontGetGlyphCount(CTFontRef font);
CORETEXT_EXPORT CGRect CTFontGetBoundingBox(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetUnderlinePosition(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetUnderlineThickness(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetSlantAngle(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetCapHeight(CTFontRef self);
CORETEXT_EXPORT CGFloat CTFontGetXHeight(CTFontRef self);

CORETEXT_EXPORT CGPathRef CTFontCreatePathForGlyph(CTFontRef self,
                                                   CGGlyph glyph,
                                                   CGAffineTransform *xform);
CORETEXT_EXPORT CGGlyph CTFontGetGlyphWithName(CTFontRef font, CFStringRef glyphName);
CORETEXT_EXPORT CGRect CTFontGetBoundingRectsForGlyphs(CTFontRef font, CTFontOrientation orientation, const CGGlyph *glyphs, CGRect *boundingRects, CFIndex count);
CORETEXT_EXPORT double CTFontGetAdvancesForGlyphs(CTFontRef font, CTFontOrientation orientation,
                                                const CGGlyph *glyphs,
                                                CGSize *advances, CFIndex count);
CORETEXT_EXPORT CGRect CTFontGetOpticalBoundsForGlyphs(CTFontRef font, const CGGlyph *glyphs, CGRect *boundingRects, CFIndex count, CFOptionFlags options);
CORETEXT_EXPORT void CTFontGetVerticalTranslationsForGlyphs(CTFontRef font, const CGGlyph *glyphs, CGSize *translations, CFIndex count);

CORETEXT_EXPORT CFArrayRef CTFontCopyVariationAxes(CTFontRef font);
CORETEXT_EXPORT CFDictionaryRef CTFontCopyVariation(CTFontRef font);

CORETEXT_EXPORT CFArrayRef CTFontCopyFeatures(CTFontRef font);
CORETEXT_EXPORT CFArrayRef CTFontCopyFeatureSettings(CTFontRef font);

CORETEXT_EXPORT bool CTFontGetGlyphsForCharacters(CTFontRef font, const UniChar *characters, CGGlyph *glyphs, CFIndex count);
CORETEXT_EXPORT void CTFontDrawGlyphs(CTFontRef font, const CGGlyph *glyphs, const CGPoint *positions, size_t count, CGContextRef context);
CORETEXT_EXPORT CFIndex CTFontGetLigatureCaretPositions(CTFontRef font, CGGlyph glyph, CGFloat *positions, CFIndex maxPositions);

CORETEXT_EXPORT CGFontRef CTFontCopyGraphicsFont(
        CTFontRef font, CTFontDescriptorRef _Nullable *attributes);
CORETEXT_EXPORT CTFontRef CTFontCreateWithGraphicsFont(
        CGFontRef cgFont, CGFloat size, CGAffineTransform *xform,
        CTFontDescriptorRef attributes);

CORETEXT_EXPORT ATSFontRef CTFontGetPlatformFont(CTFontRef font, CTFontDescriptorRef  _Nullable *attributes); // Deprecated
CORETEXT_EXPORT CTFontRef CTFontCreateWithPlatformFont(ATSFontRef platformFont, CGFloat size, const CGAffineTransform *matrix, CTFontDescriptorRef attributes); // Deprecated
CORETEXT_EXPORT CTFontRef CTFontCreateWithQuickdrawInstance(ConstStr255Param name, int16_t identifier, uint8_t style, CGFloat size); // Deprecated

CORETEXT_EXPORT CFArrayRef CTFontCopyAvailableTables(CTFontRef font, CTFontTableOptions options);
CORETEXT_EXPORT CFDataRef CTFontCopyTable(CTFontRef font, CTFontTableTag table, CTFontTableOptions options);

CORETEXT_EXPORT CFTypeID CTFontGetTypeID(void);

CF_IMPLICIT_BRIDGING_DISABLED
