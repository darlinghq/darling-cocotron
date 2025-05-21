enum {
  kCTFontClassMaskShift = 28,
};

typedef enum CTFontSymbolicTraits : uint32_t {
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
} CTFontSymbolicTraits;
