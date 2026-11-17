// Copyright (C) 2026 Lubos Dolezel
//
// Host tool of tests/x11-chromeless-window-shape.sh: for every managed window whose title starts with the
// given prefixes, prints "<title>: corners cut" or "<title>: corners whole" according to whether the top left
// pixel is outside the window's bounding region.
// Build: cc x11-chromeless-window-shape.c -lX11 -lXext
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "no X display\n");
        return 2;
    }
    Atom list = XInternAtom(display, "_NET_CLIENT_LIST", False), name = XInternAtom(display, "_NET_WM_NAME", False);
    Atom utf8 = XInternAtom(display, "UTF8_STRING", False), type;
    int format;
    unsigned long count, after;
    unsigned char *data = NULL;
    if (XGetWindowProperty(display, DefaultRootWindow(display), list, 0, 4096, False, XA_WINDOW, &type, &format,
                           &count, &after, &data) != Success || data == NULL)
        return 1;
    Window *windows = (Window *) data;
    for (unsigned long i = 0; i < count; i++) {
        unsigned char *title = NULL;
        unsigned long length;
        if (XGetWindowProperty(display, windows[i], name, 0, 256, False, utf8, &type, &format, &length, &after,
                               &title) != Success || title == NULL)
            continue;
        int rectangleCount = 0, ordering;
        XRectangle *rectangles = XShapeGetRectangles(display, windows[i], ShapeBounding, &rectangleCount, &ordering);
        int inside = 0;
        for (int r = 0; r < rectangleCount; r++)
            if (rectangles[r].x <= 0 && rectangles[r].y <= 0 && rectangles[r].x + rectangles[r].width > 0 &&
                rectangles[r].y + rectangles[r].height > 0)
                inside = 1;
        printf("%s: corners %s\n", title, inside ? "whole" : "cut");
        if (rectangles)
            XFree(rectangles);
        XFree(title);
    }
    XFree(data);
    return 0;
}
