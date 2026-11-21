// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Host helper for tests/appkit-x11-occlusion-requests.sh: a window of its own client that the window manager
// would report as the focused one (_NET_ACTIVE_WINDOW on the root window, set here so that no window manager is
// needed), then, for the given number of seconds, a stream of what a busy window manager sends about it: a
// synthetic ConfigureNotify that repeats the window's geometry, and a rewrite of _NET_CLIENT_LIST_STACKING.
// usage: x11-active-window <seconds>
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    double seconds = argc > 1 ? atof(argv[1]) : 6;
    Display *dpy = XOpenDisplay(NULL);
    if (dpy == NULL) {
        fprintf(stderr, "cannot open the display\n");
        return 1;
    }
    Window root = DefaultRootWindow(dpy);
    int x = 500, y = 400;
    unsigned int w = 300, h = 200;
    Window win = XCreateSimpleWindow(dpy, root, x, y, w, h, 0, 0, 0);
    XStoreName(dpy, win, "x11-active-window");
    XMapWindow(dpy, win);
    Atom active = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
    Atom stacking = XInternAtom(dpy, "_NET_CLIENT_LIST_STACKING", False);
    unsigned long id = win;
    XChangeProperty(dpy, root, active, XA_WINDOW, 32, PropModeReplace, (unsigned char *) &id, 1);
    XChangeProperty(dpy, root, stacking, XA_WINDOW, 32, PropModeReplace, (unsigned char *) &id, 1);
    XSync(dpy, False);
    usleep(1000000);

    int rounds = (int) (seconds * 100);
    for (int i = 0; i < rounds; i++) {
        XEvent e;
        memset(&e, 0, sizeof e);
        e.xconfigure.type = ConfigureNotify;
        e.xconfigure.display = dpy;
        e.xconfigure.event = win;
        e.xconfigure.window = win;
        e.xconfigure.x = x;
        e.xconfigure.y = y;
        e.xconfigure.width = (int) w;
        e.xconfigure.height = (int) h;
        XSendEvent(dpy, win, False, StructureNotifyMask, &e);
        XChangeProperty(dpy, root, stacking, XA_WINDOW, 32, PropModeReplace, (unsigned char *) &id, 1);
        XFlush(dpy);
        usleep(10000);
    }
    XDeleteProperty(dpy, root, active);
    XDeleteProperty(dpy, root, stacking);
    XDestroyWindow(dpy, win);
    XSync(dpy, False);
    XCloseDisplay(dpy);
    return 0;
}
