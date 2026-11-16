/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Host-side helper for the x11-window-state tests: waits up to ten seconds for
// the client window whose WM_NAME is argv[1], then prints how the X server
// sees it:
//   mapped=<0|1> motif=<none|flags:<hex> functions:<hex> decorations:<hex>> shape=<n> frameshape=<n> compositor=<0|1>
// shape is the number of rectangles of the window's bounding region (1 for an unshaped window, 0 when it is
// empty, so nothing of the window is drawn), frameshape the same for the top-level window of the window
// manager's frame around it, and compositor whether a compositing manager owns the screen.
// "motif" is the _MOTIF_WM_HINTS property the AppKit backend uses to ask the
// window manager for no frame. Build: cc probe.c -lX11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/shape.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static Window find(Display *d, Window w, const char *name) {
    char *title = NULL;
    if (XFetchName(d, w, &title) && title) {
        int match = strcmp(title, name) == 0;
        XFree(title);
        if (match)
            return w;
    }
    Window root, parent, *children = NULL;
    unsigned int count = 0;
    Window found = None;
    if (XQueryTree(d, w, &root, &parent, &children, &count)) {
        for (unsigned int i = 0; i < count && found == None; i++)
            found = find(d, children[i], name);
        if (children)
            XFree(children);
    }
    return found;
}

int main(int argc, char **argv) {
    if (argc != 2)
        return 2;
    Display *d = XOpenDisplay(NULL);
    if (!d)
        return 2;
    Window w = None;
    for (int i = 0; i < 100 && w == None; i++) {
        w = find(d, DefaultRootWindow(d), argv[1]);
        if (w == None)
            usleep(100000);
    }
    if (w == None) {
        printf("absent\n");
        return 1;
    }
    XWindowAttributes attributes;
    XGetWindowAttributes(d, w, &attributes);

    Atom hints = XInternAtom(d, "_MOTIF_WM_HINTS", True);
    Atom type;
    int format;
    unsigned long count = 0, after;
    unsigned char *data = NULL;
    char motif[64] = "none";
    if (hints != None &&
        XGetWindowProperty(d, w, hints, 0, 5, False, AnyPropertyType, &type, &format, &count, &after,
                           &data) == Success &&
        data != NULL && count >= 3) {
        long *words = (long *) data;
        snprintf(motif, sizeof motif, "flags:%lx functions:%lx decorations:%lx",
                 (unsigned long) words[0], (unsigned long) words[1], (unsigned long) words[2]);
    }
    if (data)
        XFree(data);
    int rectangles = -1, frameRectangles = -1, ordering;
    XRectangle *list = XShapeGetRectangles(d, w, ShapeBounding, &rectangles, &ordering);
    if (list)
        XFree(list);
    // the ancestor that is a child of the root window
    Window top = w, root, parent, *children = NULL;
    unsigned int childCount = 0;
    while (XQueryTree(d, top, &root, &parent, &children, &childCount)) {
        if (children)
            XFree(children);
        if (parent == root || parent == None)
            break;
        top = parent;
    }
    list = XShapeGetRectangles(d, top, ShapeBounding, &frameRectangles, &ordering);
    if (list)
        XFree(list);
    char selection[32];
    snprintf(selection, sizeof selection, "_NET_WM_CM_S%d", DefaultScreen(d));
    int compositor = XGetSelectionOwner(d, XInternAtom(d, selection, False)) != None;
    printf("mapped=%d motif=%s shape=%d frameshape=%d compositor=%d\n", attributes.map_state != IsUnmapped, motif,
           rectangles, frameRectangles, compositor);
    return 0;
}
