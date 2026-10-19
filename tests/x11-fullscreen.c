// Host test for AppKit/X11.backend/X11Fullscreen.h: the decision table, the monitor test against real RandR
// geometry, and the EWMH fullscreen request as a window manager receives it. Needs an X server; use
// tests/x11-fullscreen.sh, which runs it on its own Xvfb. Build: cc x11-fullscreen.c -lX11 -lXrandr
#include "../AppKit/X11.backend/X11Fullscreen.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int failures, checks;

#define CHECK(condition, ...)                                                                               \
    do {                                                                                                    \
        checks++;                                                                                           \
        if (!(condition)) {                                                                                 \
            failures++;                                                                                     \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                     \
            printf(__VA_ARGS__);                                                                            \
            printf("\n");                                                                                   \
        }                                                                                                   \
    } while (0)

static void decisionTable(void) {
    /* overrideRedirect, styleFullScreen, titled, coversMonitor */
    CHECK(X11FullscreenWanted(false, true, true, false), "application asked for fullscreen");
    CHECK(X11FullscreenWanted(false, true, false, false), "application asked, untitled");
    CHECK(X11FullscreenWanted(false, false, false, true), "managed borderless window on a monitor");
    CHECK(!X11FullscreenWanted(false, false, false, false), "borderless window not on a monitor");
    CHECK(!X11FullscreenWanted(false, false, true, true), "a maximized titled window is not fullscreen");
    CHECK(!X11FullscreenWanted(true, false, false, true), "unmanaged windows are left alone");
    CHECK(!X11FullscreenWanted(true, true, false, true), "unmanaged windows are left alone, even if asked");
}

static void setCrtc(Display *display, int x, int y, unsigned width, unsigned height) {
    Window root = DefaultRootWindow(display);
    XRRScreenResources *resources = XRRGetScreenResources(display, root);
    XRRModeInfo info;
    memset(&info, 0, sizeof info);
    char name[48];
    static int serial; /* RandR mode names are unique per server */
    snprintf(name, sizeof name, "%ux%ux-%d", width, height, serial++);
    info.width = width;
    info.height = height;
    info.dotClock = (unsigned long) (width + 160) * (height + 45) * 60;
    info.hTotal = width + 160;
    info.vTotal = height + 45;
    info.hSyncStart = width + 16;
    info.hSyncEnd = width + 112;
    info.vSyncStart = height + 10;
    info.vSyncEnd = height + 12;
    info.name = name;
    info.nameLength = (unsigned) strlen(name);
    RRMode mode = XRRCreateMode(display, root, &info);
    XRRAddOutputMode(display, resources->outputs[0], mode);
    Status status = XRRSetCrtcConfig(display, resources, resources->crtcs[0], CurrentTime, x, y, mode,
                                     RR_Rotate_0, resources->outputs, 1);
    XSync(display, False);
    CHECK(status == RRSetConfigSuccess, "XRRSetCrtcConfig %d,%d %ux%u failed: %d", x, y, width, height, status);
    XRRFreeScreenResources(resources);
}

static void monitorTest(Display *display) {
    int screen = DefaultScreen(display);
    unsigned width = (unsigned) DisplayWidth(display, screen), height = (unsigned) DisplayHeight(display, screen);

    X11FullscreenRect whole = {0, 0, width, height};
    CHECK(X11FullscreenRectIsMonitor(display, whole), "the only monitor covers the root");
    X11FullscreenRect workArea = {0, 0, width, height - 28};
    CHECK(!X11FullscreenRectIsMonitor(display, workArea), "a rectangle that leaves room for a panel is not a monitor");
    X11FullscreenRect shifted = {1, 0, width, height};
    CHECK(!X11FullscreenRectIsMonitor(display, shifted), "an offset rectangle is not a monitor");
    X11FullscreenRect empty = {0, 0, 0, 0};
    CHECK(!X11FullscreenRectIsMonitor(display, empty), "an empty rectangle is not a monitor");

    /* The CRTC, not the root, is the reference: shrink and move it inside the root. */
    setCrtc(display, 100, 50, 640, 480);
    X11FullscreenRect crtc = {100, 50, 640, 480};
    CHECK(X11FullscreenRectIsMonitor(display, crtc), "rectangle equal to the moved CRTC");
    CHECK(!X11FullscreenRectIsMonitor(display, whole), "the root is no longer a monitor");
    X11FullscreenRect nearly = {100, 50, 640, 479};
    CHECK(!X11FullscreenRectIsMonitor(display, nearly), "one pixel short is not a monitor");
}

