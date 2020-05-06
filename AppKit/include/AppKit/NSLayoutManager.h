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

#import <AppKit/NSFont.h>
#import <Foundation/Foundation.h>

@class NSTextStorage, NSGlyphGenerator, NSTypesetter, NSTextContainer,
    NSTextView, NSRulerView;
@class NSWindow, NSColor, NSCell;

typedef enum {
    NSGlyphInscribeBase,
    NSGlyphInscribeBelow,
    NSGlyphInscribeAbove,
    NSGlyphInscribeOverstrike,
    NSGlyphInscribeOverBelow,
} NSGlyphInscription;

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

    NSRect _extraLineFragmentRect;
    NSRect _extraLineFragmentUsedRect;
    NSTextContainer *_extraLineFragmentTextContainer;

    NSUInteger _rectCacheCapacity, _rectCacheCount;
    NSRect *_rectCache;
}

- init;

- (NSTextStorage *) textStorage;
- (NSGlyphGenerator *) glyphGenerator;
- (NSTypesetter *) typesetter;
- delegate;
- (NSArray *) textContainers;

- (NSTextView *) firstTextView;
- (NSTextView *) textViewForBeginningOfSelection;
- (BOOL) layoutManagerOwnsFirstResponderInWindow: (NSWindow *) window;

- (void) setTextStorage: (NSTextStorage *) textStorage;
- (void) replaceTextStorage: (NSTextStorage *) textStorage;
- (void) setGlyphGenerator: (NSGlyphGenerator *) generator;
- (void) setTypesetter: (NSTypesetter *) typesetter;
- (void) setDelegate: delegate;

- (BOOL) usesScreenFonts;
- (void) setUsesScreenFonts: (BOOL) yorn;

- (void) addTextContainer: (NSTextContainer *) container;
- (void) removeTextContainerAtIndex: (NSUInteger) index;
- (void) insertTextContainer: (NSTextContainer *) container
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
- (NSUInteger) getGlyphs: (NSGlyph *) glyphs range: (NSRange) glyphRange;

- (NSUInteger) getGlyphsInRange: (NSRange) range
                         glyphs: (NSGlyph *) glyphs
               characterIndexes: (NSUInteger *) charIndexes
              glyphInscriptions: (NSGlyphInscription *) inscriptions
                    elasticBits: (BOOL *) elasticBits;
- (NSUInteger) getGlyphsInRange: (NSRange) range
                         glyphs: (NSGlyph *) glyphs
               characterIndexes: (NSUInteger *) charIndexes
              glyphInscriptions: (NSGlyphInscription *) inscriptions
                    elasticBits: (BOOL *) elasticBits
                     bidiLevels: (unsigned char *) bidiLevels;

- (NSTextContainer *) textContainerForGlyphAtIndex: (NSUInteger) glyphIndex
                                    effectiveRange:
                                        (NSRangePointer) effectiveGlyphRange;
- (NSRect) lineFragmentRectForGlyphAtIndex: (NSUInteger) glyphIndex
                            effectiveRange:
                                (NSRangePointer) effectiveGlyphRange;
- (NSPoint) locationForGlyphAtIndex: (NSUInteger) glyphIndex;
- (NSRect) lineFragmentUsedRectForGlyphAtIndex: (NSUInteger) glyphIndex
                                effectiveRange:
                                    (NSRangePointer) effectiveGlyphRange;
- (NSRect) usedRectForTextContainer: (NSTextContainer *) container;
- (NSRect) extraLineFragmentRect;
- (NSRect) extraLineFragmentUsedRect;
- (NSTextContainer *) extraLineFragmentTextContainer;

- (void) setTextContainer: (NSTextContainer *) container
            forGlyphRange: (NSRange) glyphRange;
- (void) setLineFragmentRect: (NSRect) fragmentRect
               forGlyphRange: (NSRange) glyphRange
                    usedRect: (NSRect) usedRect;
- (void) setLocation: (NSPoint) location
    forStartOfGlyphRange: (NSRange) glyphRange;

- (void) setExtraLineFragmentRect: (NSRect) fragmentRect
                         usedRect: (NSRect) usedRect
                    textContainer: (NSTextContainer *) container;

- (void) invalidateGlyphsForCharacterRange: (NSRange) charRange
                            changeInLength: (NSInteger) delta
                      actualCharacterRange: (NSRangePointer) actualCharRange;
- (void) invalidateLayoutForCharacterRange: (NSRange) charRange
                                    isSoft: (BOOL) isSoft
                      actualCharacterRange: (NSRangePointer) actualCharRange;
- (void) invalidateDisplayForGlyphRange: (NSRange) glyphRange;
- (void) invalidateDisplayForCharacterRange: (NSRange) charRange;

- (void) textStorage: (NSTextStorage *) storage
              edited: (NSUInteger) editedMask
               range: (NSRange) range
      changeInLength: (NSInteger) changeInLength
    invalidatedRange: (NSRange) invalidateRange;

