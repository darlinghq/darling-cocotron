/* Copyright (C) 2026 Lubos Dolezel */
#import <CoreText/CTFont.h>
#import <CoreText/CTFontDescriptor.h>

// Exported by CoreText on macOS but not declared in the SDK headers. Not
// installed; for callers inside the tree and tests that declare it themselves.
// The names and signatures are those callers bind to (WebKit's PAL SPI
// declarations, BSD licensed, list them).

// Draws glyphs starting at the context's text position, using the font and
// size of the CTFont (which stay set in the context), and advances the text
// position by the advances.
CORETEXT_EXPORT void CTFontDrawGlyphsWithAdvances(CTFontRef font, const CGGlyph *glyphs,
                                                  const CGSize *advances, size_t count,
                                                  CGContextRef context);

// Whether text in this font is antialiased.
CORETEXT_EXPORT bool CTFontShouldAntiAlias(CTFontRef font);

// Whether the descriptor describes one of the system UI fonts: a font made by
// CTFontCreateUIFontForLanguage() for any UI font type except the user and the
// user fixed-pitch types, or a copy of the descriptor of such a font. A
// descriptor made from a font name or from attributes is not one, whatever the
// name. NULL gives false.
CORETEXT_EXPORT bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef descriptor);

// Options of CTFontShapeGlyphs().
typedef CF_OPTIONS(CFOptionFlags, CTFontShapeOptions) {
    kCTFontShapeWithKerning = (1 << 0),
    kCTFontShapeWithClusterComposition = (1 << 1),
    kCTFontShapeRightToLeft = (1 << 2),
};

// Options a descriptor is made with (CTFontDescriptorCreateWithAttributesAndOptions()).
typedef CF_OPTIONS(uint32_t, CTFontDescriptorOptions) {
    kCTFontDescriptorOptionSystemUIFont = 1 << 1,
    kCTFontDescriptorOptionPreferAppleSystemFont = kCTFontOptionsPreferSystemFont,
};

// Which fonts a fallback font may come from.
typedef CF_OPTIONS(CFOptionFlags, CTFontFallbackOption) {
    kCTFontFallbackOptionNone = 0,
    kCTFontFallbackOptionSystem = 1 << 0,
    kCTFontFallbackOptionUserInstalled = 1 << 1,
    kCTFontFallbackOptionDefault = kCTFontFallbackOptionSystem | kCTFontFallbackOptionUserInstalled,
};

// The platform whose text style metrics CTFontDescriptorGetTextStyleSize() reports.
typedef CF_ENUM(uint32_t, CTFontTextStylePlatform) {
    kCTFontTextStylePlatformDefault = (CTFontTextStylePlatform) -1,
    kCTFontTextStylePlatformPhone = 0,
    kCTFontTextStylePlatformWatch = 1,
    kCTFontTextStylePlatformTV = 2,
    kCTFontTextStylePlatformMac = 3,
    kCTFontTextStylePlatformMacTouchBar = 4,
    kCTFontTextStylePlatformVision = 5,
    kCTFontTextStylePlatformVisionLegacy = 6,
};

// Descriptor attributes and traits.
CORETEXT_EXPORT const CFStringRef kCTFontReferenceURLAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontPostScriptNameAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontUserInstalledAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontFallbackOptionAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontCSSWeightAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontCSSWidthAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontDescriptorTextStyleAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontGradeTrait;
CORETEXT_EXPORT const CFStringRef kCTFontIgnoreLegibilityWeightAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontSizeCategoryAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontTrackAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontUnscaledTrackingAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontPaletteAttribute;
CORETEXT_EXPORT const CFStringRef kCTFontPaletteColorsAttribute;

// The generic CSS families CTFontDescriptorCreateForCSSFamily() takes.
CORETEXT_EXPORT const CFStringRef kCTFontCSSFamilySerif;
CORETEXT_EXPORT const CFStringRef kCTFontCSSFamilySansSerif;
CORETEXT_EXPORT const CFStringRef kCTFontCSSFamilyCursive;
CORETEXT_EXPORT const CFStringRef kCTFontCSSFamilyFantasy;
CORETEXT_EXPORT const CFStringRef kCTFontCSSFamilyMonospace;

