/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/NSCell.h>
#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

@class NSRulerMarker;

NS_ASSUME_NONNULL_BEGIN

@class NSTextStorage, NSGlyphGenerator, NSTypesetter, NSTextContainer,
        NSTextView, NSRulerView;
@class NSWindow, NSColor, NSCell;

typedef NS_ENUM(NSUInteger, NSGlyphInscription) {
    NSGlyphInscribeBase,
    NSGlyphInscribeBelow,
    NSGlyphInscribeAbove,
    NSGlyphInscribeOverstrike,
    NSGlyphInscribeOverBelow,
};

typedef NS_ENUM(NSInteger, NSTextLayoutOrientation) {
    NSTextLayoutOrientationHorizontal,
    NSTextLayoutOrientationVertical,
};

typedef NS_OPTIONS(NSInteger, NSGlyphProperty) {
    NSGlyphPropertyNull = (1 << 0),
    NSGlyphPropertyControlCharacter = (1 << 1),
    NSGlyphPropertyElastic = (1 << 2),
    NSGlyphPropertyNonBaseCharacter = (1 << 3),
};

typedef NS_OPTIONS(NSInteger, NSControlCharacterAction) {
    NSControlCharacterActionZeroAdvancement = (1 << 0),
    NSControlCharacterActionWhitespace = (1 << 1),
    NSControlCharacterActionHorizontalTab = (1 << 2),
    NSControlCharacterActionLineBreak = (1 << 3),
    NSControlCharacterActionParagraphBreak = (1 << 4),
    NSControlCharacterActionContainerBreak = (1 << 5),
};

@interface NSLayoutManager : NSObject {
    NSTextStorage *_textStorage;
    NSGlyphGenerator *_glyphGenerator;
    NSTypesetter *_typesetter;

    id _delegate;

    NSMutableArray *_textContainers;

    struct NSRangeEntries *_glyphFragments;
    struct NSRangeEntries *_invalidFragments;

    struct NSRangeEntries *_rangeToTemporaryAttributes;

    BOOL _layoutInvalid;
    BOOL _allowsNonContiguousLayout;

    NSRect _extraLineFragmentRect;
    NSRect _extraLineFragmentUsedRect;
    NSTextContainer *_extraLineFragmentTextContainer;

    NSUInteger _rectCacheCapacity, _rectCacheCount;
    NSRect *_rectCache;

    BOOL _showsControlCharacters;
    BOOL _showsInvisibleCharacters;
    BOOL _usesFontLeading;
    BOOL _backgroundLayoutEnabled;
    NSFont *_textFont;
    NSImageScaling _defaultAttachmentScaling;
    BOOL _usesDefaultHyphenation;
    BOOL _doesNotUseScreenFonts; // inverted: a zeroed layout manager uses screen fonts
    NS_LEGACY_IVAR_PAD(_NSLayoutManagerReserved, 111)
}

- (null_unspecified instancetype) init;

@property(null_unspecified, nonatomic, retain) NSFont *textFont;

@property(nonatomic) BOOL showsControlCharacters;
@property(nonatomic) BOOL showsInvisibleCharacters;
@property(nonatomic) BOOL usesFontLeading;
@property(nonatomic) BOOL backgroundLayoutEnabled;

@property(nullable, nonatomic, retain) NSTextStorage *textStorage;
@property(nonatomic, retain) NSGlyphGenerator *glyphGenerator;
@property(null_unspecified, nonatomic, retain) NSTypesetter *typesetter;
- (null_unspecified id) delegate;
- (nullable NSArray<NSTextContainer *> *) textContainers;

- (nullable NSTextView *) firstTextView;
- (nullable NSTextView *) textViewForBeginningOfSelection;
- (BOOL) layoutManagerOwnsFirstResponderInWindow: (NSWindow *) window;

- (void) replaceTextStorage: (null_unspecified NSTextStorage *) textStorage;
- (void) setDelegate: (null_unspecified id) delegate;

@property(nonatomic) BOOL usesScreenFonts;

- (void) addTextContainer: (null_unspecified NSTextContainer *) container;
- (void) removeTextContainerAtIndex: (NSUInteger) index;
- (void) insertTextContainer: (null_unspecified NSTextContainer *) container
                     atIndex: (NSUInteger) index;

