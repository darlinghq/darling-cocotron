/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
/* Whether an EWMH window manager is running on an X server. Only Xlib, so a test can include it. */
#ifndef X11_WINDOW_MANAGER_H
#define X11_WINDOW_MANAGER_H

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdbool.h>

static inline Window X11SupportingWMCheckWindow(Display *display, Window window, Atom check) {
    Atom type;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    Window result = None;

    if (XGetWindowProperty(display, window, check, 0, 1, False, XA_WINDOW, &type, &format, &count, &remaining,
                           &data) == Success &&
        data != NULL && type == XA_WINDOW && format == 32 && count == 1)
        result = (Window) * (long *) data;
    if (data != NULL)
        XFree(data);
    return result;
}

/* A window manager that exited can leave the root property behind. Per EWMH the child window it names must carry
 * the same property naming itself; a stale id fails that. */
static inline bool X11WindowManagerIsRunning(Display *display) {
    Atom check = XInternAtom(display, "_NET_SUPPORTING_WM_CHECK", True);
    if (check == None)
        return false;
    Window child = X11SupportingWMCheckWindow(display, DefaultRootWindow(display), check);
    return child != None && X11SupportingWMCheckWindow(display, child, check) == child;
}

#endif
