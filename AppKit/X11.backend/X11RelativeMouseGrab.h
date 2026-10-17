/* The Xlib side of macOS-style relative mouse mode: the pointer grab, the pointer warps and the handling of a
 * MotionNotify, on top of the decision model in X11RelativeMouse.h.
 *
 * Only Xlib, no Objective-C, so tests/x11-relative-mouse-x11.c can drive the same code the backend runs against a
 * real server (Xvfb, with XTest supplying the physical motion). */
#ifndef X11_RELATIVE_MOUSE_GRAB_H
#define X11_RELATIVE_MOUSE_GRAB_H

#include "X11RelativeMouse.h"
#include <X11/Xlib.h>

#define X11_RELATIVE_MOUSE_NOT_FOCUSED (-1)
#define X11_RELATIVE_MOUSE_QUERY_FAILED (-2)

/* Whether window holds the keyboard focus: directly, through a descendant (an embedded child window), or through an
 * ancestor (a reparenting window manager may focus the frame it put around the window). */
static inline bool X11RelativeMouseWindowHasFocus(Display *display, Window window) {
    Window focus;
    int revert;
    XGetInputFocus(display, &focus, &revert);
    Window root = DefaultRootWindow(display), ancestor = focus;
    for (int depth = 0; depth < 64 && ancestor != window && ancestor != None && ancestor != PointerRoot &&
                        ancestor != root;
         depth++) {
        Window queriedRoot, parent, *children = NULL;
        unsigned int count;
        if (!XQueryTree(display, ancestor, &queriedRoot, &parent, &children, &count))
            return false;
        if (children)
            XFree(children);
        ancestor = parent;
    }
    if (ancestor == window)
        return true;
    /* The focus may be an ancestor of the window. The root and PointerRoot are not a window's own focus. */
    if (focus == None || focus == PointerRoot || focus == root)
        return false;
    ancestor = window;
    for (int depth = 0; depth < 64 && ancestor != None && ancestor != root; depth++) {
        Window queriedRoot, parent, *children = NULL;
        unsigned int count;
        if (!XQueryTree(display, ancestor, &queriedRoot, &parent, &children, &count))
            return false;
        if (children)
            XFree(children);
        if (parent == focus)
            return true;
        ancestor = parent;
    }
    return false;
}

/* The rectangle the pointer is confined to (the grab window clipped to the screen, in root coordinates). XWarpPointer
 * clips to it, not to the monitor. Returns false when the window has no visible area or cannot be queried. */
static inline bool X11RelativeMouseWindowBounds(Display *display, Window window, X11RelativeMouseBounds *bounds) {
    XWindowAttributes attributes;
    Window child;
    int x, y;
    if (!XGetWindowAttributes(display, window, &attributes) ||
        !XTranslateCoordinates(display, window, DefaultRootWindow(display), 0, 0, &x, &y, &child))
        return false;
    int screen = DefaultScreen(display);
    bounds->minX = x < 0 ? 0 : x;
    bounds->minY = y < 0 ? 0 : y;
    bounds->maxX = x + attributes.width - 1;
    if (bounds->maxX > DisplayWidth(display, screen) - 1)
        bounds->maxX = DisplayWidth(display, screen) - 1;
    bounds->maxY = y + attributes.height - 1;
    if (bounds->maxY > DisplayHeight(display, screen) - 1)
        bounds->maxY = DisplayHeight(display, screen) - 1;
    return bounds->maxX >= bounds->minX && bounds->maxY >= bounds->minY;
}

/* Takes the pointer grab on window (confined to it) and starts the virtual cursor at the current pointer
 * position. Returns GrabSuccess, X11_RELATIVE_MOUSE_NOT_FOCUSED when the window does not hold the focus (a grab
 * would take the pointer from whichever client does), X11_RELATIVE_MOUSE_QUERY_FAILED, or the XGrabPointer error.
 * Nothing is left grabbed on failure. warpsHonoured is whether the server moves the pointer
 * for XWarpPointer (see the backend); the pointer is parked away from the confine edge only then. */
static inline bool X11RelativeMouseApplicationWarp(Display *display, X11RelativeMouse *mouse, double x, double y,
                                                   bool warpsHonoured);

