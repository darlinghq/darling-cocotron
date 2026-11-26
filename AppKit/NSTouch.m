/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

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

#import <AppKit/NSTouch.h>
#import <AppKit/NSTouchBackend.h>
#import "NSEventQueue.h"
#import <AppKit/NSResponder.h>
#import <objc/runtime.h>
#import <AppKit/NSEvent_touch.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSWindow-Private.h>
#import <Foundation/Foundation.h>
#include <math.h>

/*
 * Fingers are routed when they are reported, not when their events are
 * dispatched: a finger that moves the mouse must reach the event queue as
 * mouse events, so that the tracking loops of controls (which ask only for
 * mouse events) see it.
 */

@implementation NSTouch

- (instancetype) _initWithIdentity: (id<NSObject, NSCopying>) identity
                            window: (NSWindow *) window
                          location: (NSPoint) location
{
    if ((self = [super init])) {
        _identity = [identity retain];
        _window = window;
        _location = _previousLocation = location;
        _phase = NSTouchPhaseBegan;
    }
    return self;
}

- (void) dealloc {
    [_identity release];
    [_view release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *) zone {
    NSTouch *copy = [[NSTouch allocWithZone: zone] _initWithIdentity: _identity
                                                              window: _window
                                                            location: _location];
    copy->_phase = _phase;
    copy->_previousLocation = _previousLocation;
    copy->_normalizedPosition = _normalizedPosition;
    copy->_deviceSize = _deviceSize;
    copy->_view = [_view retain];
    return copy;
}

- (id<NSObject, NSCopying>) identity { return _identity; }
- (NSTouchPhase) phase { return _phase; }
- (NSTouchType) type { return NSTouchTypeDirect; }
- (BOOL) isResting { return NO; }
- (NSPoint) normalizedPosition { return _normalizedPosition; }
- (NSSize) deviceSize { return _deviceSize; }
- (id) device { return nil; }
- (NSView *) _view { return _view; }
- (NSWindow *) _window { return _window; }

- (NSPoint) locationInView: (NSView *) view {
    return view != nil ? [view convertPoint: _location fromView: nil] : _location;
}

- (NSPoint) previousLocationInView: (NSView *) view {
    return view != nil ? [view convertPoint: _previousLocation fromView: nil] : _previousLocation;
}

- (void) _moveTo: (NSPoint) location phase: (NSTouchPhase) phase {
    _previousLocation = phase == NSTouchPhaseBegan ? location : _location;
    _location = location;
    _phase = phase;
}

- (void) _setNormalizedPosition: (NSPoint) position deviceSize: (NSSize) size {
    _normalizedPosition = position;
    _deviceSize = size;
}

- (void) _setPhase: (NSTouchPhase) phase {
    _phase = phase;
}

- (void) _setView: (NSView *) view {
    [_view release];
    _view = [view retain];
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<NSTouch %p: identity %@, phase %lu, location %@, view %@>", self, _identity,
                                       (unsigned long) _phase, NSStringFromPoint(_location), [_view class]];
}

@end

@implementation NSEvent_touch

- (instancetype) initWithWindow: (NSWindow *) window
                       location: (NSPoint) location
                      timestamp: (NSTimeInterval) timestamp
                        touches: (NSSet *) touches
{
    if ((self = [super initWithType: NSEventTypeDirectTouch location: location modifierFlags: 0 window: window])) {
        _timestamp = timestamp;
        _touches = [touches copy];
    }
    return self;
}

- (void) dealloc {
    [_touches release];
    [super dealloc];
}

- (NSSet *) touchesMatchingPhase: (NSUInteger) phase inView: (NSView *) view {
    NSMutableSet *result = [NSMutableSet set];
    for (NSTouch *touch in _touches) {
        if (!([touch phase] & phase))
            continue;
        if (view == nil || [[touch _view] isDescendantOf: view])
            [result addObject: touch];
    }
    return result;
}

- (NSSet *) allTouches {
    return _touches;
}

- (NSSet *) touchesForView: (NSView *) view {
    return [self touchesMatchingPhase: NSTouchPhaseAny inView: view];
}

- (NSArray *) coalescedTouchesForTouch: (id) touch {
    return touch != nil ? @[touch] : @[];
}

@end

#pragma mark - Routing

static NSMutableDictionary<NSNumber *, NSTouch *> *sFingers;
static unsigned long long sTouchSerial;

// Taps that follow each other closely count up, as clicks do.
static NSTimeInterval sLastTapTime;
static NSPoint sLastTapPoint;
static NSWindow *sLastTapWindow;
static NSInteger sTapCount;

// A view takes direct touches when it allows them and handles them itself.
// Every NSView allows direct touches by default, so the touch handlers decide:
// a view that does not override them leaves the finger to move the mouse, as
// it would without touch support.
static BOOL NSTouchViewHandlesTouches(NSView *view) {
    if (!([view allowedTouchTypes] & NSTouchTypeMaskDirect))
        return NO;
    SEL began = @selector(touchesBeganWithEvent:);
    return class_getMethodImplementation([view class], began) !=
           class_getMethodImplementation([NSResponder class], began);
}

// Only the view under the finger decides: an AppKit view inside one that takes
// touches (a text field in a UIKit view) still wants the mouse.
static NSView *NSTouchTarget(NSWindow *window, NSPoint location) {
    NSView *view = [[window _backgroundView] hitTest: location];
    return NSTouchViewHandlesTouches(view) ? view : nil;
}

static BOOL NSTouchMouseIsTaken(void) {
    for (NSTouch *finger in [sFingers objectEnumerator])
        if (finger->_movesMouse)
            return YES;
    return NO;
}

