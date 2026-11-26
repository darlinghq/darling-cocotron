#ifndef CGFONT_H
#define CGFONT_H

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

#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CoreGraphicsExport.h>
#import <CoreGraphics/CGDataProvider.h>

#include <CoreFoundation/CoreFoundation.h>

// DARLING: SDK consumers get the struct tag macOS's SDK has, which code that
// forward-declares the type relies on; Darling's own build keeps its own.
#ifdef DARLING
typedef struct CF_BRIDGED_TYPE(id) O2Font *CGFontRef;
#else
typedef struct CF_BRIDGED_TYPE(id) CGFont *CGFontRef;
#endif

typedef uint16_t CGFontIndex;
typedef CGFontIndex CGGlyph;

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CFArrayRef CGFontCopyTableTags(CGFontRef font);

COREGRAPHICS_EXPORT CGFontRef CGFontCreateWithFontName(CFStringRef name);
COREGRAPHICS_EXPORT CGFontRef CGFontRetain(CGFontRef self);
COREGRAPHICS_EXPORT void CGFontRelease(CGFontRef self);

COREGRAPHICS_EXPORT CFStringRef CGFontCopyFullName(CGFontRef self);
COREGRAPHICS_EXPORT CFStringRef CGFontCopyPostScriptName(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetUnitsPerEm(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetAscent(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetDescent(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetLeading(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetCapHeight(CGFontRef self);
COREGRAPHICS_EXPORT int CGFontGetXHeight(CGFontRef self);
COREGRAPHICS_EXPORT CGFloat CGFontGetItalicAngle(CGFontRef self);
COREGRAPHICS_EXPORT CGFloat CGFontGetStemV(CGFontRef self);
COREGRAPHICS_EXPORT CGRect CGFontGetFontBBox(CGFontRef self);

COREGRAPHICS_EXPORT size_t CGFontGetNumberOfGlyphs(CGFontRef self);
COREGRAPHICS_EXPORT bool CGFontGetGlyphAdvances(CGFontRef self,
                                                const CGGlyph *glyphs,
                                                size_t count, int *advances);

COREGRAPHICS_EXPORT CGGlyph CGFontGetGlyphWithGlyphName(CGFontRef self,
                                                        CFStringRef name);
COREGRAPHICS_EXPORT CFStringRef CGFontCopyGlyphNameForGlyph(CGFontRef self,
                                                            CGGlyph glyph);

COREGRAPHICS_EXPORT CFDataRef CGFontCopyTableForTag(CGFontRef self,
                                                    uint32_t tag);

COREGRAPHICS_EXPORT CGFontRef CGFontCreateWithDataProvider(CGDataProviderRef provider);

COREGRAPHICS_EXPORT CFStringRef const kCGFontVariationAxisName;
COREGRAPHICS_EXPORT CFStringRef const kCGFontVariationAxisMinValue;
COREGRAPHICS_EXPORT CFStringRef const kCGFontVariationAxisDefaultValue;
COREGRAPHICS_EXPORT CFStringRef const kCGFontVariationAxisMaxValue;

/* The variation axes of a variable font: an array of dictionaries with the kCGFontVariationAxis keys above (the
 * name, and the minimum, default and maximum values as numbers). NULL for a font without variation axes. */
COREGRAPHICS_EXPORT CFArrayRef CGFontCopyVariationAxes(CGFontRef font);
/* The current variation settings: a dictionary from axis name to value; NULL for a font without variation axes. */
COREGRAPHICS_EXPORT CFDictionaryRef CGFontCopyVariations(CGFontRef font);
/* A font with the given axis values (a dictionary from axis name to number; unknown names are ignored). The font
 * itself is returned (retained) when there is nothing to apply. */
COREGRAPHICS_EXPORT CGFontRef CGFontCreateCopyWithVariations(CGFontRef font, CFDictionaryRef variations);

CF_IMPLICIT_BRIDGING_DISABLED

#endif /* CGFONT_H */
