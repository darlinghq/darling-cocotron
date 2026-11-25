/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>
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
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent_mouse.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <CoreGraphics/CGEvent.h>

// A mouse is not pressure-sensitive: AppKit documents pressure as 0 or 1 for
// such devices, so it is 1 while a button is held and 0 otherwise.
static float defaultPressure(NSEventType type) {
    switch (type) {
    case NSLeftMouseDown:
    case NSLeftMouseDragged:
    case NSRightMouseDown:
    case NSRightMouseDragged:
    case NSOtherMouseDown:
    case NSOtherMouseDragged:
        return 1;
    default:
        return 0;
    }
}

// The button an event of this type is about, until a backend sets the
// actual one: 0 is the left button, 1 the right one and 2 the middle one.
static NSInteger defaultButtonNumber(NSEventType type) {
    switch (type) {
    case NSRightMouseDown:
    case NSRightMouseUp:
    case NSRightMouseDragged:
        return 1;
    case NSOtherMouseDown:
    case NSOtherMouseUp:
    case NSOtherMouseDragged:
        return 2;
    default:
        return 0;
    }
}

@implementation NSEvent_mouse

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window
                   clickCount: (NSInteger) clickCount
                       deltaX: (CGFloat) deltaX
                       deltaY: (CGFloat) deltaY
{
    [super initWithType: type
                 location: location
            modifierFlags: modifierFlags
                   window: window];

    _buttonNumber = defaultButtonNumber(type);
    _pressure = defaultPressure(type);
    _clickCount = clickCount;
    _deltaX = deltaX;
    _deltaY = deltaY;

    return self;
}

- (NSInteger) clickCount {
    return _clickCount;
}

- (short) subtype {
    return NSEventSubtypeMouseEvent;
}

- (NSInteger) eventNumber {
    return _eventNumber;
}

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                       window: (NSWindow *) window
                       deltaY: (CGFloat) deltaY
{
    [super initWithType: type
                 location: location
            modifierFlags: modifierFlags
                   window: window];

    _deltaY = deltaY;

    return self;
}

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                  eventNumber: (NSInteger) eventNumber
               trackingNumber: (NSInteger) tracking
                     userData: (void *) userData
{
    self = [super initWithType: type
                      location: location
                 modifierFlags: modifierFlags
                        window: [NSApp windowWithWindowNumber: windowNumber]];
    if (self != nil) {
        _timestamp = timestamp;
        _eventNumber = eventNumber;
        _trackingNumber = tracking;
        _userData = userData;
    }
    return self;
}

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                  eventNumber: (NSInteger) eventNumber
                   clickCount: (NSInteger) clickCount
                     pressure: (float) pressure
{
    [super initWithType: type
                 location: location
            modifierFlags: modifierFlags
                   window: [NSApp windowWithWindowNumber: windowNumber]];
    _timestamp = timestamp;
    _buttonNumber = defaultButtonNumber(type);
    _pressure = pressure;
    _clickCount = clickCount;
    _eventNumber = eventNumber;
    return self;
}

- (CGFloat) deltaX {
    return _deltaX;
}

- (float) pressure {
    return _pressure;
}

- (CGFloat) deltaY {
    return _deltaY;
}

- (CGFloat) deltaZ {
    return 0.0;
}

// Apple's documentation is a bit confusing here. NSEvent exposes no API to pass
// a NSTrackingArea object on creation, yet they expose API to get that pointer.
// Additionally, they state -trackingArea would deliver meaningful returns only
// if the area was created with the NSTrackingArea API.
//
// On the other hand, NSTrackingArea's docs explicitely state a pointer to a
// NSTrackingArea is now substitute for NSTrackingRectTags, which are in turn
// "trackingNumbers". See "Compatibility Issues", there.
//
// Accordingly, it's unclear wether there's a difference between -trackingArea
// and -trackingNumber at all (as of 10.6 docs). Let's assume they are the same.
// Only the events of areas made with NSTrackingArea have one; the number of the
// others is the tag returned by -addTrackingRect:owner:userData:assumeInside:.
- (NSTrackingArea *) trackingArea {
    return [_trackingArea _isFromTagAPI] ? nil : _trackingArea;
}

- (void) _setTrackingArea: (NSTrackingArea *) area {
    if (_trackingArea != area) {
        [_trackingArea release];
        _trackingArea = [area retain];
    }
}

- (void) dealloc {
    [_trackingArea release];
    [super dealloc];
}

- (NSInteger) trackingNumber {
    return _trackingNumber;
}

- (void *) userData {
    if (_type != NSMouseEntered && _type != NSMouseExited) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ userData] not valid for type %d",
                            [self class], _type];
        return NULL;
    }

    return _userData;
}

- (NSInteger) buttonNumber {
    return _buttonNumber;
}

- (void) _setButtonNumber: (NSInteger) num {
    _buttonNumber = num;
}

- (void) _setDeltaX: (CGFloat) deltaX deltaY: (CGFloat) deltaY {
    _deltaX = deltaX;
    _deltaY = deltaY;
}

- (void) _setPreciseScrollingDeltaX: (CGFloat) deltaX deltaY: (CGFloat) deltaY phase: (NSEventPhase) phase {
    if (_type != NSScrollWheel)
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %s] needs a scroll wheel event, not type %d",
                            [self class], sel_getName(_cmd), (int) _type];

    _hasPreciseScrollingDeltas = YES;
    _scrollingDeltaX = deltaX;
    _scrollingDeltaY = deltaY;
    // QUIRK: the legacy deltaX and deltaY of a precise scroll event are a tenth of the scrolling deltas (the
    // deltas are in points, the legacy ones in lines of ten points). Not documented. Evidence: black-box
    // observation on macOS 26.7.3 and 10.14.4 (tier 2), scroll events made with CGEventCreateScrollWheelEvent2 in
    // pixel units: 10 points gave deltaY 1, 25 gave deltaX 2.5.
    // Test: appkit-precise-scroll-events (test_quirk_precise_legacy_deltas_are_a_tenth)
    _deltaX = deltaX / 10;
    _deltaY = deltaY / 10;
    _scrollPhase = phase;
}

- (BOOL) hasPreciseScrollingDeltas {
    return _hasPreciseScrollingDeltas;
}

- (CGFloat) scrollingDeltaX {
    return _hasPreciseScrollingDeltas ? _scrollingDeltaX : [super scrollingDeltaX];
}

- (CGFloat) scrollingDeltaY {
    return _hasPreciseScrollingDeltas ? _scrollingDeltaY : [super scrollingDeltaY];
}

- (NSEventPhase) phase {
    return _hasPreciseScrollingDeltas ? _scrollPhase : [super phase];
}

- (void) _setWindowWasKeyOnArrival: (BOOL) key {
    _keyStateOnArrival = key ? 1 : 2;
}

- (BOOL) _hasWindowKeyStateOnArrival {
    return _keyStateOnArrival != 0;
}

- (BOOL) _windowWasKeyOnArrival {
    return _keyStateOnArrival == 1;
}

@end
