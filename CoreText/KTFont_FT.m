/* Copyright (c) 2008 Johannes Fortmann

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import <CoreText/KTFont_FT.h>
#import <Onyx2D/O2Font_freetype.h>
#ifdef DARLING
#define __linux__
#endif
#import <ft2build.h>
#import FT_OUTLINE_H
#ifdef DARLING
#undef __linux__
#endif

typedef struct {
    CGMutablePathRef path;
    const CGAffineTransform *matrix;
    BOOL contourOpen;
} GlyphPathBuilder;

static int glyphPathMoveTo(const FT_Vector *to, void *user) {
    GlyphPathBuilder *builder = user;

    if (builder->contourOpen)
        CGPathCloseSubpath(builder->path);
    CGPathMoveToPoint(builder->path, builder->matrix, to->x, to->y);
    builder->contourOpen = YES;
    return 0;
}

static int glyphPathLineTo(const FT_Vector *to, void *user) {
    GlyphPathBuilder *builder = user;

    CGPathAddLineToPoint(builder->path, builder->matrix, to->x, to->y);
    return 0;
}

static int glyphPathConicTo(const FT_Vector *control, const FT_Vector *to, void *user) {
    GlyphPathBuilder *builder = user;

    CGPathAddQuadCurveToPoint(builder->path, builder->matrix, control->x, control->y,
                              to->x, to->y);
    return 0;
}

static int glyphPathCubicTo(const FT_Vector *control1, const FT_Vector *control2,
                            const FT_Vector *to, void *user)
{
    GlyphPathBuilder *builder = user;

    CGPathAddCurveToPoint(builder->path, builder->matrix, control1->x, control1->y,
                          control2->x, control2->y, to->x, to->y);
    return 0;
}

@implementation KTFont (KTFont_FT)
+ (id) allocWithZone: (NSZone *) zone {
    return NSAllocateObject([KTFont_FT class], 0, NULL);
}
@end

@implementation KTFont_FT

// Default point sizes and faces of the UI font types, as CTFontCreateUIFontForLanguage
// reports them when the requested size is 0. Darling has one UI family: the
// system faces map to the sans-serif font known as "San Francisco" (bold where
// the type is emphasized); the user font maps to Helvetica and the fixed pitch
// font to a monospace face.
typedef struct {
    CGFloat size;
    BOOL bold;
    NSString *pattern;
} KTUIFontSpec;

static BOOL KTUIFontSpecForType(CTFontUIFontType type, KTUIFontSpec *spec) {
    static const struct {
        CGFloat size;
        BOOL bold;
    } sizes[] = {
        [kCTFontUIFontUser] = { 12, NO },
        [kCTFontUIFontUserFixedPitch] = { 10, NO },
        [kCTFontUIFontSystem] = { 13, NO },
        [kCTFontUIFontEmphasizedSystem] = { 13, YES },
        [kCTFontUIFontSmallSystem] = { 11, NO },
        [kCTFontUIFontSmallEmphasizedSystem] = { 11, YES },
        [kCTFontUIFontMiniSystem] = { 9, NO },
        [kCTFontUIFontMiniEmphasizedSystem] = { 9, YES },
        [kCTFontUIFontViews] = { 12, NO },
        [kCTFontUIFontApplication] = { 13, NO },
        [kCTFontUIFontLabel] = { 10, NO },
        [kCTFontUIFontMenuTitle] = { 14, NO },
        [kCTFontUIFontMenuItem] = { 14, NO },
        [kCTFontUIFontMenuItemMark] = { 14, NO },
        [kCTFontUIFontMenuItemCmdKey] = { 14, NO },
        [kCTFontUIFontWindowTitle] = { 13, NO },
        [kCTFontUIFontPushButton] = { 13, NO },
        [kCTFontUIFontUtilityWindowTitle] = { 11, NO },
        [kCTFontUIFontAlertHeader] = { 13, YES },
        [kCTFontUIFontSystemDetail] = { 9, NO },
        [kCTFontUIFontEmphasizedSystemDetail] = { 9, YES },
        [kCTFontUIFontToolbar] = { 11, NO },
        [kCTFontUIFontSmallToolbar] = { 10, NO },
        [23] = { 13, NO },
        [24] = { 11, NO },
        [kCTFontUIFontToolTip] = { 11, NO },
        [kCTFontUIFontControlContent] = { 12, NO },
    };

    if (type > kCTFontUIFontControlContent)
        return NO;
    spec->size = sizes[type].size;
    spec->bold = sizes[type].bold;
    if (type == kCTFontUIFontUser)
        spec->pattern = @"Helvetica";
    else if (type == kCTFontUIFontUserFixedPitch)
        spec->pattern = @"monospace";
    else
        spec->pattern = spec->bold ? @"San Francisco:bold" : @"San Francisco";
    return YES;
}

- initWithUIFontType: (CTFontUIFontType) uiFontType
                size: (CGFloat) size
            language: (NSString *) language
{
    KTUIFontSpec spec;

    if (!KTUIFontSpecForType(uiFontType, &spec)) {
        [self release];
        return nil;
    }
    if (size == 0)
        size = spec.size;

    O2Font *font = O2FontCreateWithFontName(spec.pattern);
    if (font == nil) {
        [self release];
        return nil;
    }

    self = [self initWithFont: (CGFontRef)font size: size];

    [font release];

    return self;
}

- (void) getGlyphs: (CGGlyph *) glyphs
        forCharacters: (const unichar *) characters
               length: (NSUInteger) length
{
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];

        for (NSUInteger i = 0; i < length; i++) {
            uint32_t codePoint = characters[i];
            bool paired = codePoint >= 0xD800 && codePoint <= 0xDBFF &&
                    i + 1 < length && characters[i + 1] >= 0xDC00 &&
                    characters[i + 1] <= 0xDFFF;
            if (paired)
                codePoint = 0x10000 + ((codePoint - 0xD800) << 10) +
                        (characters[i + 1] - 0xDC00);

            // Unpaired surrogates are not Unicode scalar values.
            FT_UInt glyph = face != NULL &&
                    !(codePoint >= 0xD800 && codePoint <= 0xDFFF)
                    ? FT_Get_Char_Index(face, codePoint) : 0;
            glyphs[i] = glyph <= UINT16_MAX ? (CGGlyph) glyph : 0;
            // Preserve UTF-16 indexing: the low surrogate has no separate glyph.
            if (paired)
                glyphs[++i] = 0;
        }
    }
}

// The advance of the glyph for layout: the unscaled and unhinted design width at
// the exact point size (the layout code takes it as the glyph's own advance).
- (CGPoint) positionOfGlyph: (CGGlyph) current
            precededByGlyph: (CGGlyph) previous
                  isNominal: (BOOL *) isNominalp
{
    *isNominalp = YES;

    if (!current)
        return NSZeroPoint;

    CGSize advance = CGSizeZero;
    [self getAdvancements: &advance forGlyphs: &current count: 1];
    // The kerning with the glyph before is folded into the width of the glyph
    // that follows it, so the widths of a run still add up to the kerned line.
    return CGPointMake(advance.width + [self kerningBetweenGlyph: previous andGlyph: current],
                       advance.height);
}

// Pair kerning from the face's kern table, in design units scaled to the
// exact point size. Fonts that carry their pair adjustments only in OpenType
// layout tables (GPOS) have none here.
- (CGFloat) kerningBetweenGlyph: (CGGlyph) first andGlyph: (CGGlyph) second {
    if (first == 0 || second == 0 || _unitsPerEm == 0)
        return 0;
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];
        FT_Vector delta;
        if (face == NULL || !FT_HAS_KERNING(face) ||
            FT_Get_Kerning(face, first, second, FT_KERNING_UNSCALED, &delta) != 0)
            return 0;
        return delta.x * _size / _unitsPerEm;
    }
}

// FreeType reports the face's post table underline metrics in font units,
// with negative positions below the baseline, as CoreText does.
- (CGFloat) underlinePosition {
    FT_Face face = [(O2Font_freetype *) _font face];
    if (face == NULL || _unitsPerEm == 0)
        return 0;
    return face->underline_position * _size / _unitsPerEm;
}

- (CGFloat) underlineThickness {
    FT_Face face = [(O2Font_freetype *) _font face];
    if (face == NULL || _unitsPerEm == 0)
        return 0;
    return face->underline_thickness * _size / _unitsPerEm;
}

- (CFCharacterSetRef) copyCharacterSet {
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];
        if (face == NULL || face->charmap == NULL ||
            face->charmap->encoding != FT_ENCODING_UNICODE)
            return NULL;
    }
    NSCharacterSet *set = O2FontGetCoveredCharacterSet((O2FontRef) o2Font);
    return set != nil
            ? CFCharacterSetCreateCopy(kCFAllocatorDefault, (CFCharacterSetRef) set)
            : NULL;
}

- (CGPathRef) createPathForGlyph: (CGGlyph) glyph
                       transform: (CGAffineTransform *) xform
{
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];

        // Unscaled outlines are in font units, so the shared face's size is left alone.
        if (face == NULL || _unitsPerEm == 0 ||
            FT_Load_Glyph(face, glyph, FT_LOAD_NO_SCALE) != 0 ||
            face->glyph->format != FT_GLYPH_FORMAT_OUTLINE)
            return NULL;

        CGFloat unit = _size / _unitsPerEm;
        CGAffineTransform matrix = CGAffineTransformMakeScale(unit, unit);
        if (xform != NULL)
            matrix = CGAffineTransformConcat(matrix, *xform);

        GlyphPathBuilder builder = {CGPathCreateMutable(), &matrix, NO};
        const FT_Outline_Funcs funcs = {glyphPathMoveTo, glyphPathLineTo, glyphPathConicTo,
                                        glyphPathCubicTo, 0, 0};

        if (FT_Outline_Decompose(&face->glyph->outline, &funcs, &builder) != 0) {
            CGPathRelease(builder.path);
            return NULL;
        }
        if (builder.contourOpen)
            CGPathCloseSubpath(builder.path);
        return builder.path;
    }
}

@end
