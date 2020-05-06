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

#import <CoreText/KTFont.h>

#ifdef DARLING
#define __linux__
#endif

#import <ft2build.h>
#import <stddef.h>

#ifdef LINUX
typedef int ptrdiff_t;
#endif
#import FT_FREETYPE_H
#import FT_RENDER_H

#ifdef DARLING
#undef __linux__
#endif

@class NSSet;

@interface KTFont_FT : KTFont

- (CGPoint) positionOfGlyph: (CGGlyph) current
            precededByGlyph: (CGGlyph) previous
                  isNominal: (BOOL *) isNominalp;
- (void) getAdvancements: (CGSize *) advancements
               forGlyphs: (const CGGlyph *) glyphs
                   count: (NSUInteger) count;

@end
