/*
 This file is part of Darling.

 Copyright (C) 2021-2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSPanGestureRecognizer.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSView.h>
#import "NSGestureRecognizer-Private.h"

#define EXTRA NS_EXTRA(NSPanGestureRecognizer, self)

// The buttons as NSEvent numbers them (0 is the primary one), which is how
// buttonMask has a bit for each.
static BOOL buttonInMask(NSUInteger mask, NSInteger button) {
    return button >= 0 && button < (NSInteger) (sizeof(NSUInteger) * 8) && (mask & ((NSUInteger) 1 << button)) != 0;
}

// A vector in window coordinates as one in the view's (nil: the window's).
static NSPoint vectorInView(NSPoint vector, NSView *view) {
    if (view == nil)
        return vector;
    NSPoint origin = [view convertPoint: NSZeroPoint fromView: nil];
    NSPoint end = [view convertPoint: vector fromView: nil];
    return NSMakePoint(end.x - origin.x, end.y - origin.y);
}

// A vector in the view's coordinates as one in the window's.
static NSPoint vectorFromView(NSPoint vector, NSView *view) {
    if (view == nil)
        return vector;
    NSPoint origin = [view convertPoint: NSZeroPoint toView: nil];
    NSPoint end = [view convertPoint: vector toView: nil];
    return NSMakePoint(end.x - origin.x, end.y - origin.y);
}

@implementation NSPanGestureRecognizer

+ (unsigned int) _defaultDelayedEvents {
    return _NSGestureRecognizerDelaysPrimaryMouseButtonEvents;
}

- (instancetype) initWithTarget: (id) target action: (SEL) action {
    if ((self = [super initWithTarget: target action: action])) {
        EXTRA->_buttonMask = 1;
        EXTRA->_numberOfTouchesRequired = 1;
    }
    return self;
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder])) {
        EXTRA->_buttonMask = 1;
        EXTRA->_numberOfTouchesRequired = 1;
    }
    return self;
}

- (void) dealloc {
    NS_EXTRA_FREE(NSPanGestureRecognizer, self);
    [super dealloc];
}

- (NSUInteger) buttonMask {
    return EXTRA->_buttonMask;
}

- (void) setButtonMask: (NSUInteger) mask {
    EXTRA->_buttonMask = mask;
}

// Darling has no touch input; the value is kept for those who read it back.
- (NSInteger) numberOfTouchesRequired {
    return EXTRA->_numberOfTouchesRequired;
}

- (void) setNumberOfTouchesRequired: (NSInteger) count {
    EXTRA->_numberOfTouchesRequired = count;
}

- (NSTimeInterval) timestamp {
    return EXTRA->_timestamp;
}

- (NSPoint) translationInView: (NSView *) view {
    NSPoint translation = NSMakePoint(EXTRA->_lastLocation.x - EXTRA->_startLocation.x,
                                      EXTRA->_lastLocation.y - EXTRA->_startLocation.y);
    return vectorInView(translation, view);
}

- (void) setTranslation: (NSPoint) translation inView: (NSView *) view {
    NSPoint vector = vectorFromView(translation, view);
    EXTRA->_startLocation = NSMakePoint(EXTRA->_lastLocation.x - vector.x, EXTRA->_lastLocation.y - vector.y);
}

- (NSPoint) velocityInView: (NSView *) view {
    return vectorInView(EXTRA->_velocity, view);
}

// The velocity once the pointer is at the event's location: zero when the pan
// begins, the speed since the previous event at the first change, and after
// that four fifths of that speed and one fifth of the velocity before, as
// observed on macOS 26.7.3 and Mac OS X 10.14.4 (test:
// tests/appkit-pan-gesture-recognizer.m). An event at the same time as the
// previous one keeps the velocity.
- (void) _moveToEvent: (NSEvent *) event beginning: (BOOL) beginning {
    NSPoint location = [event locationInWindow];
    NSTimeInterval time = [event timestamp];
    NSTimeInterval elapsed = time - EXTRA->_lastTime;
    if (beginning) {
        EXTRA->_velocity = NSZeroPoint;
        EXTRA->_hasVelocity = NO;
    } else if (elapsed > 0) {
        NSPoint speed = NSMakePoint((location.x - EXTRA->_lastLocation.x) / elapsed,
                                    (location.y - EXTRA->_lastLocation.y) / elapsed);
        if (EXTRA->_hasVelocity)
            speed = NSMakePoint(0.8 * speed.x + 0.2 * EXTRA->_velocity.x, 0.8 * speed.y + 0.2 * EXTRA->_velocity.y);
        EXTRA->_velocity = speed;
        EXTRA->_hasVelocity = YES;
    }
    EXTRA->_lastLocation = location;
    EXTRA->_lastTime = time;
    EXTRA->_timestamp = time;
}

- (void) _buttonDown: (NSEvent *) event button: (NSInteger) button {
    if (EXTRA->_tracking || !buttonInMask(EXTRA->_buttonMask, button))
        return;
    EXTRA->_tracking = YES;
    EXTRA->_trackedButton = button;
    EXTRA->_startLocation = EXTRA->_lastLocation = [event locationInWindow];
    EXTRA->_lastTime = EXTRA->_timestamp = [event timestamp];
    EXTRA->_velocity = NSZeroPoint;
    EXTRA->_hasVelocity = NO;
}

- (void) _buttonDragged: (NSEvent *) event button: (NSInteger) button {
    if (!EXTRA->_tracking || button != EXTRA->_trackedButton)
        return;
    BOOL beginning = [self state] == NSGestureRecognizerStatePossible;
    [self _moveToEvent: event beginning: beginning];
    [self setState: beginning ? NSGestureRecognizerStateBegan : NSGestureRecognizerStateChanged];
}

- (void) _buttonUp: (NSEvent *) event button: (NSInteger) button {
    if (!EXTRA->_tracking || button != EXTRA->_trackedButton)
        return;
    EXTRA->_tracking = NO;
    NSGestureRecognizerState state = [self state];
    if (state == NSGestureRecognizerStateBegan || state == NSGestureRecognizerStateChanged) {
        [self _moveToEvent: event beginning: NO];
        [self setState: NSGestureRecognizerStateEnded];
    } else {
        [self setState: NSGestureRecognizerStateFailed];
    }
}

- (void) mouseDown: (NSEvent *) event {
    [self _buttonDown: event button: 0];
}

- (void) rightMouseDown: (NSEvent *) event {
    [self _buttonDown: event button: 1];
}

- (void) otherMouseDown: (NSEvent *) event {
    [self _buttonDown: event button: [event buttonNumber]];
}

- (void) mouseDragged: (NSEvent *) event {
    [self _buttonDragged: event button: 0];
}

- (void) rightMouseDragged: (NSEvent *) event {
    [self _buttonDragged: event button: 1];
}

- (void) otherMouseDragged: (NSEvent *) event {
    [self _buttonDragged: event button: [event buttonNumber]];
}

- (void) mouseUp: (NSEvent *) event {
    [self _buttonUp: event button: 0];
}

- (void) rightMouseUp: (NSEvent *) event {
    [self _buttonUp: event button: 1];
}

- (void) otherMouseUp: (NSEvent *) event {
    [self _buttonUp: event button: [event buttonNumber]];
}

// After a pan the translation and the velocity start again from zero; the
// timestamp stays.
- (void) reset {
    EXTRA->_tracking = NO;
    EXTRA->_startLocation = EXTRA->_lastLocation;
    EXTRA->_velocity = NSZeroPoint;
    EXTRA->_hasVelocity = NO;
    [super reset];
}

@end
