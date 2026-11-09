// Host test for AppKit/X11.backend/X11Fullscreen.h: the decision table, the monitor test against real RandR
// geometry, and the EWMH fullscreen request as a window manager receives it. Needs an X server; use
// tests/x11-fullscreen.sh, which runs it on its own Xvfb. Build: cc x11-fullscreen.c -lX11 -lXrandr -ldl
#include "../AppKit/X11.backend/X11Fullscreen.h"
#include "../CoreGraphics/X11.backend/X11Monitors.h"
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
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

    /* wanted, requested, moved */
    /* wasStyleFullScreen, styleFullScreen */
    CHECK(X11FullscreenStyleLeft(true, false), "clearing the fullscreen style leaves, though the frame covers a monitor");
    CHECK(!X11FullscreenStyleLeft(false, false), "an unrelated style change decides by the frame");
    CHECK(!X11FullscreenStyleLeft(false, true), "setting the style enters");
    CHECK(!X11FullscreenStyleLeft(true, true), "keeping the style stays");

    CHECK(X11FullscreenLeaveBeforeMove(true, true, true), "a fullscreen window moving to another monitor leaves first");
    CHECK(!X11FullscreenLeaveBeforeMove(true, true, false), "a fullscreen window that stays put sends nothing");
    CHECK(X11FullscreenLeaveBeforeMove(false, true, false), "leaving fullscreen on a frame that covers no monitor");
    CHECK(X11FullscreenLeaveBeforeMove(false, true, true), "leaving and moving");
    CHECK(!X11FullscreenLeaveBeforeMove(true, false, true), "a window that is not fullscreen has nothing to leave");
    CHECK(!X11FullscreenLeaveBeforeMove(false, false, true), "an ordinary window moving sends nothing");
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
    X11FullscreenRect twice = {100, 50, 1280, 480};
    CHECK(!X11FullscreenRectIsMonitor(display, twice), "a rectangle spanning two monitors is not one monitor");
    X11FullscreenRect taller = {100, 50, 640, 481};
    CHECK(!X11FullscreenRectIsMonitor(display, taller), "one pixel too tall is not a monitor");
}

/* Xvfb has a single CRTC and RandR, so a second monitor and a server without RandR cannot be set up on it. The
 * header's calls into RandR are therefore interposed here (this executable's definitions win over libXrandr's):
 * unless a fake is selected they forward to the real library. */
static enum { FakeOff, FakeTwoCrtcs, FakeNoRandR } fake;
static const struct {
    int x, y;
    unsigned width, height;
} fakeCrtcs[] = {{0, 0, 640, 480}, {640, 100, 800, 600}};

Bool XRRQueryExtension(Display *display, int *eventBase, int *errorBase) {
    if (fake == FakeNoRandR)
        return False;
    Bool (*real)(Display *, int *, int *) = (Bool (*)(Display *, int *, int *)) dlsym(RTLD_NEXT, "XRRQueryExtension");
    return real(display, eventBase, errorBase);
}

XRRScreenResources *XRRGetScreenResourcesCurrent(Display *display, Window window) {
    if (fake != FakeTwoCrtcs) {
        XRRScreenResources *(*real)(Display *, Window) =
                (XRRScreenResources * (*) (Display *, Window)) dlsym(RTLD_NEXT, "XRRGetScreenResourcesCurrent");
        return real(display, window);
    }
    /* One block, as libXrandr allocates it: XRRFreeScreenResources frees only the struct. */
    XRRScreenResources *resources = calloc(1, sizeof *resources + 2 * sizeof *resources->crtcs);
    resources->ncrtc = 2;
    resources->crtcs = (RRCrtc *) (resources + 1);
    resources->crtcs[0] = 1;
    resources->crtcs[1] = 2;
    return resources;
}

XRRCrtcInfo *XRRGetCrtcInfo(Display *display, XRRScreenResources *resources, RRCrtc crtc) {
    if (fake != FakeTwoCrtcs) {
        XRRCrtcInfo *(*real)(Display *, XRRScreenResources *, RRCrtc) =
                (XRRCrtcInfo * (*) (Display *, XRRScreenResources *, RRCrtc)) dlsym(RTLD_NEXT, "XRRGetCrtcInfo");
        return real(display, resources, crtc);
    }
    XRRCrtcInfo *info = calloc(1, sizeof *info);
    info->x = fakeCrtcs[crtc - 1].x;
    info->y = fakeCrtcs[crtc - 1].y;
    info->width = fakeCrtcs[crtc - 1].width;
    info->height = fakeCrtcs[crtc - 1].height;
    info->mode = 1;
    return info;
}

static void multiMonitorTest(Display *display) {
    fake = FakeTwoCrtcs;
    X11FullscreenRect first = {0, 0, 640, 480}, second = {640, 100, 800, 600};
    CHECK(X11FullscreenRectIsMonitor(display, first), "the first of two monitors");
    CHECK(X11FullscreenRectIsMonitor(display, second), "the second of two monitors, not only the first CRTC counts");
    X11FullscreenRect secondY = {640, 101, 800, 600}, secondTop = {640, 0, 800, 600};
    CHECK(!X11FullscreenRectIsMonitor(display, secondY), "the second monitor one pixel lower is not a monitor");
    CHECK(!X11FullscreenRectIsMonitor(display, secondTop), "the second monitor's size at y 0 is not a monitor");
    X11FullscreenRect firstY = {0, 1, 640, 480};
    CHECK(!X11FullscreenRectIsMonitor(display, firstY), "the first monitor one pixel lower is not a monitor");
    X11FullscreenRect secondX = {641, 100, 800, 600};
    CHECK(!X11FullscreenRectIsMonitor(display, secondX), "the second monitor one pixel right is not a monitor");
    fake = FakeOff;
}

