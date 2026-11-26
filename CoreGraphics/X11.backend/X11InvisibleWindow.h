// Copyright (C) 2026 Lubos Dolezel
//
/* Fully transparent windows on a display without a compositing manager, for the X11 backend.
 *
 * -[NSWindow setAlphaValue:] with 0 makes a window invisible on macOS, and it stays an ordinary window: ordered in,
 * key, main. The backend passes the opacity on in _NET_WM_WINDOW_OPACITY, which only a compositing manager applies.
 * Without one the window would stay fully visible, with the window manager's frame around it. The same effect is
 * reached with the SHAPE extension: a window whose bounding region is empty draws nothing (neither its contents nor
 * a frame the window manager gives it, which follows the shape) and is skipped when the server looks for the window
 * under the pointer, while it stays mapped and keeps the keyboard focus.
 *
 * A compositing manager announces itself by owning the selection _NET_WM_CM_S<screen number> (EWMH / ICCCM
 * manager selection convention).
 *
 * Only Xlib and Xext, so a test can drive it against Xvfb. */
#ifndef X11_INVISIBLE_WINDOW_H
#define X11_INVISIBLE_WINDOW_H

#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdbool.h>
#include <stdio.h>

/* Whether a compositing manager owns the screen. */
static inline bool X11CompositorRunning(Display *display, int screen) {
    char name[48];
    snprintf(name, sizeof name, "_NET_WM_CM_S%d", screen);
    return XGetSelectionOwner(display, XInternAtom(display, name, False)) != None;
}

/* Empties (or restores) the bounding region of the window. Returns whether the server has the SHAPE extension. */
static inline bool X11WindowSetBoundingEmpty(Display *display, Window window, bool empty) {
    int eventBase, errorBase;
    if (!XShapeQueryExtension(display, &eventBase, &errorBase))
        return false;
    if (empty)
        XShapeCombineRectangles(display, window, ShapeBounding, 0, 0, NULL, 0, ShapeSet, Unsorted);
    else
        XShapeCombineMask(display, window, ShapeBounding, 0, 0, None, ShapeSet);
    return true;
}

#endif