- (void) insertGlyph: (NSGlyph) glyph
          atGlyphIndex: (NSUInteger) glyphIndex
        characterIndex: (NSUInteger) characterIndex;
- (void) replaceGlyphAtIndex: (NSUInteger) glyphIndex
                   withGlyph: (NSGlyph) glyph;
- (void) deleteGlyphsInRange: (NSRange) glyphRange;
- (void) setCharacterIndex: (NSUInteger) characterIndex
           forGlyphAtIndex: (NSUInteger) glyphIndex;
- (void) setNotShownAttribute: (BOOL) notShown
              forGlyphAtIndex: (NSUInteger) glyphIndex;
- (void) setAttachmentSize: (NSSize) size forGlyphRange: (NSRange) glyphRange;
- (void) setDrawsOutsideLineFragment: (BOOL) drawsOutside
                     forGlyphAtIndex: (NSUInteger) glyphIndex;

- (NSUInteger) numberOfGlyphs;
- (NSUInteger) getGlyphs: (nullable NSGlyph *) glyphs range: (NSRange) glyphRange;

- (NSUInteger) getGlyphsInRange: (NSRange) range
                         glyphs: (nullable NSGlyph *) glyphs
               characterIndexes: (nullable NSUInteger *) charIndexes
              glyphInscriptions: (nullable NSGlyphInscription *) inscriptions
                    elasticBits: (nullable BOOL *) elasticBits;
- (NSUInteger) getGlyphsInRange: (NSRange) range
                         glyphs: (nullable NSGlyph *) glyphs
               characterIndexes: (nullable NSUInteger *) charIndexes
              glyphInscriptions: (nullable NSGlyphInscription *) inscriptions
                    elasticBits: (nullable BOOL *) elasticBits
                     bidiLevels: (nullable unsigned char *) bidiLevels;

- (null_unspecified NSTextContainer *) textContainerForGlyphAtIndex: (NSUInteger) glyphIndex
                                    effectiveRange: (nullable NSRangePointer)
                                                            effectiveGlyphRange;
- (NSRect) lineFragmentRectForGlyphAtIndex: (NSUInteger) glyphIndex
                            effectiveRange:
                                    (nullable NSRangePointer) effectiveGlyphRange;
- (NSPoint) locationForGlyphAtIndex: (NSUInteger) glyphIndex;
- (NSRect) lineFragmentUsedRectForGlyphAtIndex: (NSUInteger) glyphIndex
                                effectiveRange:
                                        (nullable NSRangePointer) effectiveGlyphRange;
- (void) enumerateLineFragmentsForGlyphRange: (NSRange) glyphRange
                                  usingBlock: (void (^)(NSRect lineRect, NSRect usedRect,
                                                        NSTextContainer *textContainer,
                                                        NSRange lineGlyphRange,
                                                        BOOL *stop)) block;
- (NSRect) usedRectForTextContainer: (null_unspecified NSTextContainer *) container;
- (NSRect) extraLineFragmentRect;
- (NSRect) extraLineFragmentUsedRect;
- (null_unspecified NSTextContainer *) extraLineFragmentTextContainer;

@property(nonatomic) BOOL allowsNonContiguousLayout;

- (void) setTextContainer: (null_unspecified NSTextContainer *) container
            forGlyphRange: (NSRange) glyphRange;
- (void) setLineFragmentRect: (NSRect) fragmentRect
               forGlyphRange: (NSRange) glyphRange
                    usedRect: (NSRect) usedRect;
- (void) setLocation: (NSPoint) location
        forStartOfGlyphRange: (NSRange) glyphRange;

- (void) setExtraLineFragmentRect: (NSRect) fragmentRect
                         usedRect: (NSRect) usedRect
                    textContainer: (null_unspecified NSTextContainer *) container;

- (void) invalidateGlyphsForCharacterRange: (NSRange) charRange
                            changeInLength: (NSInteger) delta
                      actualCharacterRange: (nullable NSRangePointer) actualCharRange;
- (void) invalidateLayoutForCharacterRange: (NSRange) charRange
                                    isSoft: (BOOL) isSoft
                      actualCharacterRange: (nullable NSRangePointer) actualCharRange;
