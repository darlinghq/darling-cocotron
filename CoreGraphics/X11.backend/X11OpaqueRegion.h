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

/* Advertising the opaque region of an opaque window.
 *
 * -[NSWindow isOpaque] answers YES when every pixel of the window is opaque. A window on a visual without an
 * alpha channel (depth 24) is opaque to a compositing manager already. A window on a 32-bit visual has an alpha
 * channel; _NET_WM_OPAQUE_REGION (EWMH, CARDINAL[][4]/32, rectangles x, y, width, height in window coordinates)
 * is the client's promise that those pixels are already opaque, so a manager can skip drawing what lies behind
 * them. It is an occlusion and performance hint that a manager may ignore, and the specification calls it not
 * typically useful for a window without alpha, so it is set only for an opaque window on a 32-bit visual and
 * removed otherwise.
 *
 * It does not make pixels with alpha below 1 show as opaque, as an XRGB buffer does on Wayland. A window that
 * should show opaque needs a visual without alpha, and a visual cannot change once the window is mapped.
 * https://specifications.freedesktop.org/wm-spec/latest/ (the _NET_WM_OPAQUE_REGION entry)
 *
 * Only Xlib, so tests/x11-opaque-region.c can drive it against Xvfb. */
#ifndef X11_OPAQUE_REGION_H
#define X11_OPAQUE_REGION_H

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdbool.h>

/* Whether a window of this depth that is opaque gets the hint. */
static inline bool X11OpaqueRegionApplies(int depth, bool windowIsOpaque) {
    return windowIsOpaque && depth == 32;
}

/* Sets the hint to cover the whole window of the given size in device pixels, or removes it. Returns whether
 * a region is set afterwards. */
static inline bool X11WindowSetOpaqueRegion(Display *display, Window window, int depth, bool windowIsOpaque,
                                            int width, int height) {
    Atom property = XInternAtom(display, "_NET_WM_OPAQUE_REGION", False);
    if (!X11OpaqueRegionApplies(depth, windowIsOpaque)) {
        XDeleteProperty(display, window, property);
        return false;
    }
    long region[4] = {0, 0, width, height};
    XChangeProperty(display, window, property, XA_CARDINAL, 32, PropModeReplace, (const unsigned char *) region, 4);
    return true;
}

#endif
