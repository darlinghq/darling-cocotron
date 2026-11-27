/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/

/* Which LeaveNotify events mean the pointer left a window, for the X11 backend.
 *
 * The core protocol (https://www.x.org/releases/current/doc/xproto/x11protocol.html, "Pointer Window" and
 * "EnterNotify, LeaveNotify" in the event section) sends a window a LeaveNotify with a mode and a detail:
 *  - mode NotifyGrab is sent when a pointer grab activates, as if the pointer had moved to the grab window. The
 *    pointer has not moved, so the window is not left in the sense AppKit tracks.
 *  - mode NotifyNormal is a real move; NotifyUngrab is sent when a grab ends, as if the pointer moved from the
 *    grab window to the window it is really over. A pointer that left a window during a grab with owner_events False
 *    (the drag grab, CGSX11Drag.m in CoreGraphics) is reported to the window by this crossing when the grab ends. With
 *    owner_events True (the other grabs of this backend) the window can still receive the Ungrab crossing; a probe
 *    of such a grab without LeaveWindowMask in its mask delivered a Normal leave when the pointer was warped out,
 *    then the Ungrab leave on release. Nothing more is claimed for it. The coordinates of both are the pointer's
 *    real position.
 *  - detail NotifyInferior means the pointer moved into a child window and so is still inside this one. Every other
 *    detail (Ancestor, Virtual, Nonlinear, NonlinearVirtual) means the pointer is no longer in the window or in
 *    any of its children.
 * Only Xlib's constants, so tests/x11-leave-notify.c can drive it against Xvfb. */
#ifndef X11_CROSSING_H
#define X11_CROSSING_H

#include <X11/X.h>
#include <stdbool.h>

static inline bool X11LeaveNotifyMeansPointerLeft(int mode, int detail) {
    return mode != NotifyGrab && detail != NotifyInferior;
}

#endif
