// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Host helper for tests/appkit-window-occlusion-x11.sh: maps an opaque fullscreen window (the EWMH fullscreen
// state, as another client's game or video player would) on $DISPLAY, then exits after the given seconds.
// Build: cc x11-cover-window.c -lX11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "no X display\n");
        return 2;
    }
    int seconds = argc > 1 ? atoi(argv[1]) : 5;
    int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, DisplayWidth(display, screen),
                                        DisplayHeight(display, screen), 0, 0, BlackPixel(display, screen));
    XStoreName(display, window, "occlusion-cover");
    Atom state = XInternAtom(display, "_NET_WM_STATE", False);
    Atom fullscreen = XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
    XChangeProperty(display, window, state, XA_ATOM, 32, PropModeReplace, (unsigned char *) &fullscreen, 1);
    XMapRaised(display, window);
    XFlush(display);
    sleep(seconds);
    XDestroyWindow(display, window);
    XCloseDisplay(display);
    return 0;
}
