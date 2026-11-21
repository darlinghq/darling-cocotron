/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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
#import "NSViewLayoutInternal.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGraphicsContextFunctions.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <AppKit/NSProgressIndicator.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSProgressIndicator

// A progress indicator hugs like a control (observed on macOS 10.14.4 and 26.7.3).
- (NSLayoutPriority) _defaultContentHuggingPriorityForOrientation: (NSLayoutConstraintOrientation) orientation {
    return orientation == NSLayoutConstraintOrientationVertical ? NSLayoutPriorityDefaultHigh : NSLayoutPriorityDefaultLow;
}


- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned flags = [keyed decodeIntForKey: @"NSpiFlags"];

        _minValue = [keyed decodeDoubleForKey: @"NSMinValue"];
        _maxValue = [keyed decodeDoubleForKey: @"NSMaxValue"];
        _value = _minValue;
        _animationDelay = 5.0 / 60.0;
        _animationTimer = nil;
        _animationValue = 0;
        _style = (flags & 0x1000) ? NSProgressIndicatorSpinningStyle
                                  : NSProgressIndicatorBarStyle;
        _size = (flags & 0x100) ? NSSmallControlSize : NSRegularControlSize;
        _displayWhenStopped = (flags & 0x2000) ? NO : YES; // inverted
        _isBezeled = YES;
        _isIndeterminate = (flags & 0x02) ? YES : NO;
        _usesThreadedAnimation = NO;
    } else {
        NSInteger version = [coder versionForClassName: @"NSProgressIndicator"];
        char bezeled = 0, indeterminate = 0, sizeByte = 0;

        // The two flag bytes, the range (floats up to version 211, doubles after) and, from
        // version 219, a byte with the control size in bits 2-3 (its other bits have an
        // unknown meaning). The style, the displayed-when-stopped and threaded-animation
        // settings and the value are not archived: the value reads as the minimum.
        if (version <= 211) {
            float minValue, maxValue;
            [coder decodeValuesOfObjCTypes: "ccff", &bezeled, &indeterminate, &minValue, &maxValue];
            _minValue = minValue;
            _maxValue = maxValue;
        } else if (version <= 218) {
            [coder decodeValuesOfObjCTypes: "ccdd", &bezeled, &indeterminate, &_minValue, &_maxValue];
        } else {
            [coder decodeValuesOfObjCTypes: "ccddc", &bezeled, &indeterminate, &_minValue, &_maxValue, &sizeByte];
        }
        _isBezeled = bezeled != 0;
        _isIndeterminate = indeterminate != 0;
        _size = (sizeByte >> 2) & 3;
        _value = _minValue;
        _animationDelay = 5.0 / 60.0;
        _animationTimer = nil;
        _animationValue = 0;
        _style = NSProgressIndicatorBarStyle;
        _displayWhenStopped = YES;
        _usesThreadedAnimation = NO;
    }
    return self;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    _value = 0;
    _minValue = 0;
    _maxValue = 100;
    _animationDelay = 5.0 / 60.0;
    _animationTimer = nil;
    _animationValue = 0;
    _style = NSProgressIndicatorBarStyle;
    _size = NSRegularControlSize;
    _tint = 0;
    // documented default: the indicator is shown while it is not animating
    _displayWhenStopped = YES;
    _isBezeled = YES;
    _isIndeterminate = YES;
    _usesThreadedAnimation = NO;

    return self;
}

- (void) _invalidateTimer {
    if (_animationTimer != nil) {
        [self willChangeValueForKey: @"animate"];
        [_animationTimer invalidate];
        [_animationTimer release];
        _animationTimer = nil;
        [self didChangeValueForKey: @"animate"];
    }
}

