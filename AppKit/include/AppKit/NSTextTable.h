/* Copyright (c) 2007 Christopher J. W. Lloyd

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

#import <AppKit/NSTextBlock.h>
#import <AppKit/AppKitIvarLayout.h>

typedef NS_ENUM(NSUInteger, NSTextTableLayoutAlgorithm) {
    NSTextTableAutomaticLayoutAlgorithm,
    NSTextTableFixedLayoutAlgorithm
};

// Tells the implementation (UIFoundation) that the instance variables are in
// the extra-state structure, to be reached with NS_EXTRA.
#define _NS_HAS_EXTRA_IVARS_NSTextTable 1

@interface NSTextTable : NSTextBlock {
    NS_LEGACY_IVAR_PAD(_NSTextTableReserved, 16)
    NS_EXTRA_IVARS_BEGIN(NSTextTable)
    unsigned _numberOfColumns;
    BOOL _collapsesBorders;
    BOOL _hidesEmptyCells;
    NSTextTableLayoutAlgorithm _layoutAlgorithm;
    NS_EXTRA_IVARS_END(NSTextTable)
}

- (unsigned) numberOfColumns;
- (BOOL) collapsesBorders;
- (BOOL) hidesEmptyCells;
- (NSTextTableLayoutAlgorithm) layoutAlgorithm;

- (void) setNumberOfColumns: (unsigned) numberOfColumns;
- (void) setCollapsesBorders: (BOOL) yorn;
- (void) setHidesEmptyCells: (BOOL) yorn;
- (void) setLayoutAlgorithm: (NSTextTableLayoutAlgorithm) algorithm;

#if 0
-(NSRect)boundsRectForBlock:(NSTextTableBlock *)block contentRect:(NSRect)contentRect inRect:(NSRect)rect textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)range;
-(NSRect)rectForBlock:(NSTextTableBlock *)block layoutAtPoint:(NSPoint)point inRect:(NSRect)rect textContainer:(NSTextContainer *)textContainer characterRange:(NSRange)range;

-(void)drawBackgroundForBlock:(NSTextTableBlock *)block withFrame:(NSRect)frame inView:(NSView *)view characterRange:(NSRange)range layoutManager:(NSLayoutManager *)layoutManager;
#endif

@end
