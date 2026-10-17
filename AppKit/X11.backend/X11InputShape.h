/* Click-through windows for the X11 backend.
 *
 * -[NSWindow setIgnoresMouseEvents:YES] makes a window transparent to the mouse: pointer and crossing events go to
 * whatever is below it. X11 does that with the SHAPE extension's input region: a window whose input region is
 * empty never receives pointer events and is skipped when the server looks for the window under the pointer.
 * Restoring the default region (no mask) makes the window clickable again.
 *
 * The input region (ShapeInput) was added in SHAPE 1.1, so the extension's version is checked, not only its presence.
 *
 * Limit: under a reparenting window manager a TITLED window sits inside a frame window the manager owns, and that
 * frame has no empty input region, so it still catches the pointer. Borderless windows are not reparented
 * (override-redirect, or managed but undecorated), so overlays and tooltips, the cases this exists for, are fully
 * click-through; on macOS a titled window would be too.
 *
 * Only Xlib and Xext, so tests/x11-input-shape.c can drive it against Xvfb. */
#ifndef X11_INPUT_SHAPE_H
#define X11_INPUT_SHAPE_H

#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdbool.h>

/* Whether a SHAPE version has input regions. */
static inline bool X11ShapeVersionHasInput(int major, int minor) {
    return major > 1 || (major == 1 && minor >= 1);
}

/* Returns whether the request could be made (the server has SHAPE 1.1 or later). */
static inline bool X11WindowSetIgnoresMouseEvents(Display *display, Window window, bool ignores) {
    int eventBase, errorBase, major, minor;
    if (!XShapeQueryExtension(display, &eventBase, &errorBase) || !XShapeQueryVersion(display, &major, &minor) ||
        !X11ShapeVersionHasInput(major, minor))
        return false;
    if (ignores)
        XShapeCombineRectangles(display, window, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    else
        XShapeCombineMask(display, window, ShapeInput, 0, 0, None, ShapeSet);
    return true;
}

#endif
