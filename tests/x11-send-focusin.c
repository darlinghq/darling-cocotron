// Host-side helper for x11-focusin-ordered-out.m: waits until the window
// named "focus-probe" exists and is unmapped, then sends it a FocusIn with
// detail NotifyPointer, as the X server does when focus reverts to
// PointerRoot. Build: cc x11-send-focusin.c -lX11
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

int main(void) {
    Display *d = XOpenDisplay(NULL);
    if (!d)
        return 2;
    int seenMapped = 0;
    for (int i = 0; i < 600; i++) {
        Window w = find(d, DefaultRootWindow(d), "focus-probe");
        XWindowAttributes attributes;
        if (w != None && XGetWindowAttributes(d, w, &attributes)) {
            if (attributes.map_state == IsViewable)
                seenMapped = 1;
            else if (seenMapped) {
                XEvent event = {0};
                event.xfocus.type = FocusIn;
                event.xfocus.display = d;
                event.xfocus.window = w;
                event.xfocus.mode = NotifyNormal;
                event.xfocus.detail = NotifyPointer;
                XSendEvent(d, w, False, FocusChangeMask, &event);
                XFlush(d);
                printf("sent FocusIn to 0x%lx\n", w);
                return 0;
            }
        }
        usleep(100000);
    }
    printf("probe window not seen unmapped\n");
    return 1;
}
