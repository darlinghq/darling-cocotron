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

#import "X11Display.h"
#import "X11InputMask.h"

/*
 * Pinch gestures on a touchpad, through XInput 2.4 (see X11Touch.h and X11InputMask.h), as AppKit's magnify and
 * rotate events, the way the Wayland backend does for zwp_pointer_gestures_v1. A server without XInput 2.4 just
 * has no gestures. With headers older than XInput 2.4 (no X11_XI_GESTURES, see X11InputMask.h) only the pinch
 * cancelling methods are compiled.
 */
@interface X11Display (X11Gesture)
#ifdef X11_XI_GESTURES
// One XInput pinch event (XI_GesturePinchBegin, Update or End) for the window it was selected on, with its position
// in that window in device pixels, the pinch's scale since the fingers began (1 at the start), the rotation since the
// previous update in degrees clockwise, whether an end cancelled the gesture, and the XKB effective modifiers. Split
// from X11TouchHandleEvent so the event can be fed in without a touchpad.
- (void) pinchEventType: (int) type
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled
              modifiers: (unsigned int) modifiers;
#endif
// Ends an active pinch as cancelled; nothing when none is in progress.
- (void) cancelPinch;
// The same when the pinch is on this window (the window is going away).
- (void) cancelPinchOnWindow: (Window) window;
@end