- (void) invalidateDisplayForGlyphRange: (NSRange) glyphRange;
- (void) invalidateDisplayForCharacterRange: (NSRange) charRange;

- (void) textStorage: (NSTextStorage *) storage
                  edited: (NSUInteger) editedMask
                   range: (NSRange) range
          changeInLength: (NSInteger) changeInLength
        invalidatedRange: (NSRange) invalidateRange;

- (void) textContainerChangedGeometry: (null_unspecified NSTextContainer *) container;
- (void) ensureLayoutForTextContainer: (null_unspecified NSTextContainer *) container;
- (void) ensureLayoutForGlyphRange: (NSRange) glyphRange;
- (void) ensureLayoutForCharacterRange: (NSRange) charRange;

- (NSUInteger) glyphIndexForPoint: (NSPoint) point
                       inTextContainer: (null_unspecified NSTextContainer *) container
        fractionOfDistanceThroughGlyph: (null_unspecified CGFloat *) fraction;
- (NSUInteger) glyphIndexForPoint: (NSPoint) point
                  inTextContainer: (null_unspecified NSTextContainer *) container;
- (CGFloat) fractionOfDistanceThroughGlyphForPoint: (NSPoint) point
                                   inTextContainer:
                                           (null_unspecified NSTextContainer *) container;

- (NSRange) glyphRangeForTextContainer: (null_unspecified NSTextContainer *) container;
- (NSRange) glyphRangeForCharacterRange: (NSRange) charRange
                   actualCharacterRange: (nullable NSRangePointer) actualCharRange;
- (NSRange) glyphRangeForBoundingRect: (NSRect) bounds
                      inTextContainer: (null_unspecified NSTextContainer *) container;
- (NSRange) glyphRangeForBoundingRectWithoutAdditionalLayout: (NSRect) bounds
                                             inTextContainer:
                                                     (null_unspecified NSTextContainer *)
                                                             container;
- (NSRange) rangeOfNominallySpacedGlyphsContainingIndex:
        (NSUInteger) glyphIndex;

- (NSRect) boundingRectForGlyphRange: (NSRange) glyphRange
                     inTextContainer: (null_unspecified NSTextContainer *) container;
- (null_unspecified NSRect *) rectArrayForGlyphRange: (NSRange) glyphRange
           withinSelectedGlyphRange: (NSRange) selectedGlyphRange
                    inTextContainer: (NSTextContainer *) container
                          rectCount: (NSUInteger *) rectCount;

- (NSUInteger) characterIndexForGlyphAtIndex: (NSUInteger) glyphIndex;
- (NSRange) characterRangeForGlyphRange: (NSRange) glyphRange
                       actualGlyphRange: (null_unspecified NSRange *) actualGlyphRange;
- (null_unspecified NSRect *) rectArrayForCharacterRange: (NSRange) characterRange
           withinSelectedCharacterRange: (NSRange) selectedCharRange
                        inTextContainer: (NSTextContainer *) container
                              rectCount: (NSUInteger *) rectCount;

- (NSUInteger) firstUnlaidGlyphIndex;
- (NSUInteger) firstUnlaidCharacterIndex;
- (void) getFirstUnlaidCharacterIndex: (null_unspecified NSUInteger *) charIndex
                           glyphIndex: (null_unspecified NSUInteger *) glyphIndex;

- (void) showPackedGlyphs: (char *) glyphs
                    length: (NSUInteger) length
                glyphRange: (NSRange) glyphRange
                   atPoint: (NSPoint) point
                      font: (NSFont *) font
                     color: (NSColor *) color
        printingAdjustment: (NSSize) printingAdjustment;

- (void) drawBackgroundForGlyphRange: (NSRange) glyphRange
                             atPoint: (NSPoint) origin;
- (void) drawGlyphsForGlyphRange: (NSRange) glyphRange
                         atPoint: (NSPoint) origin;

- (void) drawUnderlineForGlyphRange: (NSRange) glyphRange
                      underlineType: (NSInteger) underlineVal
                     baselineOffset: (CGFloat) baselineOffset
                   lineFragmentRect: (NSRect) lineRect
             lineFragmentGlyphRange: (NSRange) lineGlyphRange
                    containerOrigin: (NSPoint) containerOrigin;
