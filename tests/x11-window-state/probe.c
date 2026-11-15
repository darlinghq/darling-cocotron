/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Host-side helper for the x11-window-state tests: waits up to ten seconds for
// the client window whose WM_NAME is argv[1], then prints how the X server
// sees it:
//   mapped=<0|1> motif=<none|flags:<hex> decorations:<hex>>
// "motif" is the _MOTIF_WM_HINTS property the AppKit backend uses to ask the
// window manager for no frame. Build: cc probe.c -lX11
#include <X11/Xatom.h>
#include <X11/Xlib.h>
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
        snprintf(motif, sizeof motif, "flags:%lx decorations:%lx", (unsigned long) words[0],
                 (unsigned long) words[2]);
    }
    if (data)
        XFree(data);
    printf("mapped=%d motif=%s\n", attributes.map_state != IsUnmapped, motif);
    return 0;
}
