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

/* The XInput 2 events the X11 backend selects on a window.
 *
 * One XISelectEvents request sets the whole mask a client has on a window for a device, so every kind of event
 * has to be in the same mask: a second request for the touch events would drop the gesture events. Touch
 * screens report touches (XI 2.2). A touchpad reports pinch gestures (XI 2.4: GesturePinchBegin, Update and End),
 * and the specification says a client must select all three of them together. A device sends touch events or
 * gesture events, not both, and gesture events only reach a client that announced version 2.4 with XIQueryVersion.
 * https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/blob/master/specs/XI2proto.txt (the sections "Gesture
 * event sequences" and "XISelectEvents")
 *
 * The pinch constants come with XInput 2.4 (xorgproto 2021.5 and libXi 1.8). With older headers
 * X11_XI_GESTURES is not defined, the pinch events are compiled out and only touch is selected.
 *
 * Only the XI2 constants, so tests/x11-gesture-select.c can drive it against Xvfb. */
#ifndef X11_INPUT_MASK_H
#define X11_INPUT_MASK_H

#include <X11/extensions/XI2.h>
#include <stdbool.h>
#include <string.h>

#ifdef XI_GesturePinchBegin
#define X11_XI_GESTURES 1
#endif

enum { X11InputMaskLength = XIMaskLen(XI_LASTEVENT) };

/* Fills a mask of X11InputMaskLength bytes. */
static inline void X11InputEventMask(unsigned char bits[X11InputMaskLength], bool touch, bool pinch) {
    memset(bits, 0, X11InputMaskLength);
    if (touch) {
        XISetMask(bits, XI_TouchBegin);
        XISetMask(bits, XI_TouchUpdate);
        XISetMask(bits, XI_TouchEnd);
    }
#ifdef X11_XI_GESTURES
    if (pinch) {
        XISetMask(bits, XI_GesturePinchBegin);
        XISetMask(bits, XI_GesturePinchUpdate);
        XISetMask(bits, XI_GesturePinchEnd);
    }
#else
    (void) pinch;
#endif
}

#endif