/* Without RandR the root window is the only monitor. */
static void noRandRTest(Display *display) {
    fake = FakeNoRandR;
    int screen = DefaultScreen(display);
    unsigned width = (unsigned) DisplayWidth(display, screen), height = (unsigned) DisplayHeight(display, screen);
    X11FullscreenRect whole = {0, 0, width, height};
    CHECK(X11FullscreenRectIsMonitor(display, whole), "no RandR: the root is the monitor");
    X11FullscreenRect right = {1, 0, width, height}, lower = {0, 1, width, height};
    CHECK(!X11FullscreenRectIsMonitor(display, right), "no RandR: shifted in x is not the root");
    CHECK(!X11FullscreenRectIsMonitor(display, lower), "no RandR: shifted in y is not the root");
    X11FullscreenRect narrow = {0, 0, width - 1, height}, shorter = {0, 0, width, height - 1};
    CHECK(!X11FullscreenRectIsMonitor(display, narrow), "no RandR: one pixel narrower is not the root");
    CHECK(!X11FullscreenRectIsMonitor(display, shorter), "no RandR: one pixel shorter is not the root");
    fake = FakeOff;
}

static long lastSource;

static bool nextStateMessage(Display *wm, long *action, long *property) {
    while (XPending(wm) > 0) {
        XEvent event;
        XNextEvent(wm, &event);
        if (event.type == ClientMessage && event.xclient.message_type == XInternAtom(wm, "_NET_WM_STATE", False)) {
            *action = event.xclient.data.l[0];
            *property = event.xclient.data.l[1];
            lastSource = event.xclient.data.l[3];
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
    CHECK(lastSource == 1, "the source indication is a normal application (1), got %ld", lastSource);

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

    /* Only a 32-bit atom list is a state: the same bytes in another format are not read as atoms. */
    long wide[] = {(long) fullscreen};
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 32, PropModeReplace, (unsigned char *) wide, 1);
    XSync(wm, False);
    CHECK(X11FullscreenIsSet(client, window), "control: the 32-bit list names fullscreen");
    unsigned char bytes[sizeof wide];
    memcpy(bytes, wide, sizeof wide);
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 8, PropModeReplace, bytes, (int) sizeof bytes);
    XSync(wm, False);
    CHECK(!X11FullscreenIsSet(client, window), "an 8-bit property is not a state");
    unsigned short halves[sizeof wide / 2];
    memcpy(halves, wide, sizeof wide);
    XChangeProperty(wm, window, stateAtom, XA_ATOM, 16, PropModeReplace, (unsigned char *) halves,
                    (int) (sizeof halves / sizeof *halves));
    XSync(wm, False);
    CHECK(!X11FullscreenIsSet(client, window), "a 16-bit property is not a state");
    XCloseDisplay(wm);
}

/* X11Window compares the window's frame with the monitors by converting it from Cocoa's global space (y up from the
 * main monitor's bottom-left, the space NSScreen.frame is in) to root coordinates. That only works when the screens
 * and the window frame share a space; check the whole path against a real CRTC, including a main monitor that is not at
 * the root origin or a corner of it. */
static void conventionTest(Display *display) {
    struct {
        int x, y;
        unsigned width, height;
    } layouts[] = {{0, 0, 640, 360}, {100, 50, 640, 480}, {0, 360, 1280, 360}, {640, 0, 640, 720}};
    for (size_t i = 0; i < sizeof layouts / sizeof *layouts; i++) {
        setCrtc(display, layouts[i].x, layouts[i].y, layouts[i].width, layouts[i].height);
        int count, primary;
        X11Monitor *monitors = X11MonitorsCopy(display, &count, &primary);
        CHECK(monitors != NULL && primary == 0, "layout %zu: one active monitor", i);
        if (!monitors)
            continue;
        X11Frame main = {monitors[0].x, monitors[0].y, monitors[0].width, monitors[0].height};
        free(monitors);
        /* NSScreen.frame of that monitor, then the window frame an application sets from it, then X11Window's
         * conversion to the root rectangle it compares with the CRTC. */
        X11Frame screenFrame = X11FrameFromRoot(main, main);
        X11Frame root = X11FrameToRoot(main, screenFrame);
        X11FullscreenRect rect = {(int) root.x, (int) root.y, (unsigned) root.width, (unsigned) root.height};
        CHECK(X11FullscreenRectIsMonitor(display, rect),
              "layout %zu: [window setFrame:[screen frame]] lands on the CRTC %d,%d %ux%u (got %d,%d %ux%u)", i,
              layouts[i].x, layouts[i].y, layouts[i].width, layouts[i].height, rect.x, rect.y, rect.width, rect.height);
        CHECK(screenFrame.x == 0 && screenFrame.y == 0, "layout %zu: the main screen's frame starts at 0,0", i);
        /* A frame inset by a panel's height is not the monitor, in the same space. */
        X11Frame inset = {screenFrame.x, screenFrame.y, screenFrame.width, screenFrame.height - 28};
        root = X11FrameToRoot(main, inset);
        X11FullscreenRect insetRect = {(int) root.x, (int) root.y, (unsigned) root.width, (unsigned) root.height};
        CHECK(!X11FullscreenRectIsMonitor(display, insetRect), "layout %zu: a work-area frame is not the monitor", i);
    }
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
    multiMonitorTest(display);
    noRandRTest(display);
    conventionTest(display);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
