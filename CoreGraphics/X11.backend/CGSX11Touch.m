/* CoreGraphics X11 backend: touch screens and pinch gestures.

 Copyright (C) 2026 Lubos Dolezel

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

// Touch screens (XInput 2.2) and touchpad pinch gestures (XInput 2.4) of the process' windows, as CGEvents.
// https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/blob/master/specs/XI2proto.txt (the sections
// "Touch event sequences", "Gesture event sequences" and "XISelectEvents").
//
// A window that selects touch events no longer gets the pointer events the server would emulate from them: the
// framework above (AppKit's touch tracking) moves the mouse itself for views that take no touches.

#import "CGSX11Pointer.h"
#import "CGSConnectionX11.h"
#import "X11InputMask.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>

// The event types of the pinch gestures (CGEvent.h has no names for them), and the NSEventPhase bits their
// events carry.
enum {
    CGSX11EventTypeRotate = 18,
    CGSX11EventTypeMagnify = 30,
};
enum {
    CGSX11GesturePhaseBegan = 1 << 0,
    CGSX11GesturePhaseChanged = 1 << 2,
    CGSX11GesturePhaseEnded = 1 << 3,
    CGSX11GesturePhaseCancelled = 1 << 4,
};

@implementation CGSX11Pointer (Touch)

- (void) selectTouchInputOnWindow: (Window) window {
    if (_xiOpcode == 0 || !_touchSelectable || window == None)
        return;
    unsigned char bits[X11InputMaskLength];
    X11InputEventMask(bits, true, _pinchSelectable);
    XIEventMask mask = {.deviceid = XIAllMasterDevices, .mask_len = sizeof(bits), .mask = bits};
    XISelectEvents(_connection->_display, window, &mask, 1);
}

#pragma mark - Touch

// What every event posted here carries: the keyboard's modifier flags, the window system window and where in it (device
// pixels), and the global location.
- (void) addCommonFieldsTo: (CGEventRef) event window: (Window) window x: (double) x y: (double) y root: (CGPoint) root {
    CGPoint global = [_connection _cgPointFromRoot: root];

    CGEventSetFlags(event, (CGEventFlags) [_connection modifierFlags]);
    CGEventSetLocation(event, global);
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) window);
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, llround(x));
    CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, llround(y));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(global.x * 1024));
    CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(global.y * 1024));
}

- (void) touchEventType: (int) type
                 device: (int) deviceID
                 detail: (unsigned int) detail
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY
{
    int64_t phase;

    switch (type) {
    case XI_TouchBegin:
        phase = kCGSTouchPhaseBegan;
        break;
    case XI_TouchUpdate:
        phase = kCGSTouchPhaseMoved;
        break;
    case XI_TouchEnd:
        phase = kCGSTouchPhaseEnded;
        break;
    default:
        return;
    }
    CGEventRef event = CGEventCreate((CGEventSourceRef) _source);

    if (event == NULL)
        return;
    CGEventSetType(event, (CGEventType) kCGSEventTypeGesture);
    // Touch numbers are per device.
    CGEventSetIntegerValueField(event, kCGSTouchIdentifier, ((int64_t) deviceID << 32) | (int64_t) detail);
    CGEventSetIntegerValueField(event, kCGSTouchPhase, phase);
    if (phase == kCGSTouchPhaseEnded) {
        // As on Wayland, an end carries no position: the finger leaves where it last was.
        CGEventSetIntegerValueField(event, kCGSEventNativeWindow, (int64_t) eventWindow);
        CGEventSetIntegerValueField(event, kCGSTouchLocationUnknown, 1);
    } else {
        [self addCommonFieldsTo: event window: eventWindow x: eventX y: eventY root: CGPointMake(rootX, rootY)];
    }
    _CGSEventStreamPost(event);
    CFRelease(event);
}

#pragma mark - Pinch

- (void) postGestureType: (int) type
                   phase: (int64_t) phase
           magnification: (double) magnification
                rotation: (double) rotation
{
    CGEventRef event = CGEventCreate((CGEventSourceRef) _source);

    if (event == NULL)
        return;
    CGEventSetType(event, (CGEventType) type);
    CGEventSetIntegerValueField(event, kCGSGesturePhase, phase);
    CGEventSetIntegerValueField(event, kCGSGestureMagnification, llround(magnification * 1000000));
    CGEventSetIntegerValueField(event, kCGSGestureRotation, llround(rotation * 1000000));
    [self addCommonFieldsTo: event window: _pinchWindow x: _pinchX y: _pinchY
                       root: CGPointMake(_pinchRootX, _pinchRootY)];
    _CGSEventStreamPost(event);
    CFRelease(event);
}

// Both gestures end together, as they begin together.
- (void) endPinchWithPhase: (int64_t) phase {
    [self postGestureType: CGSX11EventTypeMagnify phase: phase magnification: 0 rotation: 0];
    [self postGestureType: CGSX11EventTypeRotate phase: phase magnification: 0 rotation: 0];
    _pinchActive = NO;
    _pinchWindow = None;
}

- (void) cancelPinchOnWindow: (Window) window {
    if (_pinchActive && _pinchWindow == window)
        [self endPinchWithPhase: CGSX11GesturePhaseCancelled];
}

#ifdef X11_XI_GESTURES
// XInput gives the absolute scale since the fingers began and the clockwise rotation since the previous update. The
// events carry the change in magnification and the rotation in degrees counterclockwise.
- (void) pinchEventType: (int) type
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled
{
    if (type == XI_GesturePinchBegin)
        _pinchActive = NO;
    else if (!_pinchActive)
        return;
    if (type != XI_GesturePinchBegin && type != XI_GesturePinchUpdate && type != XI_GesturePinchEnd)
        return;

    _pinchX = eventX;
    _pinchY = eventY;
    _pinchRootX = rootX;
    _pinchRootY = rootY;
    switch (type) {
    case XI_GesturePinchBegin:
        _pinchWindow = eventWindow;
        _pinchScale = 1;
        _pinchActive = YES;
        [self postGestureType: CGSX11EventTypeMagnify phase: CGSX11GesturePhaseBegan magnification: 0 rotation: 0];
        [self postGestureType: CGSX11EventTypeRotate phase: CGSX11GesturePhaseBegan magnification: 0 rotation: 0];
        break;

    case XI_GesturePinchUpdate: {
        // GUESS: the sign of AppKit's rotation. The Wayland backend sends the negated clockwise angle, and
        // the documentation of NSEvent.rotation does not say which way is positive.
        double rotation = -degrees;
        if (scale != _pinchScale)
            [self postGestureType: CGSX11EventTypeMagnify phase: CGSX11GesturePhaseChanged
                    magnification: scale - _pinchScale rotation: 0];
        if (rotation != 0)
            [self postGestureType: CGSX11EventTypeRotate phase: CGSX11GesturePhaseChanged magnification: 0
                         rotation: rotation];
        _pinchScale = scale;
        break;
    }

    case XI_GesturePinchEnd:
        [self endPinchWithPhase: cancelled ? CGSX11GesturePhaseCancelled : CGSX11GesturePhaseEnded];
        break;
    }
}
#endif

@end