// The designs of the system UI font (the values of kCTFontUIFontDesignTrait).
CORETEXT_EXPORT const CFStringRef kCTFontUIFontDesignTrait;
CORETEXT_EXPORT const CFStringRef kCTFontUIFontDesignDefault;
CORETEXT_EXPORT const CFStringRef kCTFontUIFontDesignMonospaced;
CORETEXT_EXPORT const CFStringRef kCTFontUIFontDesignRounded;
CORETEXT_EXPORT const CFStringRef kCTFontUIFontDesignSerif;

// Text styles.
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTitle0;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTitle1;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTitle2;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTitle3;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTitle4;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleHeadline;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleSubhead;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleBody;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleFootnote;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleCaption1;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleCaption2;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleShortHeadline;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleShortBody;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleShortSubhead;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleShortFootnote;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleShortCaption1;
CORETEXT_EXPORT const CFStringRef kCTUIFontTextStyleTallBody;

// Content size categories.
CORETEXT_EXPORT const CFStringRef kCTFontContentSizeCategoryL;

// Weights (the scale of kCTFontWeightTrait).
CORETEXT_EXPORT const CGFloat kCTFontWeightUltraLight;
CORETEXT_EXPORT const CGFloat kCTFontWeightThin;
CORETEXT_EXPORT const CGFloat kCTFontWeightLight;
CORETEXT_EXPORT const CGFloat kCTFontWeightRegular;
CORETEXT_EXPORT const CGFloat kCTFontWeightMedium;
CORETEXT_EXPORT const CGFloat kCTFontWeightSemibold;
CORETEXT_EXPORT const CGFloat kCTFontWeightBold;
CORETEXT_EXPORT const CGFloat kCTFontWeightHeavy;
CORETEXT_EXPORT const CGFloat kCTFontWeightBlack;

// Widths (the scale of kCTFontWidthTrait).
CORETEXT_EXPORT const CGFloat kCTFontWidthUltraCompressed;
CORETEXT_EXPORT const CGFloat kCTFontWidthExtraCompressed;
CORETEXT_EXPORT const CGFloat kCTFontWidthExtraCondensed;
CORETEXT_EXPORT const CGFloat kCTFontWidthCondensed;
CORETEXT_EXPORT const CGFloat kCTFontWidthSemiCondensed;
CORETEXT_EXPORT const CGFloat kCTFontWidthStandard;
CORETEXT_EXPORT const CGFloat kCTFontWidthSemiExpanded;
CORETEXT_EXPORT const CGFloat kCTFontWidthExpanded;
CORETEXT_EXPORT const CGFloat kCTFontWidthExtraExpanded;

// Descriptors.

// The descriptor of the font CTFontCreateUIFontForLanguage() makes for the
// type, size and language. NULL for a type that has no font.
CORETEXT_EXPORT CTFontDescriptorRef CTFontDescriptorCreateForUIType(CTFontUIFontType uiType,
                                                                    CGFloat size,
                                                                    CFStringRef language);

// The descriptor of the system UI font at the size and weight of a text
// style, which it carries as kCTFontDescriptorTextStyleAttribute. NULL for a
// style that is not one of the kCTUIFontTextStyle values.
CORETEXT_EXPORT CTFontDescriptorRef CTFontDescriptorCreateWithTextStyle(CFStringRef style,
                                                                        CFStringRef sizeCategory,
                                                                        CFStringRef language);

// The point size of a text style, and optionally its weight (the scale of
// kCTFontWeightTrait) and line spacing (the line height in points). 0 for a
// style that is not known; the outputs are then left alone.
CORETEXT_EXPORT CGFloat CTFontDescriptorGetTextStyleSize(CFStringRef style, CFTypeRef sizeCategory,
                                                         CTFontTextStylePlatform platform,
                                                         CGFloat *weight, CGFloat *lineSpacing);

// The descriptor of the installed face a generic CSS family (one of the
// kCTFontCSSFamily values) resolves to. NULL for any other family name.
CORETEXT_EXPORT CTFontDescriptorRef CTFontDescriptorCreateForCSSFamily(CFStringRef cssFamily,
                                                                       CFStringRef language);

