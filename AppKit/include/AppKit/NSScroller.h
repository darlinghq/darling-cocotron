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
#import <AppKit/NSControl.h>

typedef NS_ENUM(NSUInteger, NSScrollerPart) {
    NSScrollerNoPart = 0,
    NSScrollerDecrementPage = 1,
    NSScrollerKnob = 2,
    NSScrollerIncrementPage = 3,
    NSScrollerDecrementLine = 4,
    NSScrollerIncrementLine = 5,
    NSScrollerKnobSlot = 6,
};

typedef NS_ENUM(NSUInteger, NSScrollerArrow) {
    NSScrollerIncrementArrow,
    NSScrollerDecrementArrow
};

typedef NS_ENUM(NSUInteger, NSScrollArrowPosition) {
    NSScrollerArrowsMaxEnd = 0,
    NSScrollerArrowsMinEnd = 1,
    NSScrollerArrowsNone = 2,
    NSScrollerArrowsDefaultSetting = NSScrollerArrowsMaxEnd,
};

typedef NS_ENUM(NSUInteger, NSUsableScrollerParts) {
    NSNoScrollerParts = 0,
    NSOnlyScrollerArrows = 1,
    NSAllScrollerParts = 2,
};

typedef NS_ENUM(NSInteger, NSScrollerStyle) {
    NSScrollerStyleLegacy,
    NSScrollerStyleOverlay,
};

typedef NS_ENUM(NSInteger, NSScrollerKnobStyle) {
    NSScrollerKnobStyleDefault = 0,
    NSScrollerKnobStyleDark = 1,
    NSScrollerKnobStyleLight = 2,
};

// Legacy ObjC ABI (i386): instance size must stay 0x78, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSScroller : NSControl {
    float _floatValue;
    CGFloat _knobProportion;
    NS_LEGACY_IVAR_PAD(_NSScrollerReserved1, 16)
    NS_EXTRA_IVARS_BEGIN(NSScroller)
        id _target;
        SEL _action;
        struct {
            unsigned isHoriz : 1;
            NSUsableScrollerParts partsUsable : 2;
        } sFlags;

        NSScrollArrowPosition _arrowsPosition;
        NSControlSize _controlSize;

        NSScrollerPart _hitPart;
        BOOL _isEnabled;
        BOOL _isHighlighted;

        NSScrollerStyle _scrollerStyle;
        NSScrollerKnobStyle _knobStyle;
        NSControlTint _controlTint;
    NS_EXTRA_IVARS_END(NSScroller)
}

+ (CGFloat) scrollerWidth;
+ (CGFloat) scrollerWidthForControlSize: (NSControlSize) controlSize
                          scrollerStyle: (NSScrollerStyle) scrollerStyle;

- (NSControlTint) controlTint;
- (void) setControlTint: (NSControlTint) tint;
- (CGFloat) knobProportion;
- (void) setKnobProportion: (CGFloat) proportion;
- (NSScrollArrowPosition) arrowsPosition;
- (NSControlSize) controlSize;
- (NSScrollerStyle) scrollerStyle;
- (NSScrollerKnobStyle) knobStyle;
+ (NSScrollerStyle) preferredScrollerStyle;

- (void) setFloatValue: (float) zeroToOneValue
        knobProportion: (CGFloat) zeroToOneKnob;
- (void) setArrowsPosition: (NSScrollArrowPosition) position;
- (void) setControlSize: (NSControlSize) value;
- (void) setScrollerStyle: (NSScrollerStyle) style;
- (void) setKnobStyle: (NSScrollerKnobStyle) style;

- (NSRect) rectForPart: (NSScrollerPart) part;
- (void) checkSpaceForParts;
- (NSUsableScrollerParts) usableParts;

- (void) highlight: (BOOL) flag;

- (void) drawKnobSlotInRect: (NSRect) rect highlight: (BOOL) flag;
- (void) drawParts;
- (void) drawArrow: (NSScrollerArrow) arrow highlight: (BOOL) flag;
- (void) drawKnob;

- (NSScrollerPart) hitPart;
- (NSScrollerPart) testPart: (NSPoint) point;
- (void) trackKnob: (NSEvent *) event;
- (void) trackScrollButtons: (NSEvent *) event;

@end

APPKIT_EXPORT NSNotificationName const NSPreferredScrollerStyleDidChangeNotification;
