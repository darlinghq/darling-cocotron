// Host test for X11OcclusionStopWatching() in AppKit/X11.backend/X11Occlusion.h: a window of this process that
// carries the id of the window being watched keeps its event selection. Needs an X server; use
// tests/x11-occlusion-watch.sh, which runs it on its own Xvfb. Build: cc x11-occlusion-watch.c -lX11 -lXrandr
#include "../AppKit/X11.backend/X11Occlusion.h"
#include <stdio.h>

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

static long selectedEvents(Display *display, Window window) {
    XWindowAttributes attributes;
    XGetWindowAttributes(display, window, &attributes);
    return attributes.your_event_mask;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-occlusion-watch.sh\n");
        return 2;
    }
    const long appMask = KeyPressMask | KeyReleaseMask | ButtonPressMask | ExposureMask | StructureNotifyMask;
    int screen = DefaultScreen(display);
    Window ours = XCreateSimpleWindow(display, RootWindow(display, screen), 0, 0, 100, 100, 0, 0, 0);
    XSelectInput(display, ours, appMask);
    XSync(display, False);
    CHECK(selectedEvents(display, ours) == appMask, "the window starts with the application's selection");

    /* The watched id turned out to be one of this process's windows. */
    X11OcclusionStopWatching(display, ours, true);
    XSync(display, False);
    CHECK(selectedEvents(display, ours) == appMask, "a window of ours keeps its selection when it is no longer watched");

    /* A window that is not ours: the watch's own selection is cleared. */
    XSelectInput(display, ours, StructureNotifyMask | PropertyChangeMask);
    X11OcclusionStopWatching(display, ours, false);
    XSync(display, False);
    CHECK(selectedEvents(display, ours) == NoEventMask, "a foreign window's watch selection is cleared");

    /* Nothing watched. */
    XSelectInput(display, ours, appMask);
    X11OcclusionStopWatching(display, None, false);
    XSync(display, False);
    CHECK(selectedEvents(display, ours) == appMask, "no watched window leaves everything alone");

    XDestroyWindow(display, ours);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
