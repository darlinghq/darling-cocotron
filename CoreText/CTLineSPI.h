/* Copyright (C) 2026 Lubos Dolezel */
#import <CoreText/CTLine.h>
#import <CoreText/CTRun.h>
#import <CoreText/CTTypesetter.h>
#import <CoreText/CTParagraphStyle.h>

// Exported by CoreText on macOS but not declared in the SDK headers. Not
// installed; for callers inside the tree and tests that declare it themselves.
// The names and signatures are those callers bind to (WebKit's PAL SPI
// declarations, BSD licensed, list them).

// Supplies the text of a line or typesetter in pieces: the characters from
// stringIndex on, their count in *charCount and their attributes in
// *attributes (not retained by the callback). Returning NULL or a count of 0
// ends the text.
typedef const UniChar *(*CTUniCharProviderCallback)(CFIndex stringIndex, CFIndex *charCount,
                                                    CFDictionaryRef *attributes, void *refCon);
// Called once for each piece the provider returned, when it has been read.
typedef void (*CTUniCharDisposeCallback)(const UniChar *chars, void *refCon);

// A line, laid out as CTLineCreateWithAttributedString() does, of the text
// the provider supplies. NULL without a provider.
CORETEXT_EXPORT CTLineRef CTLineCreateWithUniCharProvider(CTUniCharProviderCallback provider,
                                                          CTUniCharDisposeCallback dispose,
                                                          void *refCon);

// A typesetter, as CTTypesetterCreateWithAttributedStringAndOptions() makes,
// of the text the provider supplies. NULL without a provider.
CORETEXT_EXPORT CTTypesetterRef CTTypesetterCreateWithUniCharProviderAndOptions(
        CTUniCharProviderCallback provider, CTUniCharDisposeCallback dispose, void *refCon,
        CFDictionaryRef options);

// The advance from the start of the run to the origin of its first glyph.
CORETEXT_EXPORT CGSize CTRunGetInitialAdvance(CTRunRef run);

// The language whose rules compose punctuation and spacing in East Asian text.
typedef CF_ENUM(uint8_t, CTCompositionLanguage) {
    kCTCompositionLanguageUnset,
    kCTCompositionLanguageNone,
    kCTCompositionLanguageJapanese,
    kCTCompositionLanguageSimplifiedChinese,
    kCTCompositionLanguageTraditionalChinese,
};

// Sets the composition language of a paragraph style.
CORETEXT_EXPORT void CTParagraphStyleSetCompositionLanguage(CTParagraphStyleRef style,
                                                            CTCompositionLanguage language);

// Frame attribute (CFNumber): the most lines a frame holds; 0 for no limit.
CORETEXT_EXPORT const CFStringRef kCTFrameMaximumNumberOfLinesAttributeName;
