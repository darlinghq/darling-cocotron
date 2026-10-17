/* Pure geometry of CoreGraphics' global display space, shared by CGDirectDisplay.m and the host tests.
 *
 * CoreGraphics' global space has its origin at the top-left corner of the main display and y growing downward
 * (CGDisplayBounds, CGEventGetLocation, CGWarpMouseCursorPosition); a display above or left of the main one has a
 * negative y or x. Cocoa's global space (NSScreen.frame, window frames, +[NSEvent mouseLocation]) has its origin at
 * the main display's bottom-left corner and y growing upward. Both are measured in points, and a point is
 * 1/scale of a device pixel.
 *
 * Conversion rules, written down once:
 *  - CG <-> Cocoa is a flip against the main display's height in points (the flip is its own inverse).
 *  - CGDisplayMoveCursorToPoint takes a point relative to the upper-left corner of the given display; the global
 *    point is that display's CGDisplayBounds origin plus the point.
 *  - Points outside the desktop (the union of the active displays) are clipped to its bounds, one device pixel
 *    inside the far edges because a pixel at maxX or maxY does not exist. A point inside the desktop but outside
 *    every display (the corner of an L-shaped layout) is left to the window system, which moves the pointer to a
 *    pixel that exists.
 *  - The window system moves the pointer in whole device pixels: a point is rounded to the nearest pixel of the
 *    window system's own coordinates (ties away from zero there, not in CoreGraphics' space, whose origin may be
 *    offset), so reading the pointer after a warp returns that pixel in points, and warping to what was read
 *    changes nothing.
 *
 * Plain C with no dependencies, so tests/ can include it. */
#ifndef CG_DISPLAY_GEOMETRY_H
#define CG_DISPLAY_GEOMETRY_H

#include <math.h>
#include <stdbool.h>

typedef struct {
    double x, y;
} CGDisplayGeometryPoint;

typedef struct {
    double x, y, width, height;
} CGDisplayGeometryRect;

/* Global CG point <-> global Cocoa point. mainHeight is the main display's height in points. */
static inline CGDisplayGeometryPoint CGDisplayGeometryFlip(double mainHeight, CGDisplayGeometryPoint point) {
    CGDisplayGeometryPoint flipped = {point.x, mainHeight - point.y};
    return flipped;
}

/* A point relative to the upper-left corner of a display, as global CG point. */
static inline CGDisplayGeometryPoint CGDisplayGeometryDisplayToGlobal(CGDisplayGeometryRect displayBounds,
                                                                      CGDisplayGeometryPoint point) {
    CGDisplayGeometryPoint global = {displayBounds.x + point.x, displayBounds.y + point.y};
    return global;
}

/* The smallest rectangle holding both. An empty (zero width or height) rectangle is ignored. */
static inline CGDisplayGeometryRect CGDisplayGeometryUnion(CGDisplayGeometryRect a, CGDisplayGeometryRect b) {
    if (a.width <= 0 || a.height <= 0)
        return b;
    if (b.width <= 0 || b.height <= 0)
        return a;
    double minX = fmin(a.x, b.x), minY = fmin(a.y, b.y);
    double maxX = fmax(a.x + a.width, b.x + b.width), maxY = fmax(a.y + a.height, b.y + b.height);
    CGDisplayGeometryRect united = {minX, minY, maxX - minX, maxY - minY};
    return united;
}

/* Clips a point to the desktop bounds; the far edges are exclusive, so the last valid point is one device
 * pixel (1/scale) inside. With empty bounds the point is returned unchanged. */
static inline CGDisplayGeometryPoint CGDisplayGeometryClamp(CGDisplayGeometryRect desktop, double scale,
                                                            CGDisplayGeometryPoint point) {
    if (desktop.width <= 0 || desktop.height <= 0)
        return point;
    double pixel = 1.0 / scale;
    double maxX = desktop.x + desktop.width - pixel, maxY = desktop.y + desktop.height - pixel;
    CGDisplayGeometryPoint clamped = {fmin(fmax(point.x, desktop.x), maxX), fmin(fmax(point.y, desktop.y), maxY)};
    return clamped;
}

#endif
