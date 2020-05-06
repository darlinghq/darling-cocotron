#import <AppKit/KTFont.h>
#import <windows.h>

@class Win32Font;

typedef struct CGFontMetrics {
    CGFloat emsquare;
    CGFloat scale;
    CGRect boundingRect;
    CGFloat ascender;
    CGFloat descender;
    CGFloat leading;
    CGFloat italicAngle;
    CGFloat capHeight;
    CGFloat xHeight;
    CGFloat underlineThickness;
    CGFloat underlinePosition;
} CGFontMetrics;

typedef struct CGGlyphRange {
    CGGlyph glyphs[256];
} CGGlyphRange;

typedef struct CGGlyphRangeTable {
    unsigned numberOfGlyphs;
    struct CGGlyphRange *ranges[256];
    unichar *characters;
} CGGlyphRangeTable;

typedef struct {
    CGGlyph previous;
    CGFloat xoffset;
} CGKerningOffset;

typedef struct CGGlyphMetrics {
    BOOL hasAdvancement;
    CGFloat advanceA;
    CGFloat advanceB;
    CGFloat advanceC;
    unsigned numberOfKerningOffsets;
    CGKerningOffset *kerningOffsets;
} CGGlyphMetrics;

typedef struct CGGlyphMetricsSet {
    unsigned numberOfGlyphs;
    CGGlyphMetrics *info;
} CGGlyphMetricsSet;

@interface KTFont_gdi : KTFont {
    CFStringRef _name;
    CGFontMetrics _metrics;
    struct CGGlyphRangeTable *_glyphRangeTable;
    struct CGGlyphMetricsSet *_glyphInfoSet;
    BOOL _useMacMetrics;
    Win32Font *_winFont;
    HDC _dc;
}

- (Win32Font *) createGDIFontSelectedInDC: (HDC) dc;
- (CGSize) advancementForNominalGlyphs: (const CGGlyph *) glyphs
                                 count: (unsigned) count;

@end
