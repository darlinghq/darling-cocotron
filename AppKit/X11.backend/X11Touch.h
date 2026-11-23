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

#import <X11/Xlib.h>

#import "X11Display.h"

/*
 * Touch screens, through XInput 2.2. libXi is loaded when the display opens,
 * so a host without it (or a server without XInput 2.2) just
 * has no touches. A window that selects touch events no longer gets the
 * pointer events the server would emulate from them: AppKit's touch router
 * (NSTouchPost) moves the mouse itself for views that take no touches.
 *
 * The version asked for is 2.4. When the server has it, and the XInput headers do (X11_XI_GESTURES),
 * the same selection also asks for touchpad pinch gestures (X11Gesture.h). A device reports touches or
 * gestures, never both, and gestures only come from dependent devices such as touchpads; which one a
 * device reports is a property of the device, not of the version a client asks for, so touch
 * screens and servers without 2.4 behave as before.
 */
BOOL X11TouchInit(Display *display);
void X11TouchSelectWindow(Display *display, Window window);
// YES when the event was an XInput touch event (handled or not).
BOOL X11TouchHandleEvent(X11Display *display, XEvent *event);

@interface X11Display (X11Touch)
// One XInput touch event (XI_TouchBegin, XI_TouchUpdate or XI_TouchEnd) for
// the window it was selected on, with its position in that window and on the
// root window. Split from X11TouchHandleEvent so the event can be fed in
// without a touch device.
- (void) touchEventType: (int) type
                 device: (int) deviceID
                 detail: (unsigned int) detail
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY;
@end
