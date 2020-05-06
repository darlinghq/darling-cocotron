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
#import <Foundation/NSObject.h>

@class NSAttributedString;

@protocol NSGlyphStorage
- (NSUInteger) layoutOptions;
- (NSAttributedString *) attributedString;

- (void) insertGlyphs: (const NSGlyph *) glyphs
                     length: (NSUInteger) length
    forStartingGlyphAtIndex: (NSUInteger) glyphIndex
             characterIndex: (NSUInteger) characterIndex;

- (void) setIntAttribute: (NSInteger) intAttribute
                   value: (NSInteger) value
         forGlyphAtIndex: (NSUInteger) glyphIndex;
@end

@interface NSGlyphGenerator : NSObject {
}

+ sharedGlyphGenerator;

- (void) generateGlyphsForGlyphStorage: (id<NSGlyphStorage>) glyphStorage
             desiredNumberOfCharacters: (NSUInteger) numberOfCharacters
                            glyphIndex: (NSUInteger *) glyphIndex
                        characterIndex: (NSUInteger *) characterIndex;

@end
