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

#import <CoreGraphics/CGFont.h>
#import <Onyx2D/O2Font.h>

CGFontRef CGFontCreateWithFontName(CFStringRef name) {
    return (CGFontRef)O2FontCreateWithFontName((NSString *) name);
}

CGFontRef CGFontRetain(CGFontRef self) {
    return (CGFontRef)O2FontRetain((O2FontRef)self);
}

void CGFontRelease(CGFontRef self) {
    O2FontRelease((O2FontRef)self);
}

CFStringRef CGFontCopyFullName(CGFontRef self) {
    return (CFStringRef) O2FontCopyFullName((O2FontRef)self);
}

int CGFontGetUnitsPerEm(CGFontRef self) {
    return O2FontGetUnitsPerEm((O2FontRef)self);
}

int CGFontGetAscent(CGFontRef self) {
    return O2FontGetAscent((O2FontRef)self);
}

int CGFontGetDescent(CGFontRef self) {
    return O2FontGetDescent((O2FontRef)self);
}

int CGFontGetLeading(CGFontRef self) {
    return O2FontGetLeading((O2FontRef)self);
}

int CGFontGetCapHeight(CGFontRef self) {
    return O2FontGetCapHeight((O2FontRef)self);
}

int CGFontGetXHeight(CGFontRef self) {
    return O2FontGetXHeight((O2FontRef)self);
}

CGFloat CGFontGetItalicAngle(CGFontRef self) {
    return O2FontGetItalicAngle((O2FontRef)self);
}

CGFloat CGFontGetStemV(CGFontRef self) {
    return O2FontGetStemV((O2FontRef)self);
}

CGRect CGFontGetFontBBox(CGFontRef self) {
    return O2FontGetFontBBox((O2FontRef)self);
}

size_t CGFontGetNumberOfGlyphs(CGFontRef self) {
    return O2FontGetNumberOfGlyphs((O2FontRef)self);
}

bool CGFontGetGlyphAdvances(CGFontRef self, const CGGlyph *glyphs, size_t count,
                            int *advances)
{
    return O2FontGetGlyphAdvances((O2FontRef)self, glyphs, count, advances);
}

CGGlyph CGFontGetGlyphWithGlyphName(CGFontRef self, CFStringRef name) {
    return O2FontGetGlyphWithGlyphName((O2FontRef)self, name);
}

CFStringRef CGFontCopyGlyphNameForGlyph(CGFontRef self, CGGlyph glyph) {
    return (CFStringRef) O2FontCopyGlyphNameForGlyph((O2FontRef)self, glyph);
}

CFDataRef CGFontCopyTableForTag(CGFontRef self, uint32_t tag) {
    return (CFDataRef) O2FontCopyTableForTag((O2FontRef)self, tag);
}

CGFontRef _Nullable CGFontCreateWithDataProvider(CGDataProviderRef _Nullable provider)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return nil;
}

CFStringRef const kCGFontVariationAxisName = CFSTR("kCGFontVariationAxisName");
CFStringRef const kCGFontVariationAxisMinValue = CFSTR("kCGFontVariationAxisMinValue");
CFStringRef const kCGFontVariationAxisDefaultValue = CFSTR("kCGFontVariationAxisDefaultValue");
CFStringRef const kCGFontVariationAxisMaxValue = CFSTR("kCGFontVariationAxisMaxValue");

CFArrayRef CGFontCopyTableTags(CGFontRef font) {
    return font ? O2FontCopyTableTags((O2FontRef)font) : NULL;
}
