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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSLayoutManager.h>
#import <Foundation/Foundation.h>

@class NSTextView;

typedef NS_ENUM(NSUInteger, NSLineSweepDirection) {
    NSLineSweepUp,
    NSLineSweepDown,
    NSLineSweepLeft,
    NSLineSweepRight,
};

typedef NS_ENUM(NSUInteger, NSLineMovementDirection) {
    NSLineDoesntMove,
    NSLineMovesUp,
    NSLineMovesDown,
    NSLineMovesLeft,
    NSLineMovesRight,
};

// Legacy ObjC ABI (i386): instance size must stay 0x1c, Apple's; the ivars
// before the extras keep their position in the original order. Add new state
// to the extra struct, never as an ivar.
@interface NSTextContainer : NSObject {
    NSLayoutManager *_layoutManager;
    NSTextView *_textView;
    NSSize _size;
    CGFloat _lineFragmentPadding;
    NS_EXTRA_IVARS_BEGIN(NSTextContainer)
        NSUInteger _maximumNumberOfLines;
        BOOL _widthTracksTextView;
        BOOL _heightTracksTextView;
    NS_EXTRA_IVARS_END(NSTextContainer)
}

- initWithContainerSize: (NSSize) size;

@property(nonatomic) NSSize containerSize;

@property(nonatomic, retain) NSTextView *textView;
@property(readonly) NSTextLayoutOrientation layoutOrientation;
@property(nonatomic) BOOL widthTracksTextView;
@property(nonatomic) BOOL heightTracksTextView;

@property(nonatomic, retain) NSLayoutManager *layoutManager;

@property(nonatomic) CGFloat lineFragmentPadding;
@property(nonatomic) NSUInteger maximumNumberOfLines;



- (void) replaceLayoutManager: (NSLayoutManager *) layoutManager;


- (BOOL) isSimpleRectangularTextContainer;

- (BOOL) containsPoint: (NSPoint) point;

- (NSRect) lineFragmentRectForProposedRect: (NSRect) proposed
                            sweepDirection: (NSLineSweepDirection) sweep
                         movementDirection: (NSLineMovementDirection) movement
                             remainingRect: (NSRectPointer) remaining;

@end
