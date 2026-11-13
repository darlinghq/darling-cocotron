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

- initWithUIFontType: (CTFontUIFontType) uiFontType
                size: (CGFloat) size
            language: (NSString *) language
{
    O2Font *font = nil;

    switch (uiFontType) {

    case kCTFontMenuTitleFontType:
    case kCTFontMenuItemFontType:
        if (size == 0)
            size = 12;
        font = O2FontCreateWithFontName(@"San Francisco");
        break;

    default:
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

- (void) getAdvancements: (CGSize *) advancements
               forGlyphs: (const CGGlyph *) glyphs
                   count: (NSUInteger) count
{
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];

        int i;
        FT_Set_Pixel_Sizes(face, _size, _size);

        for (i = 0; i < count; i++) {
            FT_Load_Glyph(face, glyphs[i], FT_LOAD_DEFAULT);
            advancements[i] = CGSizeMake(face->glyph->advance.x / (O2Float)(2 << 5),
                           face->glyph->advance.y / (O2Float)(2 << 5));
        }
    }
}

- (CGPoint) positionOfGlyph: (CGGlyph) current
            precededByGlyph: (CGGlyph) previous
                  isNominal: (BOOL *) isNominalp
{
    O2Font_freetype *o2Font = (O2Font_freetype *) _font;
    @synchronized(o2Font) {
        FT_Face face = [o2Font face];

        *isNominalp = YES;

        if (!current)
            return NSZeroPoint;

        FT_Set_Pixel_Sizes(face, _size, _size);

        FT_Load_Glyph(face, current, FT_LOAD_DEFAULT);
        return NSMakePoint(face->glyph->advance.x / (O2Float)(2 << 5),
                           face->glyph->advance.y / (O2Float)(2 << 5));
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
