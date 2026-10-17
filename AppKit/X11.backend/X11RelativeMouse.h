/* Decision logic for macOS-style relative mouse mode in the X11 backend.
 *
 * While CGAssociateMouseAndMouseCursorPosition(false) is in effect, macOS freezes the cursor: physical motion
 * only produces deltas, events report the frozen cursor position, and CGWarpMouseCursorPosition moves the cursor
 * without producing a delta. Here the frozen cursor is the "virtual" position (X root coordinates). Core X motion
 * still moves the real pointer, so deltas are measured against the last physical position, and where the server
 * honours warps the pointer is warped back to the virtual position after each motion. Every warp (ours or the
 * application's) is followed by a MotionNotify at its target; those echoes are recognised by request serial
 * and position and dropped. Warps are synchronous (XSync), so an echo can only be among the events already queued at that moment;
 * an expected echo expires once that many events have been handled.
 *
 * On Xwayland a warp only reaches the compositor while the X cursor is hidden. With a visible cursor the echo
 * still arrives, but the next real motion reports the unmoved physical pointer, so honoured=false keeps the last
 * physical position across echoes and never warps back.
 *
 * Threading: the model is not thread-safe. Every call on one X11RelativeMouse must come from a single thread (in
 * the backend the thread that pumps X events) or be serialized by the caller's lock: ExpectEcho reallocates the
 * pending-echo array that HandleMotion and Tick walk.
 *
 * Plain C without X11 or Objective-C dependencies, so tests/x11-relative-mouse.c can run it on the host. */
#ifndef X11_RELATIVE_MOUSE_H
#define X11_RELATIVE_MOUSE_H

#include <stdbool.h>
#include <stdlib.h>

#define X11_RELATIVE_MOUSE_INITIAL_ECHOES 8

typedef struct {
    int x, y;
    unsigned long serial; /* X request that generated the echo; coordinates alone also match real motion */
    unsigned remaining; /* X events (of any type) still to be handled before this echo is given up */
} X11RelativeMouseEcho;

/* The rectangle the pointer can reach (the confine_to window clipped to the screen), inclusive, root coordinates. */
typedef struct {
    int minX, minY, maxX, maxY;
} X11RelativeMouseBounds;

