/* Click-through windows for the X11 backend.
 *
 * -[NSWindow setIgnoresMouseEvents:YES] makes a window transparent to the mouse: pointer and crossing events go to
 * whatever is below it. X11 does that with the SHAPE extension's input region: a window whose input region is
 * empty never receives pointer events and is skipped when the server looks for the window under the pointer.
 * Restoring the default region (no mask) makes the window clickable again.
 *
 * The input region (ShapeInput) was added in SHAPE 1.1, so the extension's version is checked, not only its presence.
 *
 * Limit: a window manager may put a window inside a frame window it owns (the usual case for a titled
 * window), and that frame has no empty input region, so it still catches the pointer. Override-redirect windows
 * (menus, popups, tooltips, overlays that cannot become key) are never framed, so they are fully click-through.
 * Whether a managed borderless window is framed depends on the window manager and is not verified here; on macOS
 * the whole window would be click-through.
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