// A finger's event as the mouse event it stands for
static NSEvent *NSTouchMouseEvent(NSTouch *finger, NSWindow *window, NSTouchPhase phase, NSPoint previous,
                                  NSPoint location, NSTimeInterval timestamp)
{
    NSEventType type;
    switch (phase) {
    case NSTouchPhaseBegan: {
        CGFloat dx = location.x - sLastTapPoint.x, dy = location.y - sLastTapPoint.y;
        if (sLastTapWindow == window && timestamp - sLastTapTime < 0.5 && dx * dx + dy * dy <= 100)
            sTapCount++;
        else
            sTapCount = 1;
        sLastTapTime = timestamp;
        sLastTapPoint = location;
        sLastTapWindow = window;
        finger->_clickCount = sTapCount;
        type = NSEventTypeLeftMouseDown;
        break;
    }
    case NSTouchPhaseMoved:
        type = NSEventTypeLeftMouseDragged;
        break;
    case NSTouchPhaseEnded:
    case NSTouchPhaseCancelled:
        type = NSEventTypeLeftMouseUp;
        break;
    default:
        return nil;
    }
    // deltaY is positive downwards, as the backends report it.
    return [NSEvent mouseEventWithType: type
                              location: location
                         modifierFlags: 0
                                window: window
                            clickCount: finger->_clickCount
                                deltaX: location.x - previous.x
                                deltaY: previous.y - location.y];
}

// Every finger down in the window, as this event left it
static NSEvent *NSTouchTouchesEvent(NSTouch *changed, NSWindow *window, NSPoint location, NSTimeInterval timestamp) {
    NSMutableSet *touches = [NSMutableSet set];
    for (NSTouch *finger in [sFingers objectEnumerator]) {
        if ([finger _window] != window || [finger _view] == nil)
            continue;
        NSTouch *snapshot = [finger copy];
        if (finger != changed)
            [snapshot _setPhase: NSTouchPhaseStationary];
        [touches addObject: snapshot];
        [snapshot release];
    }
    return [[[NSEvent_touch alloc] initWithWindow: window
                                         location: location
                                        timestamp: timestamp
                                          touches: touches] autorelease];
}

static void NSTouchTrack(NSWindow *window, long long identifier, NSTouchPhase phase, NSPoint location,
                         NSTimeInterval timestamp, NSPoint normalized, NSSize deviceSize, NSMutableArray *events)
{
    if (sFingers == nil)
        sFingers = [NSMutableDictionary new];
    if (timestamp <= 0)
        timestamp = [[NSProcessInfo processInfo] systemUptime];
    NSNumber *key = [NSNumber numberWithLongLong: identifier];
    NSTouch *finger = [sFingers objectForKey: key];

    if (phase == NSTouchPhaseBegan) {
        // A finger that went up unreported is done before its number is reused.
        if (finger != nil)
            NSTouchTrack([finger _window], identifier, NSTouchPhaseCancelled, [finger locationInView: nil], timestamp,
                         normalized, deviceSize, events);
        if (window == nil)
            return;
        finger = [[NSTouch alloc] _initWithIdentity: [NSNumber numberWithUnsignedLongLong: ++sTouchSerial]
                                             window: window
                                           location: location];
        NSView *view = NSTouchTarget(window, location);
        if (view != nil)
            [finger _setView: view];
        else if (!NSTouchMouseIsTaken())
            finger->_movesMouse = YES;
        // Otherwise a second finger on a view that takes no touches: ignored.
        [sFingers setObject: finger forKey: key];
        [finger release];
    } else if (finger == nil) {
        return;
    }

    [[finger retain] autorelease];
    // A finger stays with the window it began in.
    window = [finger _window];
    NSPoint previous = [finger locationInView: nil];
    // An end reported without a position is where the finger last was.
    if (isnan(location.x) || isnan(location.y))
        location = previous;
    [finger _moveTo: location phase: phase];
    [finger _setNormalizedPosition: normalized deviceSize: deviceSize];

    NSEvent *event = nil;
    if (finger->_movesMouse)
        event = NSTouchMouseEvent(finger, window, phase, previous, location, timestamp);
    else if ([finger _view] != nil)
        event = NSTouchTouchesEvent(finger, window, location, timestamp);
    if (event != nil)
        [events addObject: event];

    if (phase == NSTouchPhaseEnded || phase == NSTouchPhaseCancelled)
        [sFingers removeObjectForKey: key];
}

NSArray *NSTouchEventsForReport(NSWindow *window, long long identifier, NSTouchPhase phase, NSPoint location,
                                NSTimeInterval timestamp, NSPoint normalizedPosition, NSSize deviceSize)
{
    NSMutableArray *events = [NSMutableArray array];
    NSTouchTrack(window, identifier, phase, location, timestamp, normalizedPosition, deviceSize, events);
    return events;
}

void NSTouchPost(NSWindow *window, long long identifier, NSTouchPhase phase, NSPoint location,
                 NSTimeInterval timestamp)
{
    for (NSEvent *event in NSTouchEventsForReport(window, identifier, phase, location, timestamp, NSZeroPoint, NSZeroSize))
        _NSEventQueuePost(event, NO);
}

void NSTouchCancelAll(NSWindow *window) {
    for (NSNumber *key in [sFingers allKeys]) {
        NSTouch *finger = [sFingers objectForKey: key];
        if (window == nil || [finger _window] == window)
            NSTouchPost([finger _window], [key longLongValue], NSTouchPhaseCancelled,
                        [finger locationInView: nil], 0);
    }
}