typedef struct {
    bool active;              /* relative motion handling is on (the pointer grab is held) */
    double virtualX, virtualY; /* the frozen macOS cursor, X root coordinates */
    int physicalX, physicalY; /* last physical pointer position, X root coordinates */
    unsigned long firstSerial; /* ignore motion queued before the initial XQueryPointer snapshot */
    int minX, minY, maxX, maxY; /* inclusive root coordinates the server can place the pointer in */
    unsigned echoCount;
    unsigned echoCapacity;
    X11RelativeMouseEcho *echoes; /* oldest first; never discard a pending warp echo on overflow */
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

/* Serial a is older than serial b. Serials wrap (32 bits wide on i386), so compare the difference. */
static inline bool X11RelativeMouseSerialBefore(unsigned long a, unsigned long b) {
    return (long)(a - b) < 0;
}

/* Zero-initialize the storage once before the first Begin; End releases the pending-echo allocation. The pointer
 * starts at (rootX, rootY) inside bounds; motion with a serial before firstSerial predates that snapshot and is
 * ignored. The model keeps warp targets inside bounds (see Warp), so neither the virtual cursor nor a recorded
 * echo can sit where the server never puts the pointer. */
static inline void X11RelativeMouseBegin(X11RelativeMouse *mouse, int rootX, int rootY, unsigned long firstSerial,
                                         X11RelativeMouseBounds bounds) {
    free(mouse->echoes);
    mouse->echoes = NULL;
    mouse->echoCapacity = 0;
    mouse->firstSerial = firstSerial;
    mouse->minX = bounds.minX;
    mouse->minY = bounds.minY;
    mouse->maxX = bounds.maxX;
    mouse->maxY = bounds.maxY;
    mouse->active = true;
    mouse->virtualX = rootX;
    mouse->virtualY = rootY;
    mouse->physicalX = rootX;
    mouse->physicalY = rootY;
    mouse->echoCount = 0;
}

static inline void X11RelativeMouseEnd(X11RelativeMouse *mouse) {
    free(mouse->echoes);
    mouse->echoes = NULL;
    mouse->echoCapacity = 0;
    mouse->active = false;
    mouse->echoCount = 0;
}

/* Record a warp to (x, y) that was just sent and synced. queuedEvents is the number of X events queued after the
 * sync; zero means the warp produced no event (the pointer was already there). */
static inline bool X11RelativeMouseExpectEcho(X11RelativeMouse *mouse, int x, int y, unsigned queuedEvents,
                                              unsigned long serial) {
    if (!queuedEvents) return true;
    if (mouse->echoCount) {
        X11RelativeMouseEcho *last = &mouse->echoes[mouse->echoCount - 1];
        if (last->x == x && last->y == y && last->serial == serial) {
            if (last->remaining < queuedEvents) last->remaining = queuedEvents;
            return true;
        }
    }
    if (mouse->echoCount == mouse->echoCapacity) {
        unsigned capacity = mouse->echoCapacity ? mouse->echoCapacity * 2 : X11_RELATIVE_MOUSE_INITIAL_ECHOES;
        if (capacity <= mouse->echoCapacity) return false;
        X11RelativeMouseEcho *echoes = realloc(mouse->echoes, (size_t)capacity * sizeof(*echoes));
        if (!echoes) return false;
        mouse->echoes = echoes;
        mouse->echoCapacity = capacity;
    }
    mouse->echoes[mouse->echoCount++] = (X11RelativeMouseEcho) {x, y, serial, queuedEvents};
    return true;
}

/* Clamps a target to the confine window, as the server does to the pointer. */
static inline void X11RelativeMouseClamp(const X11RelativeMouse *mouse, double *x, double *y) {
    if (*x < mouse->minX) *x = mouse->minX;
    if (*x > mouse->maxX) *x = mouse->maxX;
    if (*y < mouse->minY) *y = mouse->minY;
    if (*y > mouse->maxY) *y = mouse->maxY;
}

/* CGWarpMouseCursorPosition while relative: the virtual cursor moves to the target; the physical position is
 * only updated when the echo arrives (and only if the warp was honoured). The target is clamped to the bounds
 * first, whether or not warps are honoured: the server clamps the pointer there, so that is where the echo
 * arrives. A caller that sends the warp clamps the same way before (Clamp is idempotent). */
static inline bool X11RelativeMouseWarp(X11RelativeMouse *mouse, double x, double y, unsigned queuedEvents,
                                       unsigned long serial, bool warpsHonoured) {
    X11RelativeMouseClamp(mouse, &x, &y);
    if (warpsHonoured) {
        mouse->virtualX = x;
        mouse->virtualY = y;
    }
    return X11RelativeMouseExpectEcho(mouse, X11RelativeMouseWarpCoordinate(x), X11RelativeMouseWarpCoordinate(y),
                               queuedEvents, serial);
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
                                                                  bool warpsHonoured, unsigned long serial)
{
    X11RelativeMouseMotion result = {false, false, 0.0, 0.0, false, 0, 0};
    if (X11RelativeMouseSerialBefore(serial, mouse->firstSerial)) {
        X11RelativeMouseTick(mouse);
        return result;
    }
    for (unsigned i = 0; i < mouse->echoCount; ++i)
        if (mouse->echoes[i].serial == serial && mouse->echoes[i].x == rootX && mouse->echoes[i].y == rootY) {
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
        /* More physical motion may already be queued before our latest warp. That warp will
         * re-anchor it; issuing another one for each queued event creates an echo backlog. */
        bool pending = mouse->echoCount && X11RelativeMouseSerialBefore(serial, mouse->echoes[mouse->echoCount - 1].serial);
        result.rewarp = !pending;
        result.warpX = warpX;
        result.warpY = warpY;
    }
    X11RelativeMouseTick(mouse);
    return result;
}

#endif
