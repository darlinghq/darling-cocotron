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
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>

typedef NSInteger NSCharacterCollection;

// Tells the implementation (UIFoundation) that the instance variables are in
// the extra-state structure, to be reached with NS_EXTRA.
#define _NS_HAS_EXTRA_IVARS_NSGlyphInfo 1

@interface NSGlyphInfo : NSObject {
    NS_EXTRA_IVARS_BEGIN(NSGlyphInfo)
    NSUInteger _identifier;
    NSCharacterCollection _collection;
    NSString *_glyphName;
    NS_EXTRA_IVARS_END(NSGlyphInfo)
}

+ (NSGlyphInfo *)
        glyphInfoWithCharacterIdentifier: (NSUInteger) identifier
                              collection: (NSCharacterCollection) collection
                              baseString: (NSString *) baseString;

+ (NSGlyphInfo *) glyphInfoWithGlyph: (NSGlyph) glyph
                             forFont: (NSFont *) font
                          baseString: (NSString *) baseString;
+ (NSGlyphInfo *) glyphInfoWithGlyphName: (NSString *) glyphName
                                 forFont: (NSFont *) font
                              baseString: (NSString *) baseString;

- (NSUInteger) characterIdentifier;
- (NSCharacterCollection) characterCollection;
- (NSString *) glyphName;

@end
