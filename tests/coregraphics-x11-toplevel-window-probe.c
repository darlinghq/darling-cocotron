/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// Prints what the X server says about a window: "depth=<n> override=<0|1> map=<state> x=<x> y=<y> w=<w> h=<h>"
// with the position on the root window. Usage: coregraphics-x11-toplevel-window-probe <window id>
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    Display *display = XOpenDisplay(NULL);
    if (display == NULL)
        return 1;
    Window window = (Window) strtoul(argv[1], NULL, 0);
    XWindowAttributes attributes;
    if (!XGetWindowAttributes(display, window, &attributes))
        return 1;
    Window child;
    int x = 0, y = 0;
    XTranslateCoordinates(display, window, DefaultRootWindow(display), 0, 0, &x, &y, &child);
    printf("depth=%d override=%d map=%d x=%d y=%d w=%d h=%d\n", attributes.depth, attributes.override_redirect,
           attributes.map_state, x, y, attributes.width, attributes.height);
    return 0;
}
