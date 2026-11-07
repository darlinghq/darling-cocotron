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
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <CoreGraphics/CGEvent.h>

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
    _buttonNumber = defaultButtonNumber(type);
    _clickCount = clickCount;
    return self;
}

- (CGFloat) deltaX {
    return _deltaX;
}

- (CGFloat) deltaY {
    return _deltaY;
}

- (CGFloat) deltaZ {
    return 0.0;
}

- (CGEventRef) CGEvent {
    CGEventRef event;

    switch (_type) {
    case NSLeftMouseDown:
    case NSLeftMouseUp:
    case NSRightMouseDown:
    case NSRightMouseUp:
    case NSMouseMoved:
    case NSLeftMouseDragged:
    case NSRightMouseDragged:
    case NSOtherMouseDown:
    case NSOtherMouseUp:
    case NSOtherMouseDragged:
        // The mouse event types have the same values in both enums.
        event = CGEventCreateMouseEvent(NULL, (CGEventType) _type, CGPointZero,
                                        (CGMouseButton) _buttonNumber);
        CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber,
                                    _buttonNumber);
        CGEventSetIntegerValueField(event, kCGMouseEventClickState,
                                    _clickCount);
        break;
    case NSScrollWheel:
        event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2,
                                              (int32_t) _deltaY,
                                              (int32_t) _deltaX);
        break;
    default:
        return NULL;
    }
    if (event == NULL)
        return NULL;

    // CGEvent locations are global, in CoreGraphics' space: origin at the
    // top-left corner of the main display, y down.
    NSPoint point = [self locationInWindow];
    NSWindow *window = [self window];
    if (window != nil)
        point = [window convertBaseToScreen: point];
    NSArray *screens = [NSScreen screens];
    if ([screens count] > 0)
        point.y = NSHeight([[screens objectAtIndex: 0] frame]) - point.y;
    CGEventSetLocation(event, NSPointToCGPoint(point));

    // NSEventModifierFlags and CGEventFlags use the same bits.
    CGEventSetFlags(event, (CGEventFlags) [self modifierFlags]);

    return (CGEventRef) CFAutorelease(event);
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
- (NSTrackingArea *) trackingArea {
    return (NSTrackingArea *) _trackingNumber;
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

@end