- (void) _buildTimer {
    if (_animationTimer == nil) {
        [self willChangeValueForKey: @"animate"];
        _animationTimer = [[NSTimer timerWithTimeInterval: _animationDelay
                                                   target: self
                                                 selector: @selector(animate:)
                                                 userInfo: nil
                                                  repeats: YES] retain];

        // FIXME: does it do this? Or does it add it to the current mode?
        // Apple's does work in a modal panel (right?)_
        [[NSRunLoop currentRunLoop] addTimer: _animationTimer
                                     forMode: NSDefaultRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer: _animationTimer
                                     forMode: NSModalPanelRunLoopMode];

        [self didChangeValueForKey: @"animate"];
    }
}

- (void) dealloc {
    [self _invalidateTimer];

    [super dealloc];
}

- (BOOL) isFlipped {
    return YES;
}

// QUIRK: the spinning style is drawn at the size of its control size (32, 16 or 10 points square for the regular,
// small and mini sizes), centred in the view (rounded down), whatever the view's size. Not documented. Evidence:
// black-box renders of NSProgressIndicator on macOS 10.14.4 at 1x in 40 x 40 point views (tier 2).
// Test: test_quirk_spinner_size in tests/appkit-small-controls-aqua.m
- (NSRect) _spinnerRect {
    NSRect bounds = [self bounds];
    CGFloat side = _size == NSSmallControlSize ? 16 : (_size == NSMiniControlSize ? 10 : 32);
    CGFloat left = floor((NSWidth(bounds) - side) / 2), top = floor((NSHeight(bounds) - side) / 2);

    return NSMakeRect(NSMinX(bounds) + left, [self isFlipped] ? NSMinY(bounds) + top : NSMaxY(bounds) - top - side,
                      side, side);
}

- (void) drawIndeterminateCircular {
    // the leading spoke moves clockwise as the animation runs; at rest it is at the top
    NSInteger phase = lround(_animationValue * 11);

    [[self graphicsStyle] drawSpinningProgressIndicatorInRect: [self _spinnerRect] phase: phase];
}

- (void) drawRect: (NSRect) clipRect {
    if (_style == NSProgressIndicatorBarStyle) {
        if (_isIndeterminate) {
            if ([self isDisplayedWhenStopped] || (_animationTimer != nil)) {
                [[self graphicsStyle]
                        drawProgressIndicatorIndeterminate: _bounds
                                                  clipRect: clipRect
                                                   bezeled: _isBezeled
                                                 animation: _animationValue];
            }
        } else {
            double value = (_value - _minValue) / (_maxValue - _minValue);

            [[self graphicsStyle] drawProgressIndicatorDeterminate: _bounds
                                                          clipRect: clipRect
                                                           bezeled: _isBezeled
                                                             value: value];
        }
    } else {
        if ([self isIndeterminate]) {
            if ([self isDisplayedWhenStopped] || (_animationTimer != nil)) {
                [self drawIndeterminateCircular];
            }
        } else {
            double range = _maxValue - _minValue;

            [[self graphicsStyle] drawSpinningProgressPieInRect: [self _spinnerRect]
                                                          value: range > 0 ? (_value - _minValue) / range : 0
                                                        flipped: [self isFlipped]];
        }
    }
}

- (NSProgressIndicatorStyle) style {
    return _style;
}

- (NSControlSize) controlSize {
    return _size;
}

- (NSControlTint) controlTint {
    return _tint;
}

- (BOOL) isDisplayedWhenStopped {
    return _displayWhenStopped;
}

- (BOOL) usesThreadedAnimation {
    return _usesThreadedAnimation;
}

- (double) minValue {
    return _minValue;
}

- (double) maxValue {
    return _maxValue;
}

- (double) doubleValue {
    return _value;
}

- (NSTimeInterval) animationDelay {
    return _animationDelay;
}

- (BOOL) isIndeterminate {
    return _isIndeterminate;
}

- (BOOL) isBezeled {
    return _isBezeled;
}

- (void) setStyle: (NSProgressIndicatorStyle) value {
    _style = value;
    [self sizeToFit];
    [self setNeedsDisplay: YES];
}

