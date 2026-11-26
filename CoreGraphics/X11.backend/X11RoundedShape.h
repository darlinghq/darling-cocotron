/* Rounded window corners for the X11 backend.
 *
 * A window that shows no window manager frame (a full-size content view under a transparent title bar,
 * whose content is the whole window) has the rounded corners of any window on macOS. Without a frame the
 * server draws the window as a plain rectangle, so the corners are cut away with the SHAPE extension's
 * bounding region, which needs no compositor: what is outside the region is not part of the window and
 * shows what is behind it.
 *
 * X11RoundedCornerInset gives the number of pixels cut from the left edge (and, mirrored, from the right
 * edge) of a row of the corner, counted from the top or bottom edge of the window.
 *
 * Only Xlib and Xext, so tests/x11-rounded-shape.c can drive it against Xvfb. */
#ifndef X11_ROUNDED_SHAPE_H
#define X11_ROUNDED_SHAPE_H

#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>

/* Pixels of row `row` (0 is the outermost row) cut away by a corner of the given radius: the row's
 * centre is compared with a circle through the corner's inner edges. */
static inline int X11RoundedCornerInset(int radius, int row) {
    if (radius <= 0 || row < 0 || row >= radius)
        return 0;
    double dy = radius - (row + 0.5);
    double dx = sqrt((double) radius * radius - dy * dy);
    int inset = (int) ceil(radius - dx);
    return inset < 0 ? 0 : inset;
}

/* Cuts the corners of the window's bounding region; a radius of 0 restores the whole rectangle. Returns
 * whether the request could be made (the server has SHAPE). */
static inline bool X11WindowSetRoundedCorners(Display *display, Window window, int width, int height, int radius) {
    int eventBase, errorBase;
    if (!XShapeQueryExtension(display, &eventBase, &errorBase))
        return false;
    if (radius <= 0 || width < 2 * radius || height < 2 * radius) {
        XShapeCombineMask(display, window, ShapeBounding, 0, 0, None, ShapeSet);
        return true;
    }
    /* One rectangle per corner row at the top and at the bottom, and one for the middle. */
    XRectangle *rectangles = malloc(sizeof(XRectangle) * (2 * (size_t) radius + 1));
    if (rectangles == NULL)
        return false;
    int count = 0;
    for (int row = 0; row < radius; row++) {
        int inset = X11RoundedCornerInset(radius, row);
        rectangles[count++] = (XRectangle){(short) inset, (short) row, (unsigned short) (width - 2 * inset), 1};
    }
    rectangles[count++] = (XRectangle){0, (short) radius, (unsigned short) width, (unsigned short) (height - 2 * radius)};
    for (int row = radius - 1; row >= 0; row--) {
        int inset = X11RoundedCornerInset(radius, row);
        rectangles[count++] = (XRectangle){(short) inset, (short) (height - 1 - row),
                                           (unsigned short) (width - 2 * inset), 1};
    }
    XShapeCombineRectangles(display, window, ShapeBounding, 0, 0, rectangles, count, ShapeSet, YXBanded);
    free(rectangles);
    return true;
}

#endif
