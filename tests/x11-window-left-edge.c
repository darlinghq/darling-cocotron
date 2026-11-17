// Copyright (C) 2026 Lubos Dolezel
//
// Host tool of tests/x11-window-left-edge.sh: reads the pixels of the window titled "Left edge test" from the
// screen and checks, at many heights between the rounded corners, that the outline Darling draws is one pixel
// wide on the left and the right: the outermost pixel is the dark outline and the pixel beside it is not.
// Build: cc x11-window-left-edge.c -lX11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <string.h>

static int luma(XImage *image, int x, int y) {
    unsigned long p = XGetPixel(image, x, y);
    return (int) (((p >> 16) & 0xff) + ((p >> 8) & 0xff) + (p & 0xff)) / 3;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "no X display\n");
        return 2;
    }
    Window root = DefaultRootWindow(display), target = 0;
    Atom list = XInternAtom(display, "_NET_CLIENT_LIST", False), name = XInternAtom(display, "_NET_WM_NAME", False);
    Atom utf8 = XInternAtom(display, "UTF8_STRING", False), type;
    int format;
    unsigned long count, after;
    unsigned char *data = NULL;
    if (XGetWindowProperty(display, root, list, 0, 4096, False, XA_WINDOW, &type, &format, &count, &after, &data) !=
                Success || data == NULL) {
        fprintf(stderr, "no client list\n");
        return 2;
    }
    for (unsigned long i = 0; i < count; i++) {
        unsigned char *title = NULL;
        unsigned long length;
        if (XGetWindowProperty(display, ((Window *) data)[i], name, 0, 256, False, utf8, &type, &format, &length,
                               &after, &title) == Success && title != NULL) {
            if (strcmp((char *) title, "Left edge test") == 0)
                target = ((Window *) data)[i];
            XFree(title);
        }
    }
    if (!target) {
        fprintf(stderr, "window not found\n");
        return 2;
    }
    XWindowAttributes attributes;
    XGetWindowAttributes(display, target, &attributes);
    int x, y;
    Window child;
    XTranslateCoordinates(display, target, root, 0, 0, &x, &y, &child);
    XImage *image = XGetImage(display, root, x, y, attributes.width, attributes.height, AllPlanes, ZPixmap);
    if (!image) {
        fprintf(stderr, "cannot read the window\n");
        return 2;
    }
    int fail = 0, rows = 0, w = attributes.width, h = attributes.height;
    // Between the corner arcs (5 points) and a margin below them.
    for (int row = 12; row < h - 12; row += 3) {
        int edges[2][2] = {{0, 1}, {w - 1, w - 2}};
        for (int side = 0; side < 2; side++) {
            int outer = luma(image, edges[side][0], row), inner = luma(image, edges[side][1], row);
            rows++;
            if (outer > 140 || inner < 200) {
                printf("FAIL: %s edge at row %d: outermost pixel %d, next pixel %d\n", side ? "right" : "left", row,
                       outer, inner);
                fail = 1;
            }
        }
    }
    printf("%d edge samples, %s\n", rows, fail ? "FAIL" : "PASS");
    return fail;
}
