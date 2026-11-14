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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSCell.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

@class NSFontDescriptor;

#ifndef DARLING
// Provides an extendable translation scheme for apps that use non-standard
// fonts in UI elements

@interface NSNibFontNameTranslator : NSObject {
}

- (NSString *) translateToNibFontName: (NSString *) fontName;
- (NSString *) translateFromNibFontName: (NSString *) fontName;

@end
#endif

typedef NSUInteger NSGlyph;

enum {
    NSNullGlyph = 0,
    NSControlGlyph = 0xFFFFFF,
};

typedef enum {
    NSNativeShortGlyphPacking,
} NSMultibyteGlyphPacking;

typedef enum {
    NSFontDefaultRenderingMode,
    NSFontAntialiasedRenderingMode,
    NSFontIntegerAdvancementsRenderingMode,
    NSFontAntialiasedIntegerAdvancementsRenderingMode,
} NSFontRenderingMode;

// Legacy ObjC ABI (i386): instance size must stay 0x18, Apple's; the ivars
// before the extras keep their position in the original order. Add new state
// to the extra struct, never as an ivar.
@interface NSFont : NSObject <NSCopying, NSSecureCoding> {
    NSString *_name;
    CGFloat _pointSize;
    NS_LEGACY_IVAR_PAD(_NSFontReserved1, 8)
    NS_EXTRA_IVARS_BEGIN(NSFont)
        CGFloat _matrix[6];
        NSStringEncoding _encoding;

        CGFontRef _cgFont;
        CTFontRef _ctFont;
    NS_EXTRA_IVARS_END(NSFont)
}

+ (CGFloat) systemFontSize;
+ (CGFloat) smallSystemFontSize;
+ (CGFloat) labelFontSize;
+ (CGFloat) systemFontSizeForControlSize: (NSControlSize) size;

+ (NSFont *) boldSystemFontOfSize: (CGFloat) size;
+ (NSFont *) controlContentFontOfSize: (CGFloat) size;

// Monospaced system fonts (10.15 / 10.11).
+ (NSFont *) monospacedSystemFontOfSize: (CGFloat) size
                                  weight: (CGFloat) weight;
+ (NSFont *) monospacedDigitSystemFontOfSize: (CGFloat) size
                                       weight: (CGFloat) weight;

+ (NSFont *) labelFontOfSize: (CGFloat) size;
+ (NSFont *) menuFontOfSize: (CGFloat) size;
+ (NSFont *) menuBarFontOfSize: (CGFloat) size;

+ (NSFont *) messageFontOfSize: (CGFloat) size;
+ (NSFont *) paletteFontOfSize: (CGFloat) size;
+ (NSFont *) systemFontOfSize: (CGFloat) size;
+ (NSFont *) systemFontOfSize: (CGFloat) size weight: (CGFloat) weight;
+ (NSFont *) titleBarFontOfSize: (CGFloat) size;
+ (NSFont *) toolTipsFontOfSize: (CGFloat) size;
+ (NSFont *) userFontOfSize: (CGFloat) size;
+ (NSFont *) userFixedPitchFontOfSize: (CGFloat) size;

+ (void) setUserFont: (NSFont *) value;
+ (void) setUserFixedPitchFont: (NSFont *) value;

+ (NSFont *) fontWithName: (NSString *) name size: (CGFloat) size;
+ (NSFont *) fontWithName: (NSString *) name matrix: (const CGFloat *) matrix;
+ (NSFont *) fontWithDescriptor: (NSFontDescriptor *) descriptor
                           size: (CGFloat) size;
+ (NSFont *) fontWithDescriptor: (NSFontDescriptor *) descriptor
                           size: (CGFloat) size
                  textTransform: (NSAffineTransform *) transform;

+ (NSArray *) preferredFontNames;
+ (void) setPreferredFontNames: (NSArray *) fontNames;

@property(nonatomic, readonly) CGFloat pointSize;
@property(nonatomic, readonly) NSString *fontName;
@property(nonatomic, readonly) const CGFloat *matrix;
@property(nonatomic, readonly) NSAffineTransform *textTransform;
@property(nonatomic, readonly) NSFontRenderingMode renderingMode;
@property(nonatomic, readonly) NSCharacterSet *coveredCharacterSet;
@property(nonatomic, readonly) NSStringEncoding mostCompatibleStringEncoding;
@property(nonatomic, readonly) NSString *familyName;
@property(nonatomic, readonly) NSString *displayName;
@property(nonatomic, readonly) NSFontDescriptor *fontDescriptor;

@property(nonatomic, readonly) NSFont *printerFont;
@property(nonatomic, readonly) NSFont *screenFont;
- (NSFont *) screenFontWithRenderingMode: (NSFontRenderingMode) mode;

@property(nonatomic, readonly) NSRect boundingRectForFont;
- (NSRect) boundingRectForGlyph: (NSGlyph) glyph;

- (NSMultibyteGlyphPacking) glyphPacking;
@property(nonatomic, readonly) NSUInteger numberOfGlyphs;
- (NSGlyph) glyphWithName: (NSString *) name;
- (BOOL) glyphIsEncoded: (NSGlyph) glyph;
- (NSSize) advancementForGlyph: (NSGlyph) glyph;

@property(nonatomic, readonly) NSSize maximumAdvancement;
@property(nonatomic, readonly) CGFloat underlinePosition;
@property(nonatomic, readonly) CGFloat underlineThickness;
@property(nonatomic, readonly) CGFloat ascender;
@property(nonatomic, readonly) CGFloat descender;
@property(nonatomic, readonly) CGFloat leading;
- (CGFloat) defaultLineHeightForFont;
@property(nonatomic, getter=isFixedPitch, readonly) BOOL fixedPitch;
@property(nonatomic, readonly) CGFloat italicAngle;
@property(nonatomic, readonly) CGFloat xHeight;
@property(nonatomic, readonly) CGFloat capHeight;

- (void) setInContext: (NSGraphicsContext *) context;
- (void) set;

- (NSPoint) positionOfGlyph: (NSGlyph) current
            precededByGlyph: (NSGlyph) previous
                  isNominal: (BOOL *) isNominalp;

- (void) getAdvancements: (NSSize *) advancements
               forGlyphs: (const NSGlyph *) glyphs
                   count: (NSUInteger) count;
- (void) getAdvancements: (NSSize *) advancements
         forPackedGlyphs: (const void *) packed
                  length: (NSUInteger) length;
- (void) getBoundingRects: (NSRect *) rects
                forGlyphs: (const NSGlyph *) glyphs
                    count: (NSUInteger) count;

// private

- (NSUInteger) getGlyphs: (NSGlyph *) glyphs
           forCharacters: (unichar *) characters
                  length: (NSUInteger) length;

@end

#ifndef DARLING
@interface NSFont (PortatibilityAdditions)

+ (void) setNibFontTranslator: (NSNibFontNameTranslator *) fontTranslator;
+ (NSNibFontNameTranslator *) nibFontTranslator;

@end
#endif

#ifdef __cplusplus
extern "C" {
#endif

NSInteger NSConvertGlyphsToPackedGlyphs(NSGlyph *glyphs, NSInteger length,
                                        NSMultibyteGlyphPacking packing,
                                        char *output);

extern NSNotificationName NSFontSetChangedNotification;
extern NSNotificationName NSAntialiasThresholdChangedNotification;

#ifdef __cplusplus
}
#endif
