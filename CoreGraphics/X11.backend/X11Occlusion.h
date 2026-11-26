/* Copyright (C) 2026 Lubos Dolezel
 *
 * Licensed under the MIT license, the same as the rest of this project.
 *
 * Whether another client's window hides one of ours, from EWMH root properties.
 *
 * X11 has no occlusion state. A window is treated as not seen when the focused window (_NET_ACTIVE_WINDOW)
 * belongs to another client, is opaque and fullscreen, is stacked above the window in _NET_CLIENT_LIST_STACKING
 * and contains its rectangle. A window the window manager marks _NET_WM_STATE_HIDDEN is not seen either, which
 * -[X11Window isMiniaturized] reports. Without a stacking list nothing is judged covered.
 *
 * Only Xlib and the fullscreen helpers, no Objective-C, so a test can drive it against Xvfb. */
#ifndef X11_OCCLUSION_H
#define X11_OCCLUSION_H

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdbool.h>

#include "X11Fullscreen.h"

/* The pure decision. Rectangles are in root coordinates; a stack index is the window's position in the stacking
 * list (bottom to top) or -1 when it is not listed. */
static inline bool X11OcclusionCovers(X11FullscreenRect own, X11FullscreenRect cover, bool coverFullscreen,
                                      bool coverOpaque, long ownStackIndex, long coverStackIndex) {
    if (!coverFullscreen || !coverOpaque)
        return false;
    if (own.width == 0 || own.height == 0 || cover.width == 0 || cover.height == 0)
        return false;
    if (ownStackIndex < 0 || coverStackIndex <= ownStackIndex)
        return false;
    return cover.x <= own.x && cover.y <= own.y && (long) cover.x + cover.width >= (long) own.x + own.width &&
           (long) cover.y + cover.height >= (long) own.y + own.height;
}

/* The position of a window in a stacking list, or -1. */
static inline long X11OcclusionStackIndex(const unsigned long *stack, unsigned long count, Window window) {
    for (unsigned long i = 0; i < count; i++)
        if (stack[i] == window)
            return (long) i;
    return -1;
}

/* _NET_ACTIVE_WINDOW of the root window, or None. */
static inline Window X11OcclusionActiveWindow(Display *display) {
    Atom type = None;
    int format = 0;
    unsigned long count = 0, after = 0;
    unsigned char *data = NULL;
    Window active = None;
    if (XGetWindowProperty(display, DefaultRootWindow(display), XInternAtom(display, "_NET_ACTIVE_WINDOW", False), 0,
                           1, False, XA_WINDOW, &type, &format, &count, &after, &data) == Success &&
        type == XA_WINDOW && format == 32 && count == 1 && data)
        active = (Window) * (unsigned long *) data;
    if (data)
        XFree(data);
    return active;
}

/* Stops watching a foreign window. XSelectInput() replaces this client's whole selection on the window, so
 * clearing it is only right for a window that is not ours. The id of a watched window can outlive the window
 * (the window manager leaves a stale _NET_ACTIVE_WINDOW behind when a client exits) and a later window of this
 * process can be given the same id; clearing the selection on that one would cut it off from every key,
 * button and expose event. */
static inline void X11OcclusionStopWatching(Display *display, Window watched, bool isOurs) {
    if (watched != None && !isOurs)
        XSelectInput(display, watched, NoEventMask);
}

/* The windows of _NET_CLIENT_LIST_STACKING, bottom to top, in a buffer to XFree, or NULL. */
static inline unsigned long *X11OcclusionStackingList(Display *display, unsigned long *count) {
    Atom type = None;
    int format = 0;
    unsigned long after = 0;
    unsigned char *data = NULL;
    *count = 0;
    if (XGetWindowProperty(display, DefaultRootWindow(display),
                           XInternAtom(display, "_NET_CLIENT_LIST_STACKING", False), 0, 4096, False, XA_WINDOW, &type,
                           &format, count, &after, &data) == Success &&
        type == XA_WINDOW && format == 32 && data)
        return (unsigned long *) data;
    if (data)
        XFree(data);
    *count = 0;
    return NULL;
}

/* Whether _NET_WM_WINDOW_OPACITY gives the window less than full opacity. */
static inline bool X11OcclusionWindowIsTranslucent(Display *display, Window window) {
    Atom type = None;
    int format = 0;
    unsigned long count = 0, after = 0;
    unsigned char *data = NULL;
    bool translucent = false;
    if (XGetWindowProperty(display, window, XInternAtom(display, "_NET_WM_WINDOW_OPACITY", False), 0, 1, False,
                           XA_CARDINAL, &type, &format, &count, &after, &data) == Success &&
        type == XA_CARDINAL && format == 32 && count == 1 && data)
        translucent = (*(unsigned long *) data & 0xffffffffUL) != 0xffffffffUL;
    if (data)
        XFree(data);
    return translucent;
}

/* The focused window's geometry in root coordinates, and whether it is a viewable, opaque window that is
 * fullscreen (the EWMH state, or a window that exactly covers a monitor). False for anything else. */
static inline bool X11OcclusionCoverInfo(Display *display, Window window, X11FullscreenRect *rect, bool *fullscreen,
                                         bool *opaque) {
    XWindowAttributes attributes;
    Window child;
    int x, y;
    if (!XGetWindowAttributes(display, window, &attributes) || attributes.map_state != IsViewable ||
        attributes.class != InputOutput ||
        !XTranslateCoordinates(display, window, DefaultRootWindow(display), 0, 0, &x, &y, &child))
        return false;
    rect->x = x;
    rect->y = y;
    rect->width = (unsigned int) attributes.width;
    rect->height = (unsigned int) attributes.height;
    *opaque = attributes.depth != 32 && !X11OcclusionWindowIsTranslucent(display, window);
    *fullscreen = X11FullscreenIsSet(display, window) || X11FullscreenRectIsMonitor(display, *rect);
    return true;
}

#endif
