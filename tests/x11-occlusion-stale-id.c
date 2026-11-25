// Host test for the scenario behind X11OcclusionStopWatching() in AppKit/X11.backend/X11Occlusion.h: a window of
// this process is created with the id of a window the occlusion watch had remembered. Needs an X server; use
// tests/x11-occlusion-stale-id.sh, which runs it on its own Xvfb. Build: cc x11-occlusion-stale-id.c -lX11 -lXrandr
//
// A client that exits leaves its _NET_ACTIVE_WINDOW on the root window and the server hands the resource id range
// it used to the next client that connects, so the application's first window can get the id the stale property
// names. This test plays that with real connections: client A creates a window and exits with the property set;
// the application (B) reads the property at startup, watches that id, creates its window (the same id), and later
// moves the watch to the window of another client (C). B's window must keep receiving its events.
#include "../AppKit/X11.backend/X11Occlusion.h"
#include <stdio.h>
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

static int badWindowErrors;

static int countBadWindow(Display *display, XErrorEvent *error) {
    (void) display;
    if (error->error_code == BadWindow)
        badWindowErrors++;
    return 0;
}

static void setActiveWindow(Display *display, Window window) {
    unsigned long id = window;
    XChangeProperty(display, DefaultRootWindow(display), XInternAtom(display, "_NET_ACTIVE_WINDOW", False),
                    XA_WINDOW, 32, PropModeReplace, (unsigned char *) &id, 1);
    XSync(display, False);
}

/* The step of -[X11Display updateOcclusion] that moves the watch to the newly focused foreign window; `own` lists
 * the windows of this process, which is what -[X11Display isOwnWindowID:] answers from. Keep it in step with
 * X11Display.m. */
static void moveWatch(Display *display, Window *watched, Window active, const Window *own, int ownCount) {
    bool watchedIsOurs = false;
    for (int i = 0; i < ownCount; i++)
        watchedIsOurs = watchedIsOurs || own[i] == *watched;
    if (active != *watched) {
        X11OcclusionStopWatching(display, *watched, watchedIsOurs);
        *watched = active;
        if (active != None)
            XSelectInput(display, active, StructureNotifyMask | PropertyChangeMask);
    }
}

int main(void) {
    const long appMask = KeyPressMask | KeyReleaseMask | ButtonPressMask | ExposureMask | StructureNotifyMask;
    Display *other = XOpenDisplay(NULL); /* client C: the window manager's choice of focused window */
    if (!other) {
        printf("no X display: run through tests/x11-occlusion-stale-id.sh\n");
        return 2;
    }
    Window staleId = None;
    Display *app = NULL;
    Window ours = None;
    XSetErrorHandler(countBadWindow);

    /* Client A leaves; the connection of the application that follows is given its id range. The server frees the
     * range some moments after the disconnect, so a connection made too early gets a different one. */
    for (int attempt = 0; attempt < 50; attempt++) {
        if (app) {
            XCloseDisplay(app);
            app = NULL;
        }
        Display *a = XOpenDisplay(NULL);
        staleId = XCreateSimpleWindow(a, DefaultRootWindow(a), 0, 0, 50, 50, 0, 0, 0);
        setActiveWindow(a, staleId);
        XCloseDisplay(a);
        usleep(100000);
        app = XOpenDisplay(NULL);
        badWindowErrors = 0;
        /* The application starts: the active window is the stale one, which no longer exists. */
        Window active = X11OcclusionActiveWindow(app);
        CHECK(active == staleId, "the stale _NET_ACTIVE_WINDOW survives its client");
        XSelectInput(app, active, StructureNotifyMask | PropertyChangeMask);
        XSync(app, False);
        if (attempt == 0)
            CHECK(badWindowErrors == 1, "the stale id names no window (BadWindow %d)", badWindowErrors);
        ours = XCreateSimpleWindow(app, DefaultRootWindow(app), 0, 0, 100, 100, 0, 0, 0);
        if (ours == staleId)
            break;
    }
    CHECK(ours == staleId, "the application's first window got the id the stale property names (%lx, %lx)", ours,
          staleId);
    if (ours != staleId) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    Window watched = staleId;
    XSelectInput(app, ours, appMask);
    XSync(app, False);

    /* The window manager now names the window of another client. */
    Window foreign = XCreateSimpleWindow(other, DefaultRootWindow(other), 200, 200, 100, 100, 0, 0, 0);
    XMapWindow(other, foreign);
    setActiveWindow(other, foreign);
    Window active = X11OcclusionActiveWindow(app);
    CHECK(active == foreign, "the focused window changed to the foreign window");
    moveWatch(app, &watched, active, &ours, 1);
    XSync(app, False);

    XWindowAttributes attributes;
    XGetWindowAttributes(app, ours, &attributes);
    CHECK(attributes.your_event_mask == appMask, "the window of ours keeps the application's selection (%lx)",
          (unsigned long) attributes.your_event_mask);

    /* What the selection is for: another client sends the window a key press, as the server would on a key. */
    XEvent key = {0};
    key.xkey.type = KeyPress;
    key.xkey.window = ours;
    key.xkey.root = DefaultRootWindow(other);
    key.xkey.keycode = 38;
    XSendEvent(other, ours, False, KeyPressMask, &key);
    XSync(other, False);
    XSync(app, False);
    XEvent received;
    CHECK(XCheckTypedWindowEvent(app, ours, KeyPress, &received), "the window of ours still receives key events");

    CHECK(watched == foreign, "the watch moved to the foreign window");
    XCloseDisplay(app);
    XCloseDisplay(other);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
