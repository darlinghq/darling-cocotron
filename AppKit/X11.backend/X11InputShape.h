/* Click-through windows for the X11 backend.
 *
 * -[NSWindow setIgnoresMouseEvents:YES] makes a window transparent to the mouse: pointer and crossing events go to
 * whatever is below it. X11 does that with the SHAPE extension's input region: a window whose input region is
 * empty never receives pointer events and is skipped when the server looks for the window under the pointer.
 * Restoring the default region (no mask) makes the window clickable again.
 *
 * Only Xlib and Xext, so tests/x11-input-shape.c can drive it against Xvfb. */
#ifndef X11_INPUT_SHAPE_H
#define X11_INPUT_SHAPE_H

#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdbool.h>

/* Returns whether the request could be made (the server has the SHAPE extension). */
static inline bool X11WindowSetIgnoresMouseEvents(Display *display, Window window, bool ignores) {
    int eventBase, errorBase;
    if (!XShapeQueryExtension(display, &eventBase, &errorBase))
        return false;
    if (ignores)
        XShapeCombineRectangles(display, window, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
    else
        XShapeCombineMask(display, window, ShapeInput, 0, 0, None, ShapeSet);
    return true;
}

#endif
