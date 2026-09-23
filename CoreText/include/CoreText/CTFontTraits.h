#import <CoreFoundation/CFString.h>
#import <CoreText/CoreTextExport.h>

CORETEXT_EXPORT const CFStringRef kCTFontSymbolicTrait;
CORETEXT_EXPORT const CFStringRef kCTFontWeightTrait;
CORETEXT_EXPORT const CFStringRef kCTFontWidthTrait;
CORETEXT_EXPORT const CFStringRef kCTFontSlantTrait;

enum {
  kCTFontClassMaskShift = 28,
};

typedef CF_OPTIONS(uint32_t, CTFontSymbolicTraits) {
  kCTFontTraitItalic = (1 << 0),
  kCTFontItalicTrait = (1 << 0), // Deprecated
  kCTFontTraitBold = (1 << 1),
  kCTFontBoldTrait = (1 << 1), // Deprecated
  kCTFontTraitExpanded = (1 << 5),
  kCTFontExpandedTrait = (1 << 5), // Deprecated
  kCTFontTraitCondensed = (1 << 6),
  kCTFontCondensedTrait = (1 << 6), // Deprecated
  kCTFontTraitMonoSpace = (1 << 10),
  kCTFontMonoSpaceTrait = (1 << 10), // Deprecated
  kCTFontTraitVertical = (1 << 11),
  kCTFontVerticalTrait = (1 << 11), // Deprecated
  kCTFontTraitUIOptimized = (1 << 12),
  kCTFontUIOptimizedTrait = (1 << 12), // Deprecated
  kCTFontTraitColorGlyphs = (1 << 13),
  kCTFontTraitComposite = (1 << 14),
  kCTFontTraitClassMask = (15U << kCTFontClassMaskShift),
  kCTFontClassMaskTrait = (15U << 28), // Deprecated
};

typedef CF_OPTIONS(uint32_t, CTFontStylisticClass) {
  kCTFontClassUnknown = (0u << kCTFontClassMaskShift),
  kCTFontUnknownClass = kCTFontClassUnknown,
  kCTFontClassOldStyleSerifs = (1u << kCTFontClassMaskShift),
  kCTFontOldStyleSerifsClass = kCTFontClassOldStyleSerifs,
  kCTFontClassTransitionalSerifs = (2u << kCTFontClassMaskShift),
  kCTFontTransitionalSerifsClass = kCTFontClassTransitionalSerifs,
  kCTFontClassModernSerifs = (3u << kCTFontClassMaskShift),
  kCTFontModernSerifsClass = kCTFontClassModernSerifs,
  kCTFontClassClarendonSerifs = (4u << kCTFontClassMaskShift),
  kCTFontClarendonSerifsClass = kCTFontClassClarendonSerifs,
  kCTFontClassSlabSerifs = (5u << kCTFontClassMaskShift),
  kCTFontSlabSerifsClass = kCTFontClassSlabSerifs,
  kCTFontClassFreeformSerifs = (7u << kCTFontClassMaskShift),
  kCTFontFreeformSerifsClass = kCTFontClassFreeformSerifs,
  kCTFontClassSansSerif = (8u << kCTFontClassMaskShift),
  kCTFontSansSerifClass = kCTFontClassSansSerif,
  kCTFontClassOrnamentals = (9u << kCTFontClassMaskShift),
  kCTFontOrnamentalsClass = kCTFontClassOrnamentals,
  kCTFontClassScripts = (10u << kCTFontClassMaskShift),
  kCTFontScriptsClass = kCTFontClassScripts,
  kCTFontClassSymbolic = (12u << kCTFontClassMaskShift),
  kCTFontSymbolicClass = kCTFontClassSymbolic,
};
