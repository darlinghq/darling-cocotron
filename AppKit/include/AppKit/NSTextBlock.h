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

#import <Foundation/NSGeometry.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>

@class NSColor, NSMutableArray, NSTextContainer, NSView, NSLayoutManager;

typedef NS_ENUM(NSUInteger, NSTextBlockVerticalAlignment) {
    NSTextBlockTopAlignment,
    NSTextBlockMiddleAlignment,
    NSTextBlockBottomAlignment,
    NSTextBlockBaselineAlignment
};

typedef NS_ENUM(NSUInteger, NSTextBlockValueType) {
    NSTextBlockAbsoluteValueType,
    NSTextBlockPercentageValueType,
};

typedef NS_ENUM(NSUInteger, NSTextBlockDimension) {
    NSTextBlockWidth,
    NSTextBlockMinimumWidth,
    NSTextBlockMaximumWidth,
    NSTextBlockHeight,
    NSTextBlockMinimumHeight,
    NSTextBlockMaximumHeight,
};

typedef NS_ENUM(NSUInteger, NSTextBlockLayer) {
    NSTextBlockPadding,
    NSTextBlockBorder,
    NSTextBlockMargin,
};

// Tells the implementation (UIFoundation) that the instance variables are in
// the extra-state structure, to be reached with NS_EXTRA.
#define _NS_HAS_EXTRA_IVARS_NSTextBlock 1

@interface NSTextBlock : NSObject {
    NS_LEGACY_IVAR_PAD(_NSTextBlockReserved, 24)
    NS_EXTRA_IVARS_BEGIN(NSTextBlock)
    NSColor *_backgroundColor;
    NSMutableArray *_borderColors;
    NSTextBlockVerticalAlignment _verticalAlignment;
    CGFloat _contentWidth;
    NSTextBlockValueType _contentWidthValueType;
    CGFloat _dimensionValues[NSTextBlockMaximumHeight + 1];
    CGFloat _dimensionValueTypes[NSTextBlockMaximumHeight + 1];
    CGFloat _layerWidths[NSTextBlockMargin + 1][NSMaxYEdge + 1];
    CGFloat _layerValueTypes[NSTextBlockMargin + 1][NSMaxYEdge + 1];
    NS_EXTRA_IVARS_END(NSTextBlock)
}

- init;

- (NSColor *) backgroundColor;
- (NSColor *) borderColorForEdge: (NSRectEdge) edge;
- (NSTextBlockVerticalAlignment) verticalAlignment;
- (CGFloat) contentWidth;
- (NSTextBlockValueType) contentWidthValueType;
- (CGFloat) valueForDimension: (NSTextBlockDimension) dimension;
- (NSTextBlockValueType) valueTypeForDimension:
        (NSTextBlockDimension) dimension;
- (CGFloat) widthForLayer: (NSTextBlockLayer) layer edge: (NSRectEdge) edge;
- (NSTextBlockValueType) widthValueTypeForLayer: (NSTextBlockLayer) layer
                                           edge: (NSRectEdge) edge;

- (void) setBackgroundColor: (NSColor *) color;
- (void) setBorderColor: (NSColor *) color;
- (void) setBorderColor: (NSColor *) color forEdge: (NSRectEdge) edge;
- (void) setVerticalAlignment: (NSTextBlockVerticalAlignment) alignment;
- (void) setContentWidth: (CGFloat) width type: (NSTextBlockValueType) type;
- (void) setValue: (CGFloat) value
                type: (NSTextBlockValueType) type
        forDimension: (NSTextBlockDimension) dimension;
- (void) setWidth: (CGFloat) value
             type: (NSTextBlockValueType) type
         forLayer: (NSTextBlockLayer) layer;
- (void) setWidth: (CGFloat) value
             type: (NSTextBlockValueType) type
         forLayer: (NSTextBlockLayer) layer
             edge: (NSRectEdge) edge;

- (NSRect) rectForLayoutAtPoint: (NSPoint) point
                         inRect: (NSRect) rect
                  textContainer: (NSTextContainer *) textContainer
                 characterRange: (NSRange) range;
- (NSRect) boundsRectForContentRect: (NSRect) contentRect
                             inRect: (NSRect) rect
                      textContainer: (NSTextContainer *) textContainer
                     characterRange: (NSRange) range;

- (void) drawBackgroundWithFrame: (NSRect) frame
                          inView: (NSView *) view
                  characterRange: (NSRange) range
                   layoutManager: (NSLayoutManager *) layoutManager;

@end
