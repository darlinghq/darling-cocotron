/* CoreGraphics Wayland backend: the pointer.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "CGSWaylandPointer.h"
#import "CGSWaylandCursor.h"
#import "CGSConnectionWayland.h"
#import "CGSWindowWayland.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#include <math.h>

// The event types of the gestures (NSEventType values; CGEvent.h has no names for them).
enum {
    CGSEventTypeRotate = 18,
    CGSEventTypeMagnify = 30,
};
// NSEventPhase bits, which the gesture events carry.
enum {
    CGSGesturePhaseBegan = 1 << 0,
    CGSGesturePhaseChanged = 1 << 2,
    CGSGesturePhaseEnded = 1 << 3,
    CGSGesturePhaseCancelled = 1 << 4,
};

// wl_pointer.axis values are lengths in surface-local coordinates, the space pointer motion uses. A
// notch of a wheel is this many of them, which is also what a source's pixels per line is by default
// (CGEventSourceSetPixelsPerLine), so that a line delta and a pixel delta of the same movement agree.
@interface CGSWaylandPointer ()
- (void) destroyPinch;
- (void) destroyHold;
- (void) endHoldWithPhase: (int64_t) phase;
@end

static const double AxisUnitsPerLine = 10.0;

// A Linux button code in Cocoa's numbering: the left, right and middle buttons are 0, 1 and 2, the side
// and extra buttons that follow BTN_LEFT's group are 3 and up.
static int64_t buttonNumberForCode(uint32_t code) {
    switch (code) {
    case WP_BTN_LEFT: return 0;
    case WP_BTN_RIGHT: return 1;
    case WP_BTN_MIDDLE: return 2;
    default: return code > WP_BTN_LEFT + 2 ? (int64_t) code - WP_BTN_LEFT : 3;
    }
}

static unsigned maskForCode(uint32_t code) {
    switch (code) {
    case WP_BTN_LEFT: return 1;
    case WP_BTN_RIGHT: return 2;
    case WP_BTN_MIDDLE: return 4;
    default: return 8;
    }
}

@implementation CGSWaylandPointer

@synthesize pointerProxy = _pointer;

- (void) setPendingTimestamp: (uint64_t) timestamp {
    _pendingTimestamp = timestamp;
    _hasPendingTimestamp = YES;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    _downClickState = [NSMutableDictionary new];
    // The pointer is hardware: the events it posts change the state the hardware state functions report.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    _cursorObject = [[CGSWaylandCursor alloc] initWithConnection: connection pointer: self];
    return self;
}

- (void) dealloc {
    [self stop];
    [_cursorObject invalidate];
    [_cursorObject release];
    [_downClickState release];
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

- (id<CGSNativeConnectionObserver>) observer {
    return [CGSConnection nativeObserver];
}

#pragma mark - The objects

- (void) seatCapabilities: (uint32_t) capabilities seat: (struct wl_proxy *) seat {
    if ((capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer == NULL && seat != NULL) {
        union wl_argument args[1] = {{.o = NULL}};
        _pointer = [_connection createObject: seat
                                      opcode: WP_SEAT_GET_POINTER
                                   interface: &wl_pointer_interface
                                   arguments: args
                                        kind: CGSWaylandObjectPointer
                                      object: self];
        [self pointerGesturesChanged];
        [_cursorObject objectsChanged];
        id<CGSNativeConnectionObserver> observer = [self observer];
        if ([observer respondsToSelector: @selector(nativeConnectionPointerAvailabilityChanged:)])
            [observer nativeConnectionPointerAvailabilityChanged: YES];
        [self updatePointerLock];
    } else if (!(capabilities & WP_SEAT_CAPABILITY_POINTER) && _pointer != NULL) {
        [self stop];
    }
}

- (void) pointerGesturesChanged {
    struct wl_proxy *gestures = [_connection pointerGestures];

    if (gestures != NULL && _pointer != NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _pointer}};
        if (_pinch == NULL) {
            _pinch = [_connection createObject: gestures
                                        opcode: WP_GESTURES_GET_PINCH
                                     interface: &zwp_pointer_gesture_pinch_v1_interface
                                     arguments: args
                                          kind: CGSWaylandObjectPinchGesture
                                        object: self];
        }
        // The hold gesture was added in version 3 of the manager.
        if (_hold == NULL && WL.wl_proxy_get_version(gestures) >= 3) {
            _hold = [_connection createObject: gestures
                                       opcode: WP_GESTURES_GET_HOLD
                                    interface: &zwp_pointer_gesture_hold_v1_interface
                                    arguments: args
                                         kind: CGSWaylandObjectHoldGesture
                                       object: self];
        }
    } else {
        [self destroyPinch];
        [self destroyHold];
    }
}

- (void) destroyPinch {
    if (_pinch == NULL)
        return;
    [self endPinchWithPhase: CGSGesturePhaseCancelled];
    WaylandMarshal(_pinch, WP_PINCH_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    _pinch = NULL;
}

- (void) destroyHold {
    if (_hold == NULL)
        return;
    [self endHoldWithPhase: kCGScrollPhaseCancelled];
    if (WL.wl_proxy_get_version(_hold) >= 3)
        WaylandMarshal(_hold, WP_HOLD_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    else
        WL.wl_proxy_destroy(_hold);
    _hold = NULL;
}

- (void) stop {
    if (_pointer == NULL && _focus == NULL)
        return;
    _hasPendingTimestamp = NO;
    [self destroyPinch];
    [self destroyHold];
    [self releasePointerLockObjects];
    id<CGSNativeConnectionObserver> observer = [self observer];
    BOOL had = _pointer != NULL;
    // Before the observer drops its state: the cancelled scroll still needs the surface.
    [self cancelFingerScroll];
    if (had && [observer respondsToSelector: @selector(nativeConnectionPointerAvailabilityChanged:)])
        [observer nativeConnectionPointerAvailabilityChanged: NO];
    if (_pointer != NULL) {
        // wl_pointer.release exists from version 3.
        if (WL.wl_proxy_get_version(_pointer) >= 3) {
            union wl_argument args[1] = {{.o = NULL}};
            WaylandMarshal(_pointer, WP_POINTER_RELEASE, NULL, WL_MARSHAL_FLAG_DESTROY, args);
        } else {
            WL.wl_proxy_destroy(_pointer);
        }
        _pointer = NULL;
        [_cursorObject objectsChanged];
    }
    _focus = NULL;
    _enterSerial = 0;
    _pressed = 0;
    [self setPressedNumbers: 0];
    _lastClickSurface = NULL;
    _located = NO;
    [_downClickState removeAllObjects];
    [self discardPendingScroll];
}

- (void) surfaceDestroyed: (struct wl_proxy *) surface {
    if (surface == NULL)
        return;
    if (_lastClickSurface == surface)
        _lastClickSurface = NULL;
    // The lock objects of a surface that goes away go with it, with no position hint for it.
    if (_lockSurface == surface || _warpSurface == surface)
        [self releasePointerLockObjects];
    if (_pinchSurface == surface)
        [self endPinchWithPhase: CGSGesturePhaseCancelled];
    if (_holdSurface == surface)
        [self endHoldWithPhase: kCGScrollPhaseCancelled];
    // A finger scroll on a window that goes away ends as cancelled
    if (_fingerSurface == surface)
        [self cancelFingerScroll];
    if (_scrollSurface == surface)
        [self discardPendingScroll];
    if (_focus == surface) {
        _focus = NULL;
        _enterSerial = 0;
        _pressed = 0;
        _dragSerial = 0;
        [self setPressedNumbers: 0];
        _located = NO;
        [_downClickState removeAllObjects];
    }
}

- (void) setSurfacePointX: (double) x y: (double) y {
    _point = CGPointMake(x, y);
    _lastPoint = _point;
    [self noteGlobalLocation];
}

- (void) setPressedNumbers: (uint32_t) numbers {
    @synchronized(self) {
        _pressedNumbers = numbers;
    }
}

- (void) setButtonNumber: (int64_t) number pressed: (BOOL) pressed {
    if (number < 0 || number > 31)
        return;
    @synchronized(self) {
        if (pressed)
            _pressedNumbers |= (uint32_t) 1 << number;
        else
            _pressedNumbers &= ~((uint32_t) 1 << number);
    }
}

- (BOOL) isButtonDown: (uint32_t) button {
    if (button > 31)
        return NO;
    @synchronized(self) {
        return (_pressedNumbers & ((uint32_t) 1 << button)) != 0;
    }
}

// The pointer is at _point of the surface that has it: that is where the state queries put it from now on.
- (void) noteGlobalLocation {
    if (_focus == NULL)
        return;
    CGPoint global = [self globalLocationOfSurface: _focus point: _point];
    @synchronized(self) {
        _lastGlobal = global;
        _lastGlobalValid = YES;
    }
}

- (BOOL) getLastGlobalLocation: (CGPoint *) location {
    // On the main thread the surface's window may have moved under the stationary pointer.
    if ([NSThread isMainThread])
        [self noteGlobalLocation];
    @synchronized(self) {
        if (!_lastGlobalValid)
            return NO;
        *location = _lastGlobal;
        return YES;
    }
}

#pragma mark - Posting

// Where a point of a surface is in global coordinates: the framework that owns the surface says, and a
// window of this connection knows its own position.
- (CGPoint) globalLocationOfSurface: (struct wl_proxy *) surface point: (CGPoint) point {
    id<CGSNativeConnectionObserver> observer = [self observer];
    CGPoint global;

    if ([observer respondsToSelector: @selector(nativeConnectionGlobalLocation:ofSurface:point:)] &&
        [observer nativeConnectionGlobalLocation: &global ofSurface: surface point: point])
        return global;
    if ([_connection globalLocation: &global ofSurface: surface point: point])
        return global;
    return point;
}

// What every event of the pointer carries: the modifier flags of the keyboard, the window and where in it.
- (void) addCommonFieldsTo: (CGEventRef) event surface: (struct wl_proxy *) surface point: (CGPoint) point
                    global: (CGPoint) global flags: (uint64_t) flags {
    CGEventSetFlags(event, (CGEventFlags) flags);
    // The events of a display overlay name no window: it covers the display, belonging to none of the
    // application's windows, like a captured display.
    uint32_t windowID = [_connection windowIDForSurface: surface];
    if (windowID != 0 && ![_connection isDisplayOverlaySurface: surface]) {
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer, windowID);
        CGEventSetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent, windowID);
    }
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) (intptr_t) surface);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, llround(point.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, llround(point.y * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));
}

// Lets the observer add what it knows, then posts the event to the taps and the process' event stream.
- (void) postEvent: (CGEventRef) event {
    id<CGSNativeConnectionObserver> observer = [self observer];

    if (_hasPendingTimestamp) {
        CGEventSetTimestamp(event, _pendingTimestamp);
        _hasPendingTimestamp = NO;
    }

    // The observer is asked even for the events of a display overlay (it keeps the state of the buttons), but
    // no window can refuse them: the overlay's events always go to the process' event stream.
    BOOL overlay = [_connection isDisplayOverlaySurface:
                                         (struct wl_proxy *) (intptr_t) CGEventGetIntegerValueField(event, kCGSEventNativeWindow)];
    if ([observer respondsToSelector: @selector(nativeConnectionWillPostWaylandPointerEvent:)] &&
        ![observer nativeConnectionWillPostWaylandPointerEvent: (struct __CGEvent *) event] && !overlay)
        CGEventSetIntegerValueField(event, kCGSEventTapsOnly, 1);
    _CGSEventStreamPost(event);
    CFRelease(event);
}

- (void) postMouseEventType: (CGEventType) type
                     button: (int64_t) button
                 clickState: (int64_t) clickState
                     deltaX: (int64_t) deltaX
                     deltaY: (int64_t) deltaY
                     serial: (uint32_t) serial {
    CGPoint global = [self globalLocationOfSurface: _focus point: _point];
    CGEventRef event = CGEventCreateMouseEvent((CGEventSourceRef) _source, type, global, (CGMouseButton) button);

    if (event == NULL)
        return;
    CGEventSetIntegerValueField(event, kCGMouseEventButtonNumber, button);
    if (clickState >= 0)
        CGEventSetIntegerValueField(event, kCGMouseEventClickState, clickState);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, deltaX);
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, deltaY);
    [self addCommonFieldsTo: event surface: _focus point: _point global: global flags: [_connection modifierFlags]];
    CGEventSetIntegerValueField(event, kCGSEventInputSerial, serial);
    [self postEvent: event];
}

#pragma mark - Events

- (void) pointerEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    id<CGSNativeConnectionObserver> observer = [self observer];

    if (opcode != WP_POINTER_EV_AXIS && opcode != WP_POINTER_EV_FRAME && opcode != WP_POINTER_EV_AXIS_SOURCE &&
        opcode != WP_POINTER_EV_AXIS_STOP && opcode != WP_POINTER_EV_AXIS_DISCRETE &&
        opcode != WP_POINTER_EV_AXIS_VALUE120)
        [self postPendingScroll];
    // A modifier key the keyboard has not yet seen the effect of comes before the pointer event it modifies.
    [_connection flushPendingKeyboardEvents];

    switch (opcode) {
    case WP_POINTER_EV_ENTER:
        _enterSerial = args[0].u;
        _focus = (struct wl_proxy *) args[1].o;
        _point = CGPointMake(wl_fixed_to_double(args[2].f), wl_fixed_to_double(args[3].f));
        // A motion's delta does not reach across surfaces, whose coordinates are their own.
        _located = YES;
        _lastPoint = _point;
        _remainderX = _remainderY = 0;
        [self noteGlobalLocation];
        // The compositor starts the pointer in a new surface with no cursor image of ours: the process' cursor
        // (a blank one while it is hidden) is given again for the serial of this enter.
        [_cursorObject setNeedsApply];
        if ([observer respondsToSelector: @selector(nativeConnectionPointerEntered:serial:x:y:)])
            [observer nativeConnectionPointerEntered: _focus serial: _enterSerial x: _point.x y: _point.y];
        [self updatePointerLock];
        break;

    case WP_POINTER_EV_LEAVE:
        [self cancelFingerScroll];
        _pressed = 0;
        _dragSerial = 0;
        [self setPressedNumbers: 0];
        [_downClickState removeAllObjects];
        if ([observer respondsToSelector: @selector(nativeConnectionPointerLeft)])
            [observer nativeConnectionPointerLeft];
        _focus = NULL;
        _enterSerial = 0;
        _located = NO;
        [self discardPendingScroll];
        break;

    case WP_POINTER_EV_MOTION:
        [self motionToX: wl_fixed_to_double(args[1].f) y: wl_fixed_to_double(args[2].f)];
        break;

    case WP_POINTER_EV_BUTTON:
        [self button: args[2].u pressed: args[3].u == WP_POINTER_BUTTON_STATE_PRESSED time: args[1].u serial: args[0].u];
        break;

    case WP_POINTER_EV_AXIS:
        [self axis: args[1].u value: wl_fixed_to_double(args[2].f)];
        break;

    case WP_POINTER_EV_AXIS_SOURCE:
        _scrollSourceNamed = YES;
        _scrollSource = args[0].u;
        break;

    case WP_POINTER_EV_AXIS_STOP:
        [self startScrollFrame];
        if (args[1].u <= WP_POINTER_AXIS_HORIZONTAL_SCROLL)
            _scrollStopped |= 1u << args[1].u;
        break;

    case WP_POINTER_EV_AXIS_DISCRETE:
        [self axisSteps: args[1].i axis: args[0].u];
        break;

    case WP_POINTER_EV_AXIS_VALUE120:
        [self axisSteps: args[1].i / 120.0 axis: args[0].u];
        break;

    case WP_POINTER_EV_FRAME:
        [self postPendingScroll];
        break;
    }
}

- (void) motionToX: (double) x y: (double) y {
    id<CGSNativeConnectionObserver> observer = [self observer];
    // Track the position even when no surface is under the pointer. Opening a menu maps a new surface
    // under a stationary cursor, so the compositor sends leave and then motion with no surface; dropping
    // that motion left the position stale and the following button landed wherever the pointer last was.
    CGPoint previous = _lastPoint;
    BOOL wasLocated = _located;

    _point = CGPointMake(x, y);
    BOOL used = [observer respondsToSelector: @selector(nativeConnectionPointerMovedToX:y:)] &&
                [observer nativeConnectionPointerMovedToX: x y: y];
    // The pointer over a window's own frame is the frame's, not the content's.
    if (!used && _focus != NULL && _pressed == 0)
        used = [[_connection toplevelForSurface: _focus] toplevelClientDecorationContainsPoint: _point];
    if (_focus == NULL)
        return;
    [self noteGlobalLocation];
    _lastPoint = _point;
    _located = YES;
    if (used)
        return;

    // The motion since the previous event in whole points; what is left stays for the next one, so that a
    // slow motion or one at a fractional position is not lost.
    int64_t deltaX = 0, deltaY = 0;
    if (wasLocated) {
        double dx = _point.x - previous.x + _remainderX;
        double dy = _point.y - previous.y + _remainderY;
        double wholeX = dx < 0 ? ceil(dx) : floor(dx);
        double wholeY = dy < 0 ? ceil(dy) : floor(dy);
        _remainderX = dx - wholeX;
        _remainderY = dy - wholeY;
        deltaX = (int64_t) wholeX;
        deltaY = (int64_t) wholeY;
    }

    // The mouse moved: a cursor hidden until then comes back, and CGGetLastMouseDelta() has the motion.
    if (wasLocated && (_point.x != previous.x || _point.y != previous.y)) {
        [_connection accumulateMouseDeltaX: _point.x - previous.x y: _point.y - previous.y];
        [_connection pointerDidMove];
    }

    // After a warp with the mouse connected to the cursor the local motion is dropped for the suppression
    // interval (it still counted for CGGetLastMouseDelta() above).
    if ([_connection localMouseMotionSuppressed])
        return;
    int64_t button = 0;
    CGEventType type = [self motionEventTypeWithButton: &button];
    [self postMouseEventType: type button: button clickState: -1 deltaX: deltaX deltaY: deltaY serial: 0];
}

// Moved, or the drag of the button that is down. The drag of the other buttons is an other-mouse drag, as the
// X11 pointer reports it.
- (CGEventType) motionEventTypeWithButton: (int64_t *) button {
    *button = 0;
    if (_pressed & 1)
        return kCGEventLeftMouseDragged;
    if (_pressed & 2) {
        *button = 1;
        return kCGEventRightMouseDragged;
    }
    if (_pressed & 4) {
        *button = 2;
        return kCGEventOtherMouseDragged;
    }
    if (_pressed & 8) {
        *button = buttonNumberForCode(_otherButton);
        return kCGEventOtherMouseDragged;
    }
    return kCGEventMouseMoved;
}

// Cocoa groups clicks only within its double-click interval and four points of the preceding press, and
// only for the same button on the same surface. The compositor's timestamp is used rather than the wall
// clock, which cannot be compared with the compositor's, and its unsigned subtraction covers the wrap.
- (int64_t) clickStateForPressOf: (uint32_t) button time: (uint32_t) time {
    CGFloat dx = _point.x - _lastClickPoint.x;
    CGFloat dy = _point.y - _lastClickPoint.y;

    if (_lastClickSurface == _focus && _lastClickButton == button &&
        (uint32_t) (time - _lastClickTime) < _CGSDoubleClickInterval() * 1000 && dx * dx + dy * dy <= 16 &&
        _clickCount < INT64_MAX)
        _clickCount++;
    else
        _clickCount = 1;
    _lastClickTime = time;
    _lastClickButton = button;
    _lastClickSurface = _focus;
    _lastClickPoint = _point;
    return _clickCount;
}

- (uint32_t) heldLeftPressSerialForSurface: (struct wl_proxy *) surface {
    return surface != NULL && _focus == surface && (_pressed & 1) != 0 ? _leftPressSerial : 0;
}

- (void) button: (uint32_t) code pressed: (BOOL) pressed time: (uint32_t) time serial: (uint32_t) serial {
    id<CGSNativeConnectionObserver> observer = [self observer];

    if (pressed)
        [_connection inputPressedWithSerial: serial];

    // A window's own frame (title bar buttons, resize edges) takes the button for itself, as long as no other button of
    // the pointer is down.
    if (_focus != NULL && _pressed == 0) {
        CGSWindowWayland *window = [_connection toplevelForSurface: _focus];

        if (window != nil && [window handleToplevelDecorationButton: code pressed: pressed serial: serial atPoint: _point])
            return;
    }
    if ([observer respondsToSelector: @selector(nativeConnectionPointerButton:pressed:serial:)] &&
        [observer nativeConnectionPointerButton: code pressed: pressed serial: serial])
        return;

    unsigned mask = maskForCode(code);
    int64_t button = buttonNumberForCode(code);
    NSNumber *key = [NSNumber numberWithUnsignedInt: code];
    int64_t clickState;

    [self setButtonNumber: button pressed: pressed];
    if (pressed) {
        _pressed |= mask;
        if (mask == 1)
            _leftPressSerial = serial;
        if (mask == 8)
            _otherButton = code;
        clickState = _focus != NULL ? [self clickStateForPressOf: code time: time] : 1;
        [_downClickState setObject: [NSNumber numberWithLongLong: clickState] forKey: key];
    } else {
        _pressed &= ~mask;
        // The release of a click reports the count its press was given, so that a double click's two presses
        // are matched by their own releases; a release with no press behind it is a single click.
        NSNumber *held = [_downClickState objectForKey: key];
        clickState = held != nil ? [held longLongValue] : 1;
        [_downClickState removeObjectForKey: key];
    }
    if (pressed && _focus != NULL)
        _dragSerial = serial;
    else if (!pressed && _pressed == 0)
        _dragSerial = 0;
    if (_focus == NULL)
        return;

    CGEventType type;
    switch (code) {
    case WP_BTN_LEFT: type = pressed ? kCGEventLeftMouseDown : kCGEventLeftMouseUp; break;
    case WP_BTN_RIGHT: type = pressed ? kCGEventRightMouseDown : kCGEventRightMouseUp; break;
    default: type = pressed ? kCGEventOtherMouseDown : kCGEventOtherMouseUp; break;
    }
    [self postMouseEventType: type button: button clickState: clickState deltaX: 0 deltaY: 0 serial: pressed ? serial : 0];
}

#pragma mark - Relative mouse, warp and the hidden cursor

static const double kNothing = 0;

// The surface the lock is to be made on: a display overlay, which covers the screen above every window, so it
// is the one while there is one; else the one the framework above names (its window to lock), else the
// surface that has the pointer, else the one with the keyboard focus. The compositor activates the lock
// when the surface has the pointer focus, which can be later.
- (struct wl_proxy *) lockTargetSurface {
    id<CGSNativeConnectionObserver> observer = [self observer];
    void *surface = [_connection displayOverlaySurface];

    if (surface == NULL && [observer respondsToSelector: @selector(nativeConnectionSurfaceForPointerLock)])
        surface = [observer nativeConnectionSurfaceForPointerLock];
    if (surface == NULL)
        surface = _focus;
    if (surface == NULL)
        surface = [_connection keyboardFocus];
    return (struct wl_proxy *) surface;
}

- (void) pointerLockGlobalsChanged {
    [self updatePointerLock];
}

- (BOOL) pointerLocked {
    return _lock != NULL && _lockActive;
}

// Makes the lock objects match the connection's mouse association: with the mouse disconnected from the
// cursor the pointer is locked to a surface of the process and the relative pointer delivers the motion.
- (void) updatePointerLock {
    BOOL wanted = ![_connection mouseAssociated];
    struct wl_proxy *constraints = [_connection pointerConstraints];
    struct wl_proxy *manager = [_connection relativePointerManager];
    BOOL possible = _pointer != NULL && constraints != NULL && manager != NULL;

    if (wanted && !_loggedLockMissing && (constraints == NULL || manager == NULL)) {
        _loggedLockMissing = YES;
        NSLog(@"CoreGraphics Wayland backend: the mouse was disconnected from the cursor, but the compositor offers no "
              @"%s: the cursor stays free and no deltas are delivered",
              constraints == NULL ? "zwp_pointer_constraints_v1" : "zwp_relative_pointer_manager_v1");
    }
    struct wl_proxy *target = wanted && possible ? [self lockTargetSurface] : NULL;
    if (target == NULL || (_lockSurface != NULL && _lockSurface != target)) {
        [self releasePointerLock];
        if (target == NULL)
            return;
    }
    if (_lock != NULL)
        return;
    // A surface can have one lock: the short one of a warp gives way.
    [self destroyWarpLock];
    union wl_argument lockArgs[5] = {{.o = NULL}, {.o = (struct wl_object *) target}, {.o = (struct wl_object *) _pointer},
                                     {.o = NULL}, {.u = WP_POINTER_CONSTRAINTS_LIFETIME_PERSISTENT}};
    // A lock that lives until it is destroyed: it activates whenever the surface has the pointer focus (a
    // oneshot one would be spent by the first focus change).
    _lock = [_connection createObject: constraints
                               opcode: WP_POINTER_CONSTRAINTS_LOCK_POINTER
                            interface: &zwp_locked_pointer_v1_interface
                            arguments: lockArgs
                                 kind: CGSWaylandObjectLockedPointer
                               object: self];
    union wl_argument relativeArgs[2] = {{.o = NULL}, {.o = (struct wl_object *) _pointer}};
    _relative = [_connection createObject: manager
                                   opcode: WP_RELATIVE_POINTER_MANAGER_GET_RELATIVE_POINTER
                                interface: &zwp_relative_pointer_v1_interface
                                arguments: relativeArgs
                                     kind: CGSWaylandObjectRelativePointer
                                   object: self];
    _lockSurface = target;
    _lockActive = NO;
    _relativeRemainderX = _relativeRemainderY = kNothing;
    [_connection flush];
}

// Unlocks. The pointer comes back where the application left its cursor: the position hint is double
// buffered state of the surface, so the commit comes before the destroy.
- (void) releasePointerLock {
    if (_lock == NULL)
        return;
    union wl_argument hint[2] = {{.f = wl_fixed_from_double(_point.x)}, {.f = wl_fixed_from_double(_point.y)}};
    WaylandMarshal(_lock, WP_LOCKED_POINTER_SET_CURSOR_POSITION_HINT, NULL, 0, hint);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_lockSurface, WP_SURFACE_COMMIT, NULL, 0, none);
    [self releasePointerLockObjects];
}

- (void) releasePointerLockObjects {
    union wl_argument none[1] = {{.o = NULL}};

    [self destroyWarpLock];
    if (_lock != NULL)
        WaylandMarshal(_lock, WP_LOCKED_POINTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    if (_relative != NULL)
        WaylandMarshal(_relative, WP_RELATIVE_POINTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    _lock = _relative = _lockSurface = NULL;
    _lockActive = NO;
    [_connection flush];
}

- (void) destroyWarpLock {
    if (_warpLock == NULL)
        return;
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_warpLock, WP_LOCKED_POINTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    _warpLock = _warpSurface = NULL;
}

- (void) lockEvent: (uint32_t) opcode kind: (int) kind proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args {
    switch (kind) {
    case CGSWaylandObjectLockedPointer:
        if (proxy == _lock)
            _lockActive = opcode == WP_LOCKED_POINTER_EV_LOCKED;
        break;
    case CGSWaylandObjectRelativePointer:
        if (proxy == _relative && opcode == WP_RELATIVE_POINTER_EV_RELATIVE_MOTION)
            [self relativeMotionByX: wl_fixed_to_double(args[2].f) y: wl_fixed_to_double(args[3].f)];
        break;
    case CGSWaylandObjectWarpLock:
        if (proxy == _warpLock && opcode == WP_LOCKED_POINTER_EV_LOCKED) {
            // The pointer is held still on the surface: the compositor may put it at the hint when the lock
            // ends. The hint is surface state, so the commit comes before the destroy.
            union wl_argument hint[2] = {{.f = wl_fixed_from_double(_warpPoint.x)}, {.f = wl_fixed_from_double(_warpPoint.y)}};
            WaylandMarshal(_warpLock, WP_LOCKED_POINTER_SET_CURSOR_POSITION_HINT, NULL, 0, hint);
            union wl_argument none[1] = {{.o = NULL}};
            WaylandMarshal(_warpSurface, WP_SURFACE_COMMIT, NULL, 0, none);
            [self destroyWarpLock];
            [_connection flush];
        } else if (proxy == _warpLock && opcode == WP_LOCKED_POINTER_EV_UNLOCKED) {
            [self destroyWarpLock];
            [_connection flush];
        }
        break;
    }
}

// A locked pointer moves nothing on screen: the event carries the delta at the frozen cursor position, as the
// events of a mouse disconnected from the cursor do on macOS. The deltas are whole points; the fraction stays
// for the next event.
- (void) relativeMotionByX: (double) dx y: (double) dy {
    if (!_lockActive || _focus == NULL)
        return;
    [_connection accumulateMouseDeltaX: dx y: dy];
    double totalX = dx + _relativeRemainderX, totalY = dy + _relativeRemainderY;
    double wholeX = totalX < 0 ? ceil(totalX) : floor(totalX);
    double wholeY = totalY < 0 ? ceil(totalY) : floor(totalY);
    _relativeRemainderX = totalX - wholeX;
    _relativeRemainderY = totalY - wholeY;
    if (wholeX == 0 && wholeY == 0)
        return;
    int64_t button = 0;
    CGEventType type = [self motionEventTypeWithButton: &button];
    [self postMouseEventType: type button: button clickState: -1 deltaX: (int64_t) wholeX deltaY: (int64_t) wholeY serial: 0];
}

// On compositors that offer pointer-warp-v1 the pointer is moved with a warp request. Without it, while the
// pointer is locked the cursor is the application's own and a warp moves where the application's cursor is:
// the events carry that position and it is the hint the pointer comes back at when the lock ends. Otherwise
// the compositor is asked for the position through a short lock of the surface (it may honour the hint when
// the lock ends); the cursor is where the call says for the events that follow.
- (CGError) warpToGlobalPoint: (CGPoint) global {
    struct wl_proxy *surface = _lock != NULL ? _lockSurface : _focus;
    id<CGSNativeConnectionObserver> observer = [self observer];
    CGPoint target;

    if (surface == NULL || _pointer == NULL)
        return kCGErrorCannotComplete;
    if (!(([observer respondsToSelector: @selector(nativeConnectionPoint:ofSurface:forGlobalLocation:)] &&
           [observer nativeConnectionPoint: &target ofSurface: surface forGlobalLocation: global]) ||
          [_connection surfacePoint: &target forGlobalLocation: global ofSurface: surface]))
        return kCGErrorCannotComplete;
    struct wl_proxy *constraints = [_connection pointerConstraints];
    struct wl_proxy *warp = [_connection pointerWarp];
    // The warp protocol needs the enter serial, which is also what wl_pointer.set_cursor uses.
    if (_lock == NULL && constraints == NULL && (warp == NULL || _enterSerial == 0))
        return kCGErrorCannotComplete;

    _point = target;
    _lastPoint = target;
    _remainderX = _remainderY = kNothing;
    if ([observer respondsToSelector: @selector(nativeConnectionPointerWarpedToX:y:)])
        [observer nativeConnectionPointerWarpedToX: target.x y: target.y];
    if (_lock != NULL)
        return kCGErrorSuccess;
    [_connection noteMouseWarp];

    // A compositor with pointer-warp can move the real pointer to the point in the surface. The serial is
    // the one of wl_pointer.enter, exactly as the protocol asks for; it is valid for any surface of this
    // client, so the surface need not be the one the pointer last entered.
    if (warp != NULL && _enterSerial != 0) {
        union wl_argument args[5] = {{.o = (struct wl_object *) surface},
                                     {.o = (struct wl_object *) _pointer},
                                     {.f = wl_fixed_from_double(target.x)},
                                     {.f = wl_fixed_from_double(target.y)},
                                     {.u = _enterSerial}};
        WaylandMarshal(warp, WP_POINTER_WARP_WARP_POINTER, NULL, 0, args);
        [_connection flush];
        return kCGErrorSuccess;
    }

    _warpPoint = target;
    if (_warpLock == NULL) {
        union wl_argument args[5] = {{.o = NULL}, {.o = (struct wl_object *) surface}, {.o = (struct wl_object *) _pointer},
                                     {.o = NULL}, {.u = WP_POINTER_CONSTRAINTS_LIFETIME_ONESHOT}};
        _warpLock = [_connection createObject: constraints
                                       opcode: WP_POINTER_CONSTRAINTS_LOCK_POINTER
                                    interface: &zwp_locked_pointer_v1_interface
                                    arguments: args
                                         kind: CGSWaylandObjectWarpLock
                                       object: self];
        _warpSurface = surface;
        [_connection flush];
    }
    return kCGErrorSuccess;
}

- (void) cursorHiddenChanged {
    [_cursorObject setNeedsApply];
}

- (void) cursorChanged {
    [_cursorObject setNeedsApply];
}

- (void) cursorGlobalsChanged {
    [_cursorObject objectsChanged];
}

- (uint32_t) enterSerial {
    return _enterSerial;
}

- (uint32_t) dragSerial {
    return _dragSerial;
}

- (void) consumeDragSerial {
    _dragSerial = 0;
}

#pragma mark - Scroll

// A scroll frame is what the compositor sends between two wl_pointer.frame events (a version 5 seat; an
// older seat sends each axis on its own): the source, the axis values and wheel steps, and the axes that
// stopped. It becomes one scroll wheel CGEvent.

- (void) startScrollFrame {
    if (_scrollActive)
        return;
    _scrollSurface = _focus;
    _scrollPoint = _point;
    _scrollFlags = [_connection modifierFlags];
    _scrollActive = YES;
}

- (void) discardPendingScroll {
    _scrollX = _scrollY = _scrollStepsX = _scrollStepsY = 0;
    _scrollSurface = NULL;
    _scrollActive = _scrollSourceNamed = _scrollHasSteps = NO;
    _scrollStopped = 0;
    _fingerActive = NO;
    _fingerSurface = NULL;
}

- (void) axis: (uint32_t) axis value: (double) value {
    if (_focus == NULL)
        return;
    if (axis != WP_POINTER_AXIS_HORIZONTAL_SCROLL && axis != WP_POINTER_AXIS_VERTICAL_SCROLL)
        return;
    [self startScrollFrame];
    // Scrolling down is positive on the wire; a scroll wheel event is positive upwards and to the left.
    if (axis == WP_POINTER_AXIS_HORIZONTAL_SCROLL)
        _scrollX -= value;
    else
        _scrollY -= value;
    // wl_pointer.frame was added in version 5. Older seats deliver each axis event independently, so
    // each is a frame.
    if (WL.wl_proxy_get_version(_pointer) < 5)
        [self postPendingScroll];
}

- (void) axisSteps: (double) steps axis: (uint32_t) axis {
    if (_focus == NULL)
        return;
    if (axis != WP_POINTER_AXIS_HORIZONTAL_SCROLL && axis != WP_POINTER_AXIS_VERTICAL_SCROLL)
        return;
    [self startScrollFrame];
    _scrollHasSteps = YES;
    if (axis == WP_POINTER_AXIS_HORIZONTAL_SCROLL)
        _scrollStepsX -= steps;
    else
        _scrollStepsY -= steps;
}

// The part of a smooth scroll that makes whole pixels (a scroll wheel event's point delta is a whole
// number); the rest goes with the next frame of the same scroll.
static int64_t takeWholePixels(double value, double *remainder) {
    double total = value + *remainder;
    double whole = total < 0 ? ceil(total) : floor(total);
    *remainder = total - whole;
    return (int64_t) whole;
}

// A whole number of lines for the wheel steps (or, without steps, the pixels), at least one in the
// direction of any movement.
static int64_t wholeLines(double lines) {
    int64_t whole = (int64_t) lines;
    if (whole == 0 && lines != 0)
        whole = lines < 0 ? -1 : 1;
    return whole;
}

- (void) postScrollOfX: (double) unitsX y: (double) unitsY stepsX: (double) stepsXValue stepsY: (double) stepsYValue
              hasSteps: (BOOL) hasSteps continuous: (BOOL) continuous phase: (int64_t) phase
               surface: (struct wl_proxy *) surface point: (CGPoint) point flags: (uint64_t) flags {
    CGPoint global = [self globalLocationOfSurface: surface point: point];
    CGEventRef event;

    if (continuous) {
        // Smooth scrolling: pixels, the lines are what they are worth
        int64_t pixelsX = takeWholePixels(unitsX, &_scrollRemainderX);
        int64_t pixelsY = takeWholePixels(unitsY, &_scrollRemainderY);
        event = CGEventCreateScrollWheelEvent2((CGEventSourceRef) _source, kCGScrollEventUnitPixel, 2,
                                               (int32_t) pixelsY, (int32_t) pixelsX, 0);
        if (event == NULL)
            return;
    } else {
        int64_t linesX = hasSteps ? wholeLines(stepsXValue) : wholeLines(unitsX / AxisUnitsPerLine);
        int64_t linesY = hasSteps ? wholeLines(stepsYValue) : wholeLines(unitsY / AxisUnitsPerLine);
        event = CGEventCreateScrollWheelEvent2((CGEventSourceRef) _source, kCGScrollEventUnitLine, 2,
                                               (int32_t) linesY, (int32_t) linesX, 0);
        if (event == NULL)
            return;
    }
    // An axis that has wheel steps keeps what CGEventCreateScrollWheelEvent2 made of the lines (the fixed-point
    // lines are the steps, the points are the source's pixels per line for each of them), so that a notch of
    // the wheel gives the same event whatever the compositor's units are for it (the same as the X11 wheel).
    // Any other axis carries its axis values: the lines they are worth and the points they are.
    BOOL stepsY = hasSteps && stepsYValue != 0, stepsX = hasSteps && stepsXValue != 0;
    if (continuous || !stepsY) {
        if (!continuous)
            CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1, llround(unitsY));
        CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1, unitsY / AxisUnitsPerLine);
    }
    if (continuous || !stepsX) {
        if (!continuous)
            CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2, llround(unitsX));
        CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2, unitsX / AxisUnitsPerLine);
    }
    CGEventSetIntegerValueField(event, kCGScrollWheelEventIsContinuous, continuous);
    CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, phase);
    CGEventSetLocation(event, global);
    [self addCommonFieldsTo: event surface: surface point: point global: global flags: flags];
    [self postEvent: event];
}

- (void) postPendingScroll {
    double unitsX = _scrollX, unitsY = _scrollY, stepsX = _scrollStepsX, stepsY = _scrollStepsY;
    struct wl_proxy *surface = _scrollSurface;
    CGPoint point = _scrollPoint;
    uint64_t flags = _scrollFlags;
    uint32_t source = _scrollSource, stopped = _scrollStopped;
    BOOL sourceNamed = _scrollSourceNamed, hadFrame = _scrollActive, hasSteps = _scrollHasSteps;
    BOOL finger = sourceNamed && source == WP_POINTER_AXIS_SOURCE_FINGER;
    BOOL smoothSource = sourceNamed && source == WP_POINTER_AXIS_SOURCE_CONTINUOUS;

    _scrollX = _scrollY = _scrollStepsX = _scrollStepsY = 0;
    _scrollSurface = NULL;
    _scrollActive = _scrollSourceNamed = _scrollHasSteps = NO;
    _scrollStopped = 0;
    BOOL moved = unitsX != 0 || unitsY != 0;

    if (!hadFrame || surface == NULL)
        return;

    int64_t phase = 0;
    // The source is optional in a frame, so a finger sequence in progress also continues in a frame that
    // names no source, and a frame without motion (an axis_stop alone) can end it whatever source it names.
    // A frame that moves and names another source is not part of it.
    if (finger || (_fingerActive && (!sourceNamed || !moved))) {
        // The protocol only says a finger source sends axis_stop when the finger lifts. The first frame
        // with motion is taken as the began phase and later ones as changed. A sequence ends in a frame
        // whose axis_stop covers every axis that moved in it (so also in one with no motion); an axis_stop
        // beside motion on the other axis is a change, since the protocol says that axis is still moving
        // then. A first frame that has motion and an axis_stop for it gives began only, since one event
        // cannot be both began and ended; the sequence then ends at the next axis_stop.
        uint32_t movedAxes = (unitsX != 0 ? 1u << WP_POINTER_AXIS_HORIZONTAL_SCROLL : 0) |
                             (unitsY != 0 ? 1u << WP_POINTER_AXIS_VERTICAL_SCROLL : 0);
        BOOL ends = _fingerActive && stopped != 0 && (movedAxes & ~stopped) == 0;

        if (ends)
            phase = kCGScrollPhaseEnded;
        else if (moved)
            phase = _fingerActive ? kCGScrollPhaseChanged : kCGScrollPhaseBegan;
        if (phase == 0)
            return;
        _fingerActive = phase != kCGScrollPhaseEnded;
        _fingerSurface = _fingerActive ? surface : NULL;
        _fingerPoint = point;
    } else if (!moved) {
        return;
    }
    [self postScrollOfX: unitsX y: unitsY stepsX: stepsX stepsY: stepsY hasSteps: hasSteps
             continuous: phase != 0 || smoothSource phase: phase surface: surface point: point flags: flags];
    // The pixels held back belong to one scroll: the next one starts clean.
    if (phase == 0 || phase == kCGScrollPhaseEnded)
        _scrollRemainderX = _scrollRemainderY = 0;
}

// A pointer that leaves, a seat that loses its pointer or a window that goes away in the middle of a finger
// scroll ends it with the cancelled phase, as a pinch does. The documentation of NSEvent.phase lists
// cancelled as an ending phase of a gesture but not when it is used, so this is taken from the gestures.
- (void) cancelFingerScroll {
    struct wl_proxy *surface = _fingerSurface;
    CGPoint point = _fingerPoint;
    BOOL known = _fingerActive && surface != NULL;

    _fingerActive = NO;
    _fingerSurface = NULL;
    _scrollRemainderX = _scrollRemainderY = 0;
    if (!known)
        return;
    [self postScrollOfX: 0 y: 0 stepsX: 0 stepsY: 0 hasSteps: NO continuous: YES phase: kCGScrollPhaseCancelled
                surface: surface point: point flags: [_connection modifierFlags]];
}

- (void) flushPending {
    [self postPendingScroll];
}

#pragma mark - Pinch

- (void) postGestureType: (int) type phase: (int64_t) phase magnification: (double) magnification
                rotation: (double) rotation {
    CGPoint global = [self globalLocationOfSurface: _pinchSurface point: _point];
    CGEventRef event = CGEventCreate((CGEventSourceRef) _source);

    if (event == NULL)
        return;
    CGEventSetType(event, (CGEventType) type);
    CGEventSetLocation(event, global);
    CGEventSetIntegerValueField(event, kCGSGesturePhase, phase);
    CGEventSetIntegerValueField(event, kCGSGestureMagnification, llround(magnification * 1000000));
    CGEventSetIntegerValueField(event, kCGSGestureRotation, llround(rotation * 1000000));
    [self addCommonFieldsTo: event surface: _pinchSurface point: _point global: global flags: [_connection modifierFlags]];
    [self postEvent: event];
}

// Ends an active pinch; nothing when none is in progress.
- (void) endPinchWithPhase: (int64_t) phase {
    if (!_pinchActive)
        return;
    [self postGestureType: CGSEventTypeMagnify phase: phase magnification: 0 rotation: 0];
    [self postGestureType: CGSEventTypeRotate phase: phase magnification: 0 rotation: 0];
    _pinchActive = NO;
    _pinchSurface = NULL;
}

// A pinch reports its scale relative to where the fingers started and its rotation in degrees clockwise
// since the last update. The events carry the change in magnification and counterclockwise degrees.
- (void) pinchEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    [self postPendingScroll];
    switch (opcode) {
    case WP_PINCH_EV_BEGIN:
        _pinchSurface = (struct wl_proxy *) args[2].o;
        _pinchScale = 1;
        _pinchActive = _pinchSurface != NULL;
        if (!_pinchActive)
            break;
        [self postGestureType: CGSEventTypeMagnify phase: CGSGesturePhaseBegan magnification: 0 rotation: 0];
        [self postGestureType: CGSEventTypeRotate phase: CGSGesturePhaseBegan magnification: 0 rotation: 0];
        break;

    case WP_PINCH_EV_UPDATE: {
        if (!_pinchActive)
            break;
        double scale = wl_fixed_to_double(args[3].f);
        double rotation = -wl_fixed_to_double(args[4].f);
        if (scale != _pinchScale)
            [self postGestureType: CGSEventTypeMagnify phase: CGSGesturePhaseChanged
                    magnification: scale - _pinchScale rotation: 0];
        if (rotation != 0)
            [self postGestureType: CGSEventTypeRotate phase: CGSGesturePhaseChanged magnification: 0 rotation: rotation];
        _pinchScale = scale;
        break;
    }

    case WP_PINCH_EV_END:
        [self endPinchWithPhase: args[2].i ? CGSGesturePhaseCancelled : CGSGesturePhaseEnded];
        break;
    }
}

// A hold cancels the kinetic scrolling of the scroll view under the fingers. AppKit expresses that
// with a scroll event of zero delta and a phase, not with a magnification or rotation.
- (void) postHoldPhase: (int64_t) phase {
    CGEventRef event = CGEventCreateScrollWheelEvent2((CGEventSourceRef) _source,
                                                      kCGScrollEventUnitPixel, 2, 0, 0, 0);
    if (event == NULL)
        return;
    CGEventSetIntegerValueField(event, kCGScrollWheelEventScrollPhase, phase);
    CGEventSetLocation(event, [self globalLocationOfSurface: _holdSurface point: _point]);
    [self addCommonFieldsTo: event surface: _holdSurface point: _point
                    global: [self globalLocationOfSurface: _holdSurface point: _point]
                     flags: [_connection modifierFlags]];
    [self postEvent: event];
}

- (void) endHoldWithPhase: (int64_t) phase {
    if (!_holdActive)
        return;
    [self postHoldPhase: phase];
    _holdActive = NO;
    _holdSurface = NULL;
}

- (void) holdEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    [self postPendingScroll];
    switch (opcode) {
    case WP_HOLD_EV_BEGIN:
        _holdSurface = (struct wl_proxy *) args[2].o;
        _holdActive = _holdSurface != NULL;
        if (_holdActive)
            [self postHoldPhase: kCGScrollPhaseBegan];
        break;
    case WP_HOLD_EV_END:
        [self endHoldWithPhase: args[2].i ? kCGScrollPhaseCancelled : kCGScrollPhaseEnded];
        break;
    default:
        break;
    }
}

@end
