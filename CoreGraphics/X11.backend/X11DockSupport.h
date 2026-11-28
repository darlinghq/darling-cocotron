/* Whether the window manager places dock windows, for the X11 backend.
 *
 * The application's menu bar is a borderless window of type _NET_WM_WINDOW_TYPE_DOCK that asks for the top of the
 * screen and reserves it with _NET_WM_STRUT_PARTIAL, so it only ends up there under a window manager that handles
 * docks. A manager that does not (Hyprland's X11 support, for one) treats it as an ordinary floating window and
 * centres it over the windows of the application. EWMH has the manager list the hints it handles in
 * _NET_SUPPORTED on the root window, so a manager that lists neither the dock type nor a strut is not
 * trusted with the bar, and the menu is drawn inside the windows instead.
 *
 * A screen with no _NET_SUPPORTED at all has no EWMH manager. Windows then stay where they ask to be, so the
 * bar is where it should be and counts as placed.
 *
 * Only Xlib, no Objective-C, so tests/x11-dock-support.c can drive it against Xvfb. */
#ifndef X11_DOCK_SUPPORT_H
#define X11_DOCK_SUPPORT_H

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdbool.h>

/* The decision on a list of supported atoms: the manager handles docks when it lists the dock window type or
 * a strut that reserves the screen edge (the bar publishes both the partial and the older plain one). */
static inline bool X11SupportedAtomsPlaceDocks(const Atom *supported, unsigned long count, Atom dockType,
                                               Atom strutPartial, Atom strut) {
    for (unsigned long i = 0; i < count; i++)
        if (supported[i] == dockType || supported[i] == strutPartial || supported[i] == strut)
            return true;
    return false;
}

/* Whether dock windows are placed where they ask: no EWMH window manager, or one that lists the dock hints. */
static inline bool X11WindowManagerPlacesDocks(Display *display) {
    Atom supported = XInternAtom(display, "_NET_SUPPORTED", False);
    Atom type = None;
    int format = 0;
    unsigned long count = 0, after = 0;
    unsigned char *data = NULL;
    if (XGetWindowProperty(display, DefaultRootWindow(display), supported, 0, 4096, False, XA_ATOM, &type, &format,
                           &count, &after, &data) != Success)
        return true;
    bool places = true;
    if (type == XA_ATOM && format == 32)
        places = X11SupportedAtomsPlaceDocks((const Atom *) data, count,
                                             XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False),
                                             XInternAtom(display, "_NET_WM_STRUT_PARTIAL", False),
                                             XInternAtom(display, "_NET_WM_STRUT", False));
    if (data)
        XFree(data);
    return places;
}

#endif