static bool nextStateMessage(Display *wm, long *action, long *property) {
    while (XPending(wm) > 0) {
        XEvent event;
        XNextEvent(wm, &event);
        if (event.type == ClientMessage && event.xclient.message_type == XInternAtom(wm, "_NET_WM_STATE", False)) {
            *action = event.xclient.data.l[0];
            *property = event.xclient.data.l[1];
            return true;
        }
    }
    return false;
}

static void requestTest(Display *client) {
    /* This process also plays the window manager, on its own connection. */
    Display *wm = XOpenDisplay(NULL);
    CHECK(wm != NULL, "second connection");
    if (!wm)
        return;
    XSelectInput(wm, DefaultRootWindow(wm), SubstructureRedirectMask);
    XSync(wm, False);

    Window window = XCreateSimpleWindow(client, DefaultRootWindow(client), 0, 0, 100, 100, 0, 0, 0);
    Atom fullscreen = XInternAtom(client, "_NET_WM_STATE_FULLSCREEN", False);
    long action = -1, property = 0;

    X11FullscreenRequest(client, window, true);
    XSync(client, False);
    CHECK(nextStateMessage(wm, &action, &property), "the window manager got a _NET_WM_STATE message");
    CHECK(action == 1, "entering fullscreen is _NET_WM_STATE_ADD (1), got %ld", action);
    CHECK(property == (long) fullscreen, "the message names _NET_WM_STATE_FULLSCREEN");

    X11FullscreenRequest(client, window, false);
    XSync(client, False);
    action = -1;
    CHECK(nextStateMessage(wm, &action, &property), "the window manager got a second message");
    CHECK(action == 0, "leaving fullscreen is _NET_WM_STATE_REMOVE (0), not TOGGLE (2); got %ld", action);

    XCloseDisplay(wm);
}

/* The window manager owns _NET_WM_STATE once a window is mapped: a window must follow it, not its own last request. */
static bool waitForStateNotify(Display *client, Window window) {
    for (int attempt = 0; attempt < 50; attempt++) {
        while (XPending(client) > 0) {
            XEvent event;
            XNextEvent(client, &event);
            if (event.type == PropertyNotify && event.xproperty.window == window &&
                event.xproperty.atom == XInternAtom(client, "_NET_WM_STATE", False))
                return true;
        }
        usleep(10000);
    }
    return false;
}

static void stateTest(Display *client) {
    Display *wm = XOpenDisplay(NULL);
    CHECK(wm != NULL, "second connection");
    if (!wm)
        return;
    Window window = XCreateSimpleWindow(client, DefaultRootWindow(client), 0, 0, 100, 100, 0, 0, 0);
    XSelectInput(client, window, PropertyChangeMask);
    Atom stateAtom = XInternAtom(client, "_NET_WM_STATE", False);
    Atom fullscreen = XInternAtom(client, "_NET_WM_STATE_FULLSCREEN", False);
    Atom maximized = XInternAtom(client, "_NET_WM_STATE_MAXIMIZED_VERT", False);

    CHECK(!X11FullscreenIsSet(client, window), "a new window has no state");
    X11FullscreenRequest(client, window, true);
    XSync(client, False);
    CHECK(!X11FullscreenIsSet(client, window), "a request is not the state: only the window manager sets it");

    /* The window manager enters fullscreen (and keeps another state). */
    Atom both[] = {maximized, fullscreen};
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 32, PropModeReplace, (unsigned char *) both, 2);
    XSync(wm, False);
    CHECK(waitForStateNotify(client, window), "PropertyNotify arrives when the manager enters fullscreen");
    CHECK(X11FullscreenIsSet(client, window), "state read back: fullscreen is set");

    /* The manager leaves fullscreen on its own (a keybinding): the window must see it. */
    Atom only[] = {maximized};
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 32, PropModeReplace, (unsigned char *) only, 1);
    XSync(wm, False);
    CHECK(waitForStateNotify(client, window), "PropertyNotify arrives when the manager leaves fullscreen");
    CHECK(!X11FullscreenIsSet(client, window), "state read back: fullscreen is no longer set");

    /* Withdrawing the window: the manager removes the property. */
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 32, PropModeReplace, (unsigned char *) both, 2);
    XSync(wm, False);
    waitForStateNotify(client, window);
    XDeleteProperty(wm, window, stateAtom);
    XSync(wm, False);
    CHECK(waitForStateNotify(client, window), "PropertyNotify arrives when the property is removed");
    CHECK(!X11FullscreenIsSet(client, window), "a withdrawn window is not fullscreen");
    XCloseDisplay(wm);
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-fullscreen.sh\n");
        return 2;
    }
    decisionTable();
    requestTest(display);
    stateTest(display);
    monitorTest(display);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