- (void) textContainerChangedGeometry: (NSTextContainer *) container;
- (void) ensureLayoutForTextContainer: (NSTextContainer *) container;

- (NSUInteger) glyphIndexForPoint: (NSPoint) point
                   inTextContainer: (NSTextContainer *) container
    fractionOfDistanceThroughGlyph: (CGFloat *) fraction;
- (NSUInteger) glyphIndexForPoint: (NSPoint) point
                  inTextContainer: (NSTextContainer *) container;
- (CGFloat) fractionOfDistanceThroughGlyphForPoint: (NSPoint) point
                                   inTextContainer:
                                       (NSTextContainer *) container;

- (NSRange) glyphRangeForTextContainer: (NSTextContainer *) container;
- (NSRange) glyphRangeForCharacterRange: (NSRange) charRange
                   actualCharacterRange: (NSRangePointer) actualCharRange;
- (NSRange) glyphRangeForBoundingRect: (NSRect) bounds
                      inTextContainer: (NSTextContainer *) container;
- (NSRange) glyphRangeForBoundingRectWithoutAdditionalLayout: (NSRect) bounds
                                             inTextContainer:
                                                 (NSTextContainer *) container;
- (NSRange) rangeOfNominallySpacedGlyphsContainingIndex:
    (NSUInteger) glyphIndex;

- (NSRect) boundingRectForGlyphRange: (NSRange) glyphRange
                     inTextContainer: (NSTextContainer *) container;
- (NSRect *) rectArrayForGlyphRange: (NSRange) glyphRange
           withinSelectedGlyphRange: (NSRange) selectedGlyphRange
                    inTextContainer: (NSTextContainer *) container
                          rectCount: (NSUInteger *) rectCount;

- (NSUInteger) characterIndexForGlyphAtIndex: (NSUInteger) glyphIndex;
- (NSRange) characterRangeForGlyphRange: (NSRange) glyphRange
                       actualGlyphRange: (NSRange *) actualGlyphRange;
- (NSRect *) rectArrayForCharacterRange: (NSRange) characterRange
           withinSelectedCharacterRange: (NSRange) selectedCharRange
                        inTextContainer: (NSTextContainer *) container
                              rectCount: (NSUInteger *) rectCount;

- (NSUInteger) firstUnlaidGlyphIndex;
- (NSUInteger) firstUnlaidCharacterIndex;
- (void) getFirstUnlaidCharacterIndex: (NSUInteger *) charIndex
                           glyphIndex: (NSUInteger *) glyphIndex;

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

- (CGFloat) defaultLineHeightForFont: (NSFont *) font;

- (NSDictionary *) temporaryAttributesAtCharacterIndex: (NSUInteger) charIndex
                                        effectiveRange:
                                            (NSRangePointer) effectiveCharRange;
- (void) setTemporaryAttributes: (NSDictionary *) attrs
              forCharacterRange: (NSRange) charRange;
- (void) addTemporaryAttributes: (NSDictionary *) attrs
              forCharacterRange: (NSRange) charRange;
- (void) removeTemporaryAttribute: (NSString *) attrName
                forCharacterRange: (NSRange) charRange;

- (id) temporaryAttribute: (NSString *) attrName
         atCharacterIndex: (NSUInteger) location
           effectiveRange: (NSRangePointer) range;
- (id) temporaryAttribute: (NSString *) attrName
         atCharacterIndex: (NSUInteger) location
    longestEffectiveRange: (NSRangePointer) range
                  inRange: (NSRange) rangeLimit;
- (NSDictionary *) temporaryAttributesAtCharacterIndex: (NSUInteger) location
                                 longestEffectiveRange: (NSRangePointer) range
                                               inRange: (NSRange) rangeLimit;
- (void) addTemporaryAttribute: (NSString *) attrName
                         value: (id) value
             forCharacterRange: (NSRange) charRange;

- (NSArray *) rulerMarkersForTextView: (NSTextView *) view
                       paragraphStyle: (NSParagraphStyle *) style
                                ruler: (NSRulerView *) ruler;
- (NSView *) rulerAccessoryViewForTextView: (NSTextView *) view
                            paragraphStyle: (NSParagraphStyle *) style
                                     ruler: (NSRulerView *) ruler
                                   enabled: (BOOL) isEnabled;
@end

@protocol NSLayoutManagerDelegate <NSObject>
@optional
- (void) layoutManager: (NSLayoutManager *) layoutManager
    didCompleteLayoutForTextContainer: (NSTextContainer *) textContainer
                                atEnd: (BOOL) layoutFinishedFlag;
- (NSDictionary *) layoutManager: (NSLayoutManager *) layoutManager
    shouldUseTemporaryAttributes: (NSDictionary *) attrs
              forDrawingToScreen: (BOOL) toScreen
                atCharacterIndex: (NSUInteger) charIndex
                  effectiveRange: (NSRangePointer) effectiveCharRange;
@end
