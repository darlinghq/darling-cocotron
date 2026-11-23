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

/* Which windows hear the pointer move, for the X11 backend.
 *
 * The core protocol reports a motion with no button down (MotionNotify) only to a window that selected
 * PointerMotionMask; ButtonMotionMask reports it while a button is down. AppKit wants the motion for two
 * reasons: the window accepts mouse-moved events, and a cursor hidden until the pointer moves
 * (+[NSCursor setHiddenUntilMouseMoves:]) must come back on the next motion even when no window accepts
 * them. Only Xlib's event masks, so tests/x11-pointer-motion.c can drive it against Xvfb. */
#ifndef X11_POINTER_MOTION_H
#define X11_POINTER_MOTION_H

#include <X11/X.h>
#include <stdbool.h>

static inline long X11PointerMotionEventMask(bool acceptsMouseMovedEvents, bool cursorAwaitsMotion) {
    return acceptsMouseMovedEvents || cursorAwaitsMotion ? PointerMotionMask : 0;
}

#endif
