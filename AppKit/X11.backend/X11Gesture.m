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

#import "X11Gesture.h"
#import "X11Window.h"
#import "NSEvent_gesture.h"

@implementation X11Display (X11Gesture)

- (void) postGesture: (NSEventType) type
               phase: (NSEventPhase) phase
       magnification: (CGFloat) magnification
            rotation: (float) rotation
{
    X11Window *window = (X11Window *) [self windowForID: _pinchWindow];
    if (![window isKindOfClass: [X11Window class]])
        return;
    NSEvent *event = [[[NSEvent_gesture alloc] initWithType: type
                                                   location: _pinchLocation
                                              modifierFlags: _pinchModifiers
                                                     window: [window delegate]
                                                      phase: phase
                                              magnification: magnification
                                                   rotation: rotation] autorelease];
    [self postEvent: event atStart: NO];
}

// Both gestures end together, as they begin together.
- (void) endPinchWithPhase: (NSEventPhase) phase {
    [self postGesture: NSEventTypeMagnify phase: phase magnification: 0 rotation: 0];
    [self postGesture: NSEventTypeRotate phase: phase magnification: 0 rotation: 0];
    _pinchWindow = None;
}

- (void) cancelPinch {
    if (_pinchWindow != None)
        [self endPinchWithPhase: NSEventPhaseCancelled];
}

- (void) cancelPinchOnWindow: (Window) window {
    if (_pinchWindow == window)
        [self cancelPinch];
}

#ifdef X11_XI_GESTURES
// XInput gives the absolute scale since the fingers began and the clockwise rotation since the previous update.
// AppKit events carry the change in magnification and the rotation in degrees counterclockwise.
- (void) pinchEventType: (int) type
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled
              modifiers: (unsigned int) modifiers
{
    if (type == XI_GesturePinchBegin)
        _pinchWindow = None;
    else if (_pinchWindow == None)
        return;

    X11Window *window = (X11Window *) [self windowForID: type == XI_GesturePinchBegin ? eventWindow : _pinchWindow];
    if (![window isKindOfClass: [X11Window class]])
        return;
    _pinchLocation = [window logicalPoint: NSMakePoint(eventX, eventY)];
    _pinchModifiers = [self modifierFlagsForState: modifiers];

    switch (type) {
    case XI_GesturePinchBegin:
        _pinchWindow = eventWindow;
        _pinchScale = 1;
        [self postGesture: NSEventTypeMagnify phase: NSEventPhaseBegan magnification: 0 rotation: 0];
        [self postGesture: NSEventTypeRotate phase: NSEventPhaseBegan magnification: 0 rotation: 0];
        break;

    case XI_GesturePinchUpdate: {
        // GUESS: the sign of AppKit's rotation. The Wayland backend sends the negated clockwise angle, and
        // the documentation of NSEvent.rotation does not say which way is positive.
        float rotation = -degrees;
        if (scale != _pinchScale)
            [self postGesture: NSEventTypeMagnify phase: NSEventPhaseChanged
                magnification: scale - _pinchScale rotation: 0];
        if (rotation != 0)
            [self postGesture: NSEventTypeRotate phase: NSEventPhaseChanged magnification: 0 rotation: rotation];
        _pinchScale = scale;
        break;
    }

    case XI_GesturePinchEnd:
        [self endPinchWithPhase: cancelled ? NSEventPhaseCancelled : NSEventPhaseEnded];
        break;
    }
}
#endif

@end
