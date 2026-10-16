/* Decision logic for macOS-style relative mouse mode in the X11 backend.
 *
 * While CGAssociateMouseAndMouseCursorPosition(false) is in effect, macOS freezes the cursor: physical motion
 * only produces deltas, events report the frozen cursor position, and CGWarpMouseCursorPosition moves the cursor
 * without producing a delta. Here the frozen cursor is the "virtual" position (X root coordinates). Core X motion
 * still moves the real pointer, so deltas are measured against the last physical position, and where the server
 * honours warps the pointer is warped back to the virtual position after each motion. Every warp (ours or the
 * application's) is followed by a MotionNotify at its target; those echoes are recognised by position and
 * dropped. Warps are synchronous (XSync), so an echo can only be among the events already queued at that moment;
 * an expected echo expires once that many events have been handled.
 *
 * On Xwayland a warp only reaches the compositor while the X cursor is hidden. With a visible cursor the echo
 * still arrives, but the next real motion reports the unmoved physical pointer, so honoured=false keeps the last
 * physical position across echoes and never warps back. The cursor the user sees is then the physical pointer,
 * so the virtual cursor follows it and application warps do not move it: League keeps a visible cursor while
 * relative on GNOME and gamescope and warps it at its own mouse speed, which otherwise left the virtual cursor
 * (where clicks land) hundreds of pixels from the visible one and kept it off the screen edges.
 *
 * Plain C without X11 or Objective-C dependencies, so tests/x11-relative-mouse.c can run it on the host. */
#ifndef X11_RELATIVE_MOUSE_H
#define X11_RELATIVE_MOUSE_H

#include <stdbool.h>

#define X11_RELATIVE_MOUSE_MAX_ECHOES 8

typedef struct {
    int x, y;
    unsigned remaining; /* X events (of any type) still to be handled before this echo is given up */
} X11RelativeMouseEcho;

typedef struct {
    bool active;              /* relative motion handling is on (the pointer grab is held) */
    double virtualX, virtualY; /* the frozen macOS cursor, X root coordinates */
    int physicalX, physicalY; /* last physical pointer position, X root coordinates */
    unsigned echoCount;
    X11RelativeMouseEcho echoes[X11_RELATIVE_MOUSE_MAX_ECHOES]; /* oldest first */
} X11RelativeMouse;

typedef struct {
    bool post;             /* deliver a mouse moved/dragged event */
    bool echo;             /* the event was the echo of a warp */
    double deltaX, deltaY; /* NSEvent convention: positive deltaY is downwards */
    bool rewarp;           /* warp the pointer back to (warpX, warpY) */
    int warpX, warpY;
} X11RelativeMouseMotion;

/* X11 warps take integer coordinates; conversions truncate like the original implicit double-to-int argument. */
static inline int X11RelativeMouseWarpCoordinate(double value) {
    return (int) value;
}

static inline void X11RelativeMouseBegin(X11RelativeMouse *mouse, int rootX, int rootY) {
    mouse->active = true;
    mouse->virtualX = rootX;
    mouse->virtualY = rootY;
    mouse->physicalX = rootX;
    mouse->physicalY = rootY;
    mouse->echoCount = 0;
}

static inline void X11RelativeMouseEnd(X11RelativeMouse *mouse) {
    mouse->active = false;
    mouse->echoCount = 0;
}

/* Record a warp to (x, y) that was just sent and synced. queuedEvents is the number of X events queued after the
 * sync; zero means the warp produced no event (the pointer was already there). */
static inline void X11RelativeMouseExpectEcho(X11RelativeMouse *mouse, int x, int y, unsigned queuedEvents) {
    if (!queuedEvents) return;
    if (mouse->echoCount) {
        X11RelativeMouseEcho *last = &mouse->echoes[mouse->echoCount - 1];
        if (last->x == x && last->y == y) {
            if (last->remaining < queuedEvents) last->remaining = queuedEvents;
            return;
        }
    }
    if (mouse->echoCount == X11_RELATIVE_MOUSE_MAX_ECHOES) {
        for (unsigned i = 1; i < mouse->echoCount; ++i)
            mouse->echoes[i - 1] = mouse->echoes[i];
        mouse->echoCount--;
    }
    mouse->echoes[mouse->echoCount++] = (X11RelativeMouseEcho) {x, y, queuedEvents};
}

/* CGWarpMouseCursorPosition while relative: where warps are honoured the virtual cursor moves to the target and
 * the physical position is updated when the echo arrives. Otherwise the pointer stays put, and so does the
 * virtual cursor that tracks it; the echo is still expected so it is not taken for motion. */
static inline void X11RelativeMouseWarp(X11RelativeMouse *mouse, double x, double y, unsigned queuedEvents,
                                        bool warpsHonoured) {
    if (warpsHonoured) {
        mouse->virtualX = x;
        mouse->virtualY = y;
    }
    X11RelativeMouseExpectEcho(mouse, X11RelativeMouseWarpCoordinate(x), X11RelativeMouseWarpCoordinate(y),
                               queuedEvents);
}

/* One X event has been handled: age the expected echoes. */
static inline void X11RelativeMouseTick(X11RelativeMouse *mouse) {
    unsigned kept = 0;
    for (unsigned i = 0; i < mouse->echoCount; ++i)
        if (mouse->echoes[i].remaining > 1) {
            mouse->echoes[kept] = mouse->echoes[i];
            mouse->echoes[kept++].remaining--;
        }
    mouse->echoCount = kept;
}

/* A MotionNotify at root position (rootX, rootY) while relative. Ages the expected echoes. */
static inline X11RelativeMouseMotion X11RelativeMouseHandleMotion(X11RelativeMouse *mouse, int rootX, int rootY,
                                                                  bool warpsHonoured)
{
    X11RelativeMouseMotion result = {false, false, 0.0, 0.0, false, 0, 0};
    for (unsigned i = 0; i < mouse->echoCount; ++i)
        if (mouse->echoes[i].x == rootX && mouse->echoes[i].y == rootY) {
            /* Warps are echoed in order; earlier expected echoes that did not arrive never will. */
            for (unsigned j = i + 1; j < mouse->echoCount; ++j)
                mouse->echoes[j - i - 1] = mouse->echoes[j];
            mouse->echoCount -= i + 1;
            if (warpsHonoured) {
                mouse->physicalX = rootX;
                mouse->physicalY = rootY;
            }
            result.echo = true;
            X11RelativeMouseTick(mouse);
            return result;
        }
    result.deltaX = rootX - mouse->physicalX;
    result.deltaY = rootY - mouse->physicalY;
    mouse->physicalX = rootX;
    mouse->physicalY = rootY;
    if (!warpsHonoured) {
        mouse->virtualX = rootX;
        mouse->virtualY = rootY;
    }
    result.post = result.deltaX != 0.0 || result.deltaY != 0.0;
    int warpX = X11RelativeMouseWarpCoordinate(mouse->virtualX);
    int warpY = X11RelativeMouseWarpCoordinate(mouse->virtualY);
    if (warpsHonoured && (rootX != warpX || rootY != warpY)) {
        result.rewarp = true;
        result.warpX = warpX;
        result.warpY = warpY;
    }
    X11RelativeMouseTick(mouse);
    return result;
}

/* NSEvent deltas for absolute (non-relative) motion between two positions in Cocoa window coordinates, which
 * are bottom-up while NSEvent's deltaY is positive downwards. */
static inline void X11AbsoluteMouseDelta(double lastX, double lastY, double x, double y, double *deltaX,
                                         double *deltaY)
{
    *deltaX = x - lastX;
    *deltaY = lastY - y;
}

#endif
