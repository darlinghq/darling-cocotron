/* Copyright (c) 2006-2008 Christopher J. W. Lloyd

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
#import <CoreText/KTFont.h>
#import <Foundation/NSArray.h>
#import <Onyx2D/O2Exceptions.h>

@implementation KTFont

- initWithFont: (CGFontRef) font size: (CGFloat) size {
    _font = CGFontRetain(font);
    _unitsPerEm = CGFontGetUnitsPerEm(_font);
    _size = size;
    return self;
}

- initWithUIFontType: (CTFontUIFontType) uiFontType
                size: (CGFloat) size
            language: (NSString *) language
{
    O2InvalidAbstractInvocation();
    return nil;
}

- (void) dealloc {
    CGFontRelease(_font);
    [super dealloc];
}

- (CFTypeID) _cfTypeID {
    return CTFontGetTypeID();
}

- (CFStringRef) copyName {
    return CGFontCopyFullName(_font);
}

- (CGFontRef) copyGraphicsFont {
    return CGFontRetain(_font);
}

// A CTFont can be used where an NSFont is expected (the two are toll-free
// bridged), so answer NSFont's identity methods too.
- (NSString *) fontName {
    return [(NSString *) CTFontCopyPostScriptName((CTFontRef) self) autorelease];
}

- (NSString *) familyName {
    return [(NSString *) CTFontCopyFamilyName((CTFontRef) self) autorelease];
}

- (id) printerFont {
    return self;
}

- (id) screenFont {
    return self;
}

- (CGFloat) pointSize {
    return _size;
}

- (CGFloat) fontSize {
    return _size;
}

- (CGRect) boundingRect {
    if (_unitsPerEm == 0)
        return CGRectZero;
    CGRect box = CGFontGetFontBBox(_font);
    CGFloat scale = _size / _unitsPerEm;
    return CGRectMake(box.origin.x * scale, box.origin.y * scale,
                      box.size.width * scale, box.size.height * scale);
}

- (CGFloat) ascender {
    CGFloat ascent = CGFontGetAscent(_font);

    return (ascent / _unitsPerEm) * _size;
}

// CT descenter is the opposite of the CG one on Cocoa
- (CGFloat) descender {
    CGFloat descent = CGFontGetDescent(_font);
    return -(descent / _unitsPerEm) * _size;
}

- (CGFloat) leading {
    CGFloat leading = CGFontGetLeading(_font);

    return (leading / _unitsPerEm) * _size;
}

- (CGFloat) underlineThickness {
    O2InvalidAbstractInvocation();
    return 0;
}

- (CGFloat) underlinePosition {
    O2InvalidAbstractInvocation();
    return 0;
}

- (CGFloat) italicAngle {
    return CGFontGetItalicAngle(_font);
}

- (CGFloat) xHeight {
    CGFloat xHeight = CGFontGetXHeight(_font);

    return (xHeight / _unitsPerEm) * _size;
}

- (CGFloat) capHeight {
    CGFloat capHeight = CGFontGetCapHeight(_font);

    return (capHeight / _unitsPerEm) * _size;
}

- (NSUInteger) numberOfGlyphs {
    return CGFontGetNumberOfGlyphs(_font);
}

- (CGPoint) positionOfGlyph: (CGGlyph) current
            precededByGlyph: (CGGlyph) previous
                  isNominal: (BOOL *) isNominalp
{
    int advancement;

    if (previous == 0)
        return CGPointMake(0, 0);

    *isNominalp = YES;
    CGFontGetGlyphAdvances(_font, &previous, 1, &advancement);

    return CGPointMake(((CGFloat) advancement / _unitsPerEm) * _size, 0);
}

- (void) getGlyphs: (CGGlyph *) glyphs
        forCharacters: (const unichar *) characters
               length: (NSUInteger) length
{
    int i;

    for (i = 0; i < length; i++) {
        uint16_t code = characters[i];
        uint8_t group = code >> 8;
        uint8_t index = code & 0xFF;

        if (_twoLevel[group] == NULL)
            glyphs[i] = 0;
        else
            glyphs[i] = _twoLevel[group][index];
    }
}

- (void) getAdvancements: (CGSize *) advancements
               forGlyphs: (const CGGlyph *) glyphs
                   count: (NSUInteger) count
{
    int advances[count];

    CGFontGetGlyphAdvances(_font, glyphs, count, advances);
    for (int i = 0; i < count; i++) {
        advancements[i].width =
                ((CGFloat) advances[i] / (CGFloat) _unitsPerEm) * _size;
        advancements[i].height = 0;
    }
}

// The rest of NSFont's glyph interface. A CTFontRef is toll-free bridged to
// NSFont, so code holding one can send these messages to it. The glyph
// parameters are NSGlyph (NSUInteger) as in NSFont.

- (CGRect) boundingRectForGlyph: (NSUInteger) glyph {
    CGGlyph cgGlyph = (CGGlyph) glyph;
    CGRect rect = CGRectZero;
    CTFontGetBoundingRectsForGlyphs((CTFontRef) self, kCTFontOrientationDefault, &cgGlyph,
                                    &rect, 1);
    return rect;
}

// NSNativeShortGlyphPacking
- (NSUInteger) glyphPacking {
    return 0;
}

- (NSUInteger) glyphWithName: (NSString *) name {
    return name == nil ? 0 : CTFontGetGlyphWithName((CTFontRef) self, (CFStringRef) name);
}

- (BOOL) glyphIsEncoded: (NSUInteger) glyph {
    return glyph < [self numberOfGlyphs];
}

- (CGSize) advancementForGlyph: (NSUInteger) glyph {
    CGGlyph cgGlyph = (CGGlyph) glyph;
    CGSize advance = CGSizeZero;
    [self getAdvancements: &advance forGlyphs: &cgGlyph count: 1];
    return advance;
}

- (CGSize) maximumAdvancement {
    enum { batchSize = 256 };
    CGGlyph glyphs[batchSize];
    CGSize advances[batchSize];
    CGSize max = CGSizeZero;
    NSUInteger glyphCount = [self numberOfGlyphs];

    for (NSUInteger offset = 0; offset < glyphCount; offset += batchSize) {
        NSUInteger batch = MIN((NSUInteger) batchSize, glyphCount - offset);
        for (NSUInteger i = 0; i < batch; i++)
            glyphs[i] = (CGGlyph) (offset + i);
        [self getAdvancements: advances forGlyphs: glyphs count: batch];
        for (NSUInteger i = 0; i < batch; i++) {
            max.width = MAX(max.width, advances[i].width);
            max.height = MAX(max.height, advances[i].height);
        }
    }
    return max;
}

- (CFCharacterSetRef) copyCharacterSet {
    return NULL;
}

- (CGPathRef) createPathForGlyph: (CGGlyph) glyph
                       transform: (CGAffineTransform *) xform
{
    // Glyph outlines are not available; CTFontCreatePathForGlyph reports
    // that as NULL.
    return NULL;
}

@end