- (void) setControlSize: (NSControlSize) value {
    _size = value;
    [self sizeToFit];
    [self setNeedsDisplay: YES];
}

- (void) setControlTint: (NSControlTint) value {
    _tint = value;
    [self setNeedsDisplay: YES];
}

- (void) setDisplayedWhenStopped: (BOOL) value {
    _displayWhenStopped = value;
    [self setNeedsDisplay: YES];
}

- (void) setUsesThreadedAnimation: (BOOL) value {
    // This currently has no effect on the indicator - but no need to complain
    // about it
    _usesThreadedAnimation = value;
}

- (void) setMinValue: (double) value {
    _minValue = value;
    [self setNeedsDisplay: YES];
}

- (void) setMaxValue: (double) value {
    _maxValue = value;
    [self setNeedsDisplay: YES];
}

- (void) setDoubleValue: (double) value {
    if (value < _minValue)
        value = _minValue;
    if (value > _maxValue)
        value = _maxValue;

    _value = value;
    [self setNeedsDisplay: YES];
}

- (void) setAnimationDelay: (double) delay {
    _animationDelay = delay;
    [self _invalidateTimer];
    [self _buildTimer];
}

- (void) setIndeterminate: (BOOL) flag {
    _isIndeterminate = flag;
    [self setNeedsDisplay: YES];
}

- (void) setBezeled: (BOOL) flag {
    _isBezeled = flag;
    [self setNeedsDisplay: YES];
}

- (void) incrementBy: (double) value {
    [self setDoubleValue: _value + value];
}

// QUIRK: a spinning indicator sizes itself to a square of 32, 16 or 10 points for the regular, small and mini
// control sizes. Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2) of the frame after
// -sizeToFit. Test: appkit-progress-aqua.m
- (void) sizeToFit {
    if (_style == NSProgressIndicatorSpinningStyle) {
        CGFloat side = _size == NSSmallControlSize ? 16 : (_size == NSMiniControlSize ? 10 : 32);

        [self setFrameSize: NSMakeSize(side, side)];
    }
}

- (void) _runThreadedAnimation: (id) arg {
    _endThreadedAnimation = NO;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [self _buildTimer];
    [self setNeedsDisplay: YES];

    BOOL isRunning = YES;
    do {
        isRunning =
                [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                         beforeDate: [NSDate distantFuture]];
    } while (isRunning && _endThreadedAnimation == NO);

    [self _invalidateTimer];

    [pool drain];
}

- (void) _stopThreadedAnimation {
    _endThreadedAnimation = YES;
}

- (void) startAnimation: sender {
    if (!_isIndeterminate)
        return;

    if (NO && _usesThreadedAnimation) {
        [NSThread detachNewThreadSelector: @selector(_runThreadedAnimation:)
                                 toTarget: self
                               withObject: nil];
    } else {
        [self _buildTimer];
        [self setNeedsDisplay: YES];
    }
}

- (void) stopAnimation: sender {

    if (!_isIndeterminate)
        return;

    if (NO && _usesThreadedAnimation) {
        [self _stopThreadedAnimation];
    } else {

        [self _invalidateTimer];
        [self setNeedsDisplay: YES];
    }
}

- (void) animate: sender {
    _animationValue += 1.0 / [self bounds].size.width;

    if (_animationValue > 1)
        _animationValue = 0;

    [self setNeedsDisplay: YES];
}

@end

@implementation NSProgressIndicator (Bindings)

- (BOOL) _animate {
    return _animationTimer != nil;
}

- (void) _setAnimate: (BOOL) animate {
    if (animate) {
        [self startAnimation: nil];
    } else {
        [self stopAnimation: nil];
    }
}

- _replacementKeyPathForBinding: (id) binding {
    if ([binding isEqual: @"value"])
        return @"doubleValue";
    return [super _replacementKeyPathForBinding: binding];
}

@end