static inline int X11RelativeMouseGrab(Display *display, X11RelativeMouse *mouse, Window window, bool warpsHonoured) {
    if (!X11RelativeMouseWindowHasFocus(display, window))
        return X11_RELATIVE_MOUSE_NOT_FOCUSED;
    /* FocusChangeMask is not a valid pointer-grab event. */
    const unsigned int events = ButtonPressMask | ButtonReleaseMask | PointerMotionMask;
    int result = XGrabPointer(display, window, False, events, GrabModeAsync, GrabModeAsync, window, None, CurrentTime);
    if (result != GrabSuccess)
        return result;
    Window root, child;
    int rootX, rootY, windowX, windowY;
    unsigned int state;
    unsigned long snapshotSerial = NextRequest(display);
    if (!XQueryPointer(display, window, &root, &child, &rootX, &rootY, &windowX, &windowY, &state)) {
        XUngrabPointer(display, CurrentTime);
        return X11_RELATIVE_MOUSE_QUERY_FAILED;
    }
    X11RelativeMouseBounds bounds;
    if (!X11RelativeMouseWindowBounds(display, window, &bounds)) {
        XUngrabPointer(display, CurrentTime);
        return X11_RELATIVE_MOUSE_QUERY_FAILED;
    }
    X11RelativeMouseBegin(mouse, rootX, rootY, snapshotSerial, bounds);
    /* Park the pointer at once, so the first motion after a grab at an edge is not clipped either. The cursor
     * stays where the pointer was. */
    if (!X11RelativeMouseApplicationWarp(display, mouse, rootX, rootY, warpsHonoured)) {
        XUngrabPointer(display, CurrentTime);
        X11RelativeMouseEnd(mouse);
        return X11_RELATIVE_MOUSE_QUERY_FAILED;
    }
    return GrabSuccess;
}

/* Gives the pointer back. Safe when relative mode is not active. */
static inline void X11RelativeMouseRelease(Display *display, X11RelativeMouse *mouse) {
    if (!mouse->active)
        return;
    XUngrabPointer(display, CurrentTime);
    XFlush(display);
    X11RelativeMouseEnd(mouse);
}

/* Moves the pointer and waits for the server, so the warp's MotionNotify (if any) is already queued on return. That
 * costs one round trip per motion on the thread that pumps events, which is cheap on a local server. Returns the number of queued events. Callers read NextRequest before this call to identify the echo. */
static inline unsigned X11RelativeMouseWarpPointer(Display *display, int x, int y) {
    XWarpPointer(display, None, DefaultRootWindow(display), 0, 0, 0, 0, x, y);
    XSync(display, False);
    return (unsigned) XEventsQueued(display, QueuedAlready);
}

/* A MotionNotify while relative mode is active: the model's decision, and the warp back to the virtual cursor with
 * its echo registered. *ok is false when the echo could not be recorded (allocation failure); relative mode must then
 * be released, or the echo would be taken for input. */
static inline X11RelativeMouseMotion X11RelativeMouseMotionEvent(Display *display, X11RelativeMouse *mouse,
                                                                 const XMotionEvent *event, bool warpsHonoured,
                                                                 bool *ok) {
    X11RelativeMouseMotion motion =
            X11RelativeMouseHandleMotion(mouse, event->x_root, event->y_root, warpsHonoured, event->serial);
    *ok = true;
    if (motion.rewarp) {
        unsigned long serial = NextRequest(display);
        unsigned queued = X11RelativeMouseWarpPointer(display, motion.warpX, motion.warpY);
        *ok = X11RelativeMouseExpectEcho(mouse, motion.warpX, motion.warpY, queued, serial);
    }
    return motion;
}

/* CGWarpMouseCursorPosition while relative: the virtual cursor moves without a delta. The pointer goes where the
 * model says (inside the grab window, and parked away from its edges where warps are honoured). Returns false
 * when the echo could not be recorded. */
static inline bool X11RelativeMouseApplicationWarp(Display *display, X11RelativeMouse *mouse, double x, double y,
                                                   bool warpsHonoured) {
    int targetX, targetY;
    X11RelativeMousePointerTarget(mouse, x, y, warpsHonoured, &targetX, &targetY);
    unsigned long serial = NextRequest(display);
    unsigned queued = X11RelativeMouseWarpPointer(display, targetX, targetY);
    return X11RelativeMouseWarp(mouse, x, y, queued, serial, warpsHonoured);
}

#endif
