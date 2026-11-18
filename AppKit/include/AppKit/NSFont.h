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
#import <CoreText/CoreText.h>
#import <Foundation/Foundation.h>

@class NSFontDescriptor;

NS_ASSUME_NONNULL_BEGIN

#ifndef DARLING
// Provides an extendable translation scheme for apps that use non-standard
// fonts in UI elements

@interface NSNibFontNameTranslator : NSObject {
}

- (null_unspecified NSString *) translateToNibFontName: (null_unspecified NSString *) fontName;
- (null_unspecified NSString *) translateFromNibFontName: (null_unspecified NSString *) fontName;

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

        // Set on the fonts -screenFontWithRenderingMode: returns; an ordinary
        // font reports NSFontAntialiasedRenderingMode.
        BOOL _isScreenFont;
        NSFontRenderingMode _renderingMode;
        NSFont *_screenFonts[NSFontAntialiasedIntegerAdvancementsRenderingMode + 1];
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
+ (nullable NSFont *) userFontOfSize: (CGFloat) size;
+ (nullable NSFont *) userFixedPitchFontOfSize: (CGFloat) size;

+ (void) setUserFont: (nullable NSFont *) value;
+ (void) setUserFixedPitchFont: (nullable NSFont *) value;

+ (nullable NSFont *) fontWithName: (NSString *) name size: (CGFloat) size;
+ (nullable NSFont *) fontWithName: (NSString *) name matrix: (const CGFloat *) matrix;
+ (nullable NSFont *) fontWithDescriptor: (NSFontDescriptor *) descriptor
                           size: (CGFloat) size;
+ (null_unspecified NSFont *) fontWithDescriptor: (null_unspecified NSFontDescriptor *) descriptor
                           size: (CGFloat) size
                  textTransform: (null_unspecified NSAffineTransform *) transform;

+ (null_unspecified NSArray *) preferredFontNames;
+ (void) setPreferredFontNames: (null_unspecified NSArray *) fontNames;

@property(nonatomic, readonly) CGFloat pointSize;
@property(nonatomic, readonly) NSString *fontName;
@property(nonatomic, readonly) const CGFloat *matrix;
@property(nonatomic, readonly) NSAffineTransform *textTransform;
@property(nonatomic, readonly) NSFontRenderingMode renderingMode;
@property(nonatomic, readonly) NSCharacterSet *coveredCharacterSet;
@property(nonatomic, readonly) NSStringEncoding mostCompatibleStringEncoding;
@property(nullable, nonatomic, readonly) NSString *familyName;
@property(nullable, nonatomic, readonly) NSString *displayName;
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
                  isNominal: (null_unspecified BOOL *) isNominalp;

- (void) getAdvancements: (null_unspecified NSSize *) advancements
               forGlyphs: (const NSGlyph *) glyphs
                   count: (NSUInteger) count;
- (void) getAdvancements: (null_unspecified NSSize *) advancements
         forPackedGlyphs: (const void *) packed
                  length: (NSUInteger) length;
- (void) getBoundingRects: (null_unspecified NSRect *) rects
                forGlyphs: (const NSGlyph *) glyphs
                    count: (NSUInteger) count;

// private

- (NSUInteger) getGlyphs: (null_unspecified NSGlyph *) glyphs
           forCharacters: (null_unspecified unichar *) characters
                  length: (NSUInteger) length;

@end

#ifndef DARLING
@interface NSFont (PortatibilityAdditions)

+ (void) setNibFontTranslator: (null_unspecified NSNibFontNameTranslator *) fontTranslator;
+ (null_unspecified NSNibFontNameTranslator *) nibFontTranslator;

@end
#endif

#ifdef __cplusplus
extern "C" {
#endif

NSInteger NSConvertGlyphsToPackedGlyphs(NSGlyph *glyphs, NSInteger length,
                                        NSMultibyteGlyphPacking packing,
                                        char *output);

// The identity font matrix: six values, 1 0 0 1 0 0. Deprecated; kept for
// binaries that still import it.
extern const CGFloat * _Nullable NSFontIdentityMatrix;

extern NSNotificationName NSFontSetChangedNotification;
extern NSNotificationName NSAntialiasThresholdChangedNotification;

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
