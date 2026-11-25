/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
                 2010 Markus Hitter <mah@jump-ing.de>

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

#import <AppKit/NSEvent.h>

@interface NSEvent_mouse : NSEvent {
    NSInteger _clickCount;
    CGFloat _deltaX;
    CGFloat _deltaY;
    NSInteger _trackingNumber;
    NSTrackingArea *_trackingArea;
    void *_userData;
    NSInteger _buttonNumber;
    NSInteger _eventNumber;
    NSInteger _keyStateOnArrival;
    float _pressure;
    BOOL _hasPreciseScrollingDeltas;
    CGFloat _scrollingDeltaX;
    CGFloat _scrollingDeltaY;
    NSEventPhase _scrollPhase;
}

- (void) _setTrackingArea: (NSTrackingArea *) area;

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window
                   clickCount: (NSInteger) clickCount
                       deltaX: (CGFloat) deltaX
                       deltaY: (CGFloat) deltaY;

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window
                       deltaY: (CGFloat) deltaY;

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                  eventNumber: (NSInteger) eventNumber
               trackingNumber: (NSInteger) tracking
                     userData: (void *) userData;

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                  eventNumber: (NSInteger) eventNumber
                   clickCount: (NSInteger) clickCount
                     pressure: (float) pressure;

- (NSTrackingArea *) trackingArea;
- (NSInteger) trackingNumber;
- (void *) userData;

- (void) _setButtonNumber: (NSInteger) num;
- (void) _setDeltaX: (CGFloat) deltaX deltaY: (CGFloat) deltaY;

// Marks a scroll wheel event as coming from a device with precise deltas, such as a trackpad:
// scrollingDeltaX and scrollingDeltaY return the given amounts to scroll by, hasPreciseScrollingDeltas
// is YES and phase is the given one; deltaX and deltaY become a tenth of the amounts, as on macOS. Events never marked behave as wheel events: line-based deltas
// and no phase. Raises for any other event type.
- (void) _setPreciseScrollingDeltaX: (CGFloat) deltaX deltaY: (CGFloat) deltaY phase: (NSEventPhase) phase;

// Whether the window the press was meant for was key when the window system
// delivered the press. By the time the event is taken from the queue the
// window system's activation for the same click may have been applied. Unset
// for events that did not come from a window system.
- (void) _setWindowWasKeyOnArrival: (BOOL) key;
- (BOOL) _hasWindowKeyStateOnArrival;
- (BOOL) _windowWasKeyOnArrival;

@end