// A descriptor of a face that is always installed, the last font to fall back to.
CORETEXT_EXPORT CTFontDescriptorRef CTFontDescriptorCreateLastResort(void);

// Like CTFontDescriptorCreateWithAttributes(), with options that
// CTFontDescriptorGetOptions() reports back.
CORETEXT_EXPORT CTFontDescriptorRef CTFontDescriptorCreateWithAttributesAndOptions(
        CFDictionaryRef attributes, CTFontDescriptorOptions options);

// The options of a descriptor; 0 for NULL.
CORETEXT_EXPORT CTFontDescriptorOptions CTFontDescriptorGetOptions(CTFontDescriptorRef descriptor);

// Fonts.

// Whether the font is a system UI font, in the sense of
// CTFontDescriptorIsSystemUIFont(). NULL gives false.
CORETEXT_EXPORT bool CTFontIsSystemUIFont(CTFontRef font);

// The UI font type the font was made for by CTFontCreateUIFontForLanguage()
// (directly or through a descriptor of such a font); kCTFontUIFontNone for any
// other font and for NULL.
CORETEXT_EXPORT CTFontUIFontType CTFontGetUIFontType(CTFontRef font);

// Whether the font is Apple Color Emoji.
CORETEXT_EXPORT bool CTFontIsAppleColorEmoji(CTFontRef font);

// The symbolic traits of the face itself (for Darling, every font is a face).
CORETEXT_EXPORT CTFontSymbolicTraits CTFontGetPhysicalSymbolicTraits(CTFontRef font);

// A font for the start of the UTF-16 text: the current font when it covers the
// first character, else a fallback font. *coveredLength (optional) receives how
// many UTF-16 units from the start the result covers.
CORETEXT_EXPORT CTFontRef CTFontCreateForCharactersWithLanguageAndOption(
        CTFontRef currentFont, const UTF16Char *characters, CFIndex length,
        CFStringRef language, CTFontFallbackOption option, CFIndex *coveredLength);

// The glyphs of the characters range.location ..< range.location +
// range.length (UTF-16 code units), one per character. Returns whether every
// character has a glyph.
CORETEXT_EXPORT bool CTFontGetGlyphsForCharacterRange(CTFontRef font, CGGlyph glyphs[], CFRange range);

// Like CTFontGetGlyphsForCharacters(), with the glyphs for vertical text.
CORETEXT_EXPORT bool CTFontGetVerticalGlyphsForCharacters(CTFontRef font, const UniChar characters[],
                                                          CGGlyph glyphs[], CFIndex count);

// The glyphs whose colour form the font has, as a bit vector indexed by glyph;
// NULL when the font has none.
CORETEXT_EXPORT CFBitVectorRef CTFontCopyColorGlyphCoverage(CTFontRef font);

// The glyphs a feature setting (a dictionary of the kind
// kCTFontFeatureSettingsAttribute holds) substitutes, as a bit vector indexed
// by glyph.
CORETEXT_EXPORT CFBitVectorRef CTFontCopyGlyphCoverageForFeature(CTFontRef font, CFDictionaryRef feature);

// The size in points of the sbix (bitmap) image of a glyph at a contents
// scale; 0 when the glyph has none.
CORETEXT_EXPORT CGFloat CTFontGetSbixImageSizeForGlyphAndContentsScale(CTFontRef font, const CGGlyph glyph,
                                                                       CGFloat contentsScale);

// The weight that text of a weight is drawn in when the Bold Text
// accessibility setting is on.
CORETEXT_EXPORT CGFloat CTFontGetAccessibilityBoldWeightOfWeight(CGFloat weight);

// Shapes glyphs in place: count glyphs (with their advances, origins and
// string indexes) for the characters chars. Returns the initial advance, the
// offset of the first glyph's origin from the start of the text. handler lets
// the callee grow or shrink the caller's arrays when shaping changes the
// number of glyphs.
CORETEXT_EXPORT CGSize CTFontShapeGlyphs(CTFontRef font, CGGlyph glyphs[], CGSize advances[],
                                         CGPoint origins[], CFIndex indexes[], const UniChar chars[],
                                         CFIndex count, CTFontShapeOptions options, CFStringRef language,
                                         void (^handler)(CFRange, CGGlyph **, CGSize **, CGPoint **, CFIndex **));
