// Copyright (C) 2026 Lubos Dolezel
// Host-side XDND source for appkit-x11-xdnd-target: finds the window named
// "xdnd-target" (or the proxy that fronts it under a reparenting window
// manager), runs XdndEnter/Position/Drop with a text/uri-list payload, serves
// the selection request and waits for XdndFinished. Exit 0 when the target
// accepted the drop and reported it finished. Plain Xlib; build with
//   cc -o xdnd-source-driver xdnd-source-driver.c -lX11
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

static Display *dpy;

static Window find_target(Window w, int depth) {
    char *name = NULL;
    if (XFetchName(dpy, w, &name) && name) {
        int match = strcmp(name, "xdnd-target") == 0;
        XFree(name);
        if (match)
            return w;
    }
    Window root, parent, *kids = NULL;
    unsigned int n = 0;
    if (depth > 4 || !XQueryTree(dpy, w, &root, &parent, &kids, &n))
        return None;
    Window found = None;
    for (unsigned int i = 0; i < n && found == None; i++)
        found = find_target(kids[i], depth + 1);
    if (kids)
        XFree(kids);
    return found;
}

static int wait_event(XEvent *ev, int ms) {
    if (XPending(dpy) == 0) {
        fd_set fds; FD_ZERO(&fds); FD_SET(ConnectionNumber(dpy), &fds);
        struct timeval tv = {ms / 1000, (ms % 1000) * 1000};
        if (select(ConnectionNumber(dpy) + 1, &fds, NULL, NULL, &tv) <= 0)
            return 0;
    }
    XNextEvent(dpy, ev);
    return 1;
}

int main(void) {
    dpy = XOpenDisplay(NULL);
    if (!dpy) { puts("FAIL: no display"); return 2; }
    Window root = DefaultRootWindow(dpy);

    Window target = None;
    for (int i = 0; i < 100 && target == None; i++) {
        target = find_target(root, 0);
        if (target == None) { struct timeval tv = {0, 200000}; select(0, 0, 0, 0, &tv); }
    }
    if (target == None) { puts("FAIL: target window not found"); return 1; }

    Atom aware = XInternAtom(dpy, "XdndAware", False);
    Atom proxyAtom = XInternAtom(dpy, "XdndProxy", False);
    Atom enter = XInternAtom(dpy, "XdndEnter", False);
    Atom position = XInternAtom(dpy, "XdndPosition", False);
    Atom status = XInternAtom(dpy, "XdndStatus", False);
    Atom drop = XInternAtom(dpy, "XdndDrop", False);
    Atom finished = XInternAtom(dpy, "XdndFinished", False);
    Atom selection = XInternAtom(dpy, "XdndSelection", False);
    Atom copy = XInternAtom(dpy, "XdndActionCopy", False);
    Atom uriList = XInternAtom(dpy, "text/uri-list", False);

    // The window that has to receive the messages: the XdndProxy of the
    // frame, or the target itself.
    Window recv = target;
    {
        Atom type; int fmt; unsigned long n, after; unsigned char *data = NULL;
        Window p = target, rt, par, *kids; unsigned int nk;
        // Walk up: a reparenting window manager frame carries the proxy.
        while (XQueryTree(dpy, p, &rt, &par, &kids, &nk)) {
            if (kids) XFree(kids);
            if (par == None || par == root) break;
            p = par;
        }
        if (XGetWindowProperty(dpy, p, proxyAtom, 0, 1, False, XA_WINDOW, &type, &fmt, &n,
                               &after, &data) == Success && data && n == 1) {
            recv = *(Window *) data;
            XFree(data);
        }
        data = NULL;
        if (XGetWindowProperty(dpy, recv, aware, 0, 1, False, AnyPropertyType, &type, &fmt,
                               &n, &after, &data) != Success || data == NULL) {
            puts("FAIL: target is not XdndAware");
            return 1;
        }
        XFree(data);
    }

    Window src = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XSetSelectionOwner(dpy, selection, src, CurrentTime);

    XWindowAttributes attr;
    XGetWindowAttributes(dpy, target, &attr);
    Window dummy; int tx, ty;
    XTranslateCoordinates(dpy, target, root, 20, 20, &tx, &ty, &dummy);

    XEvent m; memset(&m, 0, sizeof m);
    m.xclient.type = ClientMessage; m.xclient.display = dpy; m.xclient.format = 32;
    m.xclient.window = recv; m.xclient.message_type = enter;
    m.xclient.data.l[0] = src; m.xclient.data.l[1] = 5L << 24;
    m.xclient.data.l[2] = uriList;
    XSendEvent(dpy, recv, False, NoEventMask, &m);

    memset(&m, 0, sizeof m);
    m.xclient.type = ClientMessage; m.xclient.display = dpy; m.xclient.format = 32;
    m.xclient.window = recv; m.xclient.message_type = position;
    m.xclient.data.l[0] = src; m.xclient.data.l[2] = (tx << 16) | ty;
    m.xclient.data.l[3] = CurrentTime; m.xclient.data.l[4] = copy;
    XSendEvent(dpy, recv, False, NoEventMask, &m);
    XFlush(dpy);

    int accepted = 0;
    XEvent ev;
    for (int i = 0; i < 50 && !accepted; i++) {
        if (!wait_event(&ev, 200)) continue;
        if (ev.type == ClientMessage && ev.xclient.message_type == status)
            accepted = (ev.xclient.data.l[1] & 1) != 0;
    }
    if (!accepted) { puts("FAIL: XdndStatus did not accept the drag"); return 1; }

    memset(&m, 0, sizeof m);
    m.xclient.type = ClientMessage; m.xclient.display = dpy; m.xclient.format = 32;
    m.xclient.window = recv; m.xclient.message_type = drop;
    m.xclient.data.l[0] = src; m.xclient.data.l[2] = CurrentTime;
    XSendEvent(dpy, recv, False, NoEventMask, &m);
    XFlush(dpy);

    const char *uris = "file:///tmp/xdnd%20test%20file.txt\r\n";
    for (int i = 0; i < 100; i++) {
        if (!wait_event(&ev, 200)) continue;
        if (ev.type == SelectionRequest && ev.xselectionrequest.selection == selection) {
            XSelectionRequestEvent *r = &ev.xselectionrequest;
            XSelectionEvent reply; memset(&reply, 0, sizeof reply);
            reply.type = SelectionNotify; reply.requestor = r->requestor;
            reply.selection = r->selection; reply.target = r->target; reply.time = r->time;
            reply.property = None;
            if (r->target == uriList) {
                XChangeProperty(dpy, r->requestor, r->property, uriList, 8, PropModeReplace,
                                (const unsigned char *) uris, strlen(uris));
                reply.property = r->property;
            }
            XSendEvent(dpy, r->requestor, False, NoEventMask, (XEvent *) &reply);
            XFlush(dpy);
        } else if (ev.type == ClientMessage && ev.xclient.message_type == finished) {
            int ok = (ev.xclient.data.l[1] & 1) != 0;
            puts(ok ? "OK" : "FAIL: XdndFinished reports the drop not accepted");
            return ok ? 0 : 1;
        }
    }
    puts("FAIL: no XdndFinished");
    return 1;
}