- (void) underlineGlyphRange: (NSRange) glyphRange
                 underlineType: (NSInteger) underlineVal
              lineFragmentRect: (NSRect) lineRect
        lineFragmentGlyphRange: (NSRange) lineGlyphRange
               containerOrigin: (NSPoint) containerOrigin;

- (void) drawStrikethroughForGlyphRange: (NSRange) glyphRange
                      strikethroughType: (NSInteger) strikethroughVal
                         baselineOffset: (CGFloat) baselineOffset
                       lineFragmentRect: (NSRect) lineRect
                 lineFragmentGlyphRange: (NSRange) lineGlyphRange
                        containerOrigin: (NSPoint) containerOrigin;
- (void) strikethroughGlyphRange: (NSRange) glyphRange
               strikethroughType: (NSInteger) strikethroughVal
                lineFragmentRect: (NSRect) lineRect
          lineFragmentGlyphRange: (NSRange) lineGlyphRange
                 containerOrigin: (NSPoint) containerOrigin;

- (CGFloat) defaultLineHeightForFont: (null_unspecified NSFont *) font;
- (CGFloat) defaultBaselineOffsetForFont: (null_unspecified NSFont *) font;

- (null_unspecified NSDictionary *) temporaryAttributesAtCharacterIndex: (NSUInteger) charIndex
                                        effectiveRange:
                                                (nullable NSRangePointer)
                                                        effectiveCharRange;
- (void) setTemporaryAttributes: (null_unspecified NSDictionary *) attrs
              forCharacterRange: (NSRange) charRange;
- (void) addTemporaryAttributes: (null_unspecified NSDictionary *) attrs
              forCharacterRange: (NSRange) charRange;
- (void) removeTemporaryAttribute: (null_unspecified NSString *) attrName
                forCharacterRange: (NSRange) charRange;

- (null_unspecified id) temporaryAttribute: (null_unspecified NSString *) attrName
         atCharacterIndex: (NSUInteger) location
           effectiveRange: (nullable NSRangePointer) range;
- (null_unspecified id) temporaryAttribute: (null_unspecified NSString *) attrName
             atCharacterIndex: (NSUInteger) location
        longestEffectiveRange: (nullable NSRangePointer) range
                      inRange: (NSRange) rangeLimit;
- (null_unspecified NSDictionary *) temporaryAttributesAtCharacterIndex: (NSUInteger) location
                                 longestEffectiveRange: (nullable NSRangePointer) range
                                               inRange: (NSRange) rangeLimit;
- (void) addTemporaryAttribute: (null_unspecified NSString *) attrName
                         value: (null_unspecified id) value
             forCharacterRange: (NSRange) charRange;

- (NSArray<NSRulerMarker *> *) rulerMarkersForTextView: (NSTextView *) view
                       paragraphStyle: (NSParagraphStyle *) style
                                ruler: (NSRulerView *) ruler;
- (nullable __kindof NSView *) rulerAccessoryViewForTextView: (NSTextView *) view
                            paragraphStyle: (NSParagraphStyle *) style
                                     ruler: (NSRulerView *) ruler
                                   enabled: (BOOL) isEnabled;


// Stored only: attachments are drawn at their own size. NSImageScaleNone
// by default.
@property(nonatomic) NSImageScaling defaultAttachmentScaling;
// Stored only (NO by default): the typesetter doesn't hyphenate.
@property(nonatomic) BOOL usesDefaultHyphenation;
@end

@protocol NSLayoutManagerDelegate <NSObject>
@optional
- (void) layoutManager: (NSLayoutManager *) layoutManager
        didCompleteLayoutForTextContainer: (nullable NSTextContainer *) textContainer
                                    atEnd: (BOOL) layoutFinishedFlag;
- (nullable NSDictionary<NSAttributedStringKey, id> *) layoutManager: (NSLayoutManager *) layoutManager
        shouldUseTemporaryAttributes: (NSDictionary<NSAttributedStringKey, id> *) attrs
                  forDrawingToScreen: (BOOL) toScreen
                    atCharacterIndex: (NSUInteger) charIndex
                      effectiveRange: (nullable NSRangePointer) effectiveCharRange;
@end

@protocol NSTextLayoutOrientationProvider

- (NSTextLayoutOrientation) layoutOrientation;

@end

NS_ASSUME_NONNULL_END
