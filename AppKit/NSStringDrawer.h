/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2009 Markus Hitter <mah@jump-ing.de>

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

#import <AppKit/AppKitExport.h>
#import <AppKit/NSParagraphStyle.h>
#import <Foundation/Foundation.h>

@class NSTextStorage, NSLayoutManager, NSTextContainer;

APPKIT_EXPORT const CGFloat NSStringDrawerLargeDimension;

@interface NSStringDrawer : NSObject {
    NSTextStorage *_textStorage;
    NSLayoutManager *_layoutManager;
    NSTextContainer *_textContainer;
    NSCache *_cache;
    NSCache *_drawCache;
}

+ (NSStringDrawer *) sharedStringDrawer;

// Use a size of NSZeroSize for unlimited dimensions.
- (NSSize) sizeOfString: (NSString *) string
         withAttributes: (NSDictionary *) attributes
                 inSize: (NSSize) maxSize;
- (void) drawString: (NSString *) string
        withAttributes: (NSDictionary *) attributes
                inRect: (NSRect) rect;
// Use a size of NSZeroSize for unlimited dimensions.
- (void) drawString: (NSString *) string
        withAttributes: (NSDictionary *) attributes
               atPoint: (NSPoint) point
                inSize: (NSSize) maxSize;

// Use a size of NSZeroSize for unlimited dimensions.
- (NSSize) sizeOfAttributedString: (NSAttributedString *) astring
                           inSize: (NSSize) maxSize;
- (void) drawAttributedString: (NSAttributedString *) astring
                       inRect: (NSRect) rect;
// Use a size of NSZeroSize for unlimited dimensions.
- (void) drawAttributedString: (NSAttributedString *) astring
                      atPoint: (NSPoint) point
                       inSize: (NSSize) maxSize;

// Wraps the string to maxSize.width and keeps only the lines that fit
// completely in maxSize.height (always at least the first one). Returns the
// size of those lines; trailing white space of a wrapped line is not counted.
// *lastLine is the character range of the last kept line and *hasHiddenText
// says whether text follows it. Either may be NULL.
- (NSSize) sizeOfAttributedString: (NSAttributedString *) astring
                    fittingInSize: (NSSize) maxSize
                     lastLineRange: (NSRange *) lastLine
                    hasHiddenText: (BOOL *) hasHiddenText;

// The same, keeping at most maximumNumberOfLines lines (0 keeps as many as fit).
- (NSSize) sizeOfAttributedString: (NSAttributedString *) astring
                    fittingInSize: (NSSize) maxSize
             maximumNumberOfLines: (NSUInteger) maximumNumberOfLines
                     lastLineRange: (NSRange *) lastLine
                    hasHiddenText: (BOOL *) hasHiddenText;

@end

// strange we need this frequently yet nothing like it is public
@interface NSString (NSStringDrawer_private)

- (void) _clipAndDrawInRect: (NSRect) rect
             withAttributes: (NSDictionary *) attributes
             truncatingTail: (BOOL) truncateTail;

- (void) _clipAndDrawInRect: (NSRect) rect
             withAttributes: (NSDictionary *) attributes;

@end

@interface NSAttributedString (NSStringDrawer_private)

- (void) _clipAndDrawInRect: (NSRect) rect
             lineBreakMode: (NSLineBreakMode) lineBreakMode;

- (void) _clipAndDrawInRect: (NSRect) rect truncatingTail: (BOOL) truncateTail;

- (void) _clipAndDrawInRect: (NSRect) rect;

@end
