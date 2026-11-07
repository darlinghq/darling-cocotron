/* EWMH fullscreen decisions and requests for the X11 backend.
 *
 * A borderless window that exactly covers a monitor is the macOS idiom for borderless fullscreen. Under a window
 * manager such a window has to ask for _NET_WM_STATE_FULLSCREEN, or it is stacked below panels and docks. The
 * monitor test compares against the full CRTC rectangle, never a work area, so a window that merely leaves room
 * for a panel stays an ordinary window.
 *
 * Only Xlib and RandR, no Objective-C, so tests/x11-fullscreen.c can drive it against Xvfb. */
#ifndef X11_FULLSCREEN_H
#define X11_FULLSCREEN_H

#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <stdbool.h>

typedef struct {
    int x, y; /* root coordinates, device pixels */
    unsigned int width, height;
} X11FullscreenRect;

/* An application window asks for fullscreen when the application did (the fullscreen style bit), or when it is
 * a managed, untitled window that covers a monitor. Titled windows are never promoted: a maximized titled
 * window is not fullscreen. Unmanaged (override-redirect) windows are not the window manager's to place. */
static inline bool X11FullscreenWanted(bool overrideRedirect, bool styleFullScreen, bool titled, bool coversMonitor) {
    if (overrideRedirect)
        return false;
    if (styleFullScreen)
        return true;
    if (titled)
        return false;
    return coversMonitor;
}

/* Whether a window that is already fullscreen has to leave fullscreen before setFrame: moves it. It does when it
 * should no longer be fullscreen, and also when it moves to another place (another monitor): a window manager
 * ignores configure requests for a fullscreen window, so a move between two monitors that are each exactly
 * covered would otherwise leave the window on the first one. The caller asks for fullscreen again after the move. */
static inline bool X11FullscreenLeaveBeforeMove(bool wanted, bool requested, bool moved) {
    return requested && (!wanted || moved);
}

/* Whether rect is exactly the geometry of an active monitor (a RandR CRTC with a mode). Without RandR the
 * root window is the only monitor. */
static inline bool X11FullscreenRectIsMonitor(Display *display, X11FullscreenRect rect) {
    Window root = DefaultRootWindow(display);
    int eventBase, errorBase;
    if (!XRRQueryExtension(display, &eventBase, &errorBase)) {
        int screen = DefaultScreen(display);
        return rect.x == 0 && rect.y == 0 && rect.width == (unsigned int) DisplayWidth(display, screen) &&
               rect.height == (unsigned int) DisplayHeight(display, screen);
    }
    XRRScreenResources *resources = XRRGetScreenResourcesCurrent(display, root);
    if (resources == NULL)
        return false;
    bool covers = false;
    for (int i = 0; i < resources->ncrtc && !covers; i++) {
        XRRCrtcInfo *crtc = XRRGetCrtcInfo(display, resources, resources->crtcs[i]);
        if (crtc == NULL)
            continue;
        covers = crtc->mode != None && crtc->width > 0 && crtc->height > 0 && crtc->x == rect.x &&
                 crtc->y == rect.y && crtc->width == rect.width && crtc->height == rect.height;
        XRRFreeCrtcInfo(crtc);
    }
    XRRFreeScreenResources(resources);
    return covers;
}

/* Asks the window manager to enter or leave fullscreen for a mapped window. EWMH section "_NET_WM_STATE":
 * data.l[0] is 0 to remove, 1 to add, 2 to toggle. Toggling would re-enter fullscreen when the manager already
 * left it, so leaving is an explicit remove. */
static inline void X11FullscreenRequest(Display *display, Window window, bool fullscreen) {
    XClientMessageEvent event = {0};
    event.type = ClientMessage;
    event.window = window;
    event.message_type = XInternAtom(display, "_NET_WM_STATE", False);
    event.format = 32;
    event.data.l[0] = fullscreen ? 1 : 0;
    event.data.l[1] = (long) XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
    event.data.l[3] = 1; /* source indication: normal application */
    XSendEvent(display, DefaultRootWindow(display), False, SubstructureNotifyMask | SubstructureRedirectMask,
               (XEvent *) &event);
}

/* Whether _NET_WM_STATE currently lists _NET_WM_STATE_FULLSCREEN for the window. Once a window is mapped the window
 * manager owns that property (EWMH): it adds and removes the state on its own (a keybinding, a panel button) and
 * clears it when the window is withdrawn, so a window that only remembers its own last request goes stale. */
static inline bool X11FullscreenIsSet(Display *display, Window window) {
    Atom state = XInternAtom(display, "_NET_WM_STATE", False);
    Atom fullscreen = XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
    Atom type = None;
    int format = 0;
    unsigned long count = 0, after = 0;
    unsigned char *data = NULL;
    if (XGetWindowProperty(display, window, state, 0, 64, False, XA_ATOM, &type, &format, &count, &after, &data) !=
        Success)
        return false;
    bool set = false;
    if (type == XA_ATOM && format == 32)
        for (unsigned long i = 0; i < count; i++)
            if (((long *) data)[i] == (long) fullscreen)
                set = true;
    if (data)
        XFree(data);
    return set;
}

#endif
