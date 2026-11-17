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

#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>

@class NSTimer;

typedef NS_ENUM(NSUInteger, NSProgressIndicatorStyle) {
    NSProgressIndicatorStyleBar = 0,
    NSProgressIndicatorStyleSpinning = 1
} NS_SWIFT_NAME(NSProgressIndicator.Style);

#define NSProgressIndicatorBarStyle NSProgressIndicatorStyleBar
#define NSProgressIndicatorSpinningStyle NSProgressIndicatorStyleSpinning

typedef NS_ENUM(NSUInteger, NSProgressIndicatorThickness) {
    NSProgressIndicatorPreferredThickness = 14,
    NSProgressIndicatorPreferredSmallThickness = 10,
    NSProgressIndicatorPreferredLargeThickness = 18,
    NSProgressIndicatorPreferredAquaThickness = 12,
};

// Legacy ObjC ABI (i386): instance size is 0x90, Apple's, with the flags and
// the three doubles where Apple has them.
@interface NSProgressIndicator : NSView {
    BOOL _isBezeled;
    BOOL _isIndeterminate;
    BOOL _usesThreadedAnimation;
    BOOL _displayWhenStopped;
    double _minValue;
    double _maxValue;
    double _value;
    NSTimer *_animationTimer;
    NSTimeInterval _animationDelay;
    double _animationValue;
    NSProgressIndicatorStyle _style;
    NSControlSize _size;
    NSControlTint _tint;
    BOOL _endThreadedAnimation;
}

@property NSProgressIndicatorStyle style;
@property NSControlSize controlSize;
@property(nonatomic) NSControlTint controlTint;
@property(nonatomic, getter=isDisplayedWhenStopped) BOOL displayedWhenStopped;
@property(nonatomic) BOOL usesThreadedAnimation;

@property double minValue;
@property double maxValue;
@property double doubleValue;

@property(nonatomic) NSTimeInterval animationDelay;
@property (getter=isIndeterminate) BOOL indeterminate;
@property(nonatomic, getter=isBezeled) BOOL bezeled;



- (void) incrementBy: (double) value;

- (void) sizeToFit;

- (void) startAnimation: sender;
- (void) stopAnimation: sender;
- (void) animate: sender;

@end
