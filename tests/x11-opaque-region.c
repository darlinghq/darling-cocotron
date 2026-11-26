// Host test for CoreGraphics/X11.backend/X11OpaqueRegion.h: an opaque window on a 32-bit visual gets
// _NET_WM_OPAQUE_REGION covering all of it, a window on the default 24-bit visual gets none, and the property
// is removed when the window stops being opaque. The depth passed to the header is the one the server reports for
// the window, as the backend reads it from the visual it created the window with. Use tests/x11-opaque-region.sh,
// which runs it on its own Xvfb.
// Build: cc x11-opaque-region.c -lX11
#include "../CoreGraphics/X11.backend/X11OpaqueRegion.h"
#include <X11/Xutil.h>
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

/* The rectangles the window carries in _NET_WM_OPAQUE_REGION, as four numbers each; -1 when it has none. */
static int regionValues(Display *display, Window window, long values[4]) {
    Atom type, property = XInternAtom(display, "_NET_WM_OPAQUE_REGION", False);
    int format;
    unsigned long count, after;
    unsigned char *data = NULL;
    if (XGetWindowProperty(display, window, property, 0, 64, False, XA_CARDINAL, &type, &format, &count, &after,
                           &data) != Success || type != XA_CARDINAL || format != 32 || count == 0) {
        if (data)
            XFree(data);
        return -1;
    }
    for (int i = 0; i < 4 && i < (int) count; i++)
        values[i] = ((long *) data)[i];
    XFree(data);
    return (int) count;
}

static int depthOf(Display *display, Window window) {
    XWindowAttributes attributes;
    XGetWindowAttributes(display, window, &attributes);
    return attributes.depth;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-opaque-region.sh\n");
        return 2;
    }
    CHECK(X11OpaqueRegionApplies(32, true) && !X11OpaqueRegionApplies(32, false) && !X11OpaqueRegionApplies(24, true) &&
                  !X11OpaqueRegionApplies(24, false),
          "only an opaque window with an alpha channel gets the hint");

    int screen = DefaultScreen(display);
    Window root = RootWindow(display, screen);
    XSetWindowAttributes attributes = {.border_pixel = 0};

    Window plain = XCreateWindow(display, root, 0, 0, 200, 100, 0, DefaultDepth(display, screen), InputOutput,
                                 DefaultVisual(display, screen), CWBorderPixel, &attributes);
    CHECK(depthOf(display, plain) == 24, "the default visual has depth 24 here, depth %d", depthOf(display, plain));
    long values[4] = {0};
    CHECK(!X11WindowSetOpaqueRegion(display, plain, depthOf(display, plain), true, 200, 100) &&
                  regionValues(display, plain, values) == -1,
          "an opaque 24-bit window has no opaque region");

    XVisualInfo wanted = {.screen = screen, .depth = 32, .class = TrueColor};
    int count = 0;
    XVisualInfo *visuals = XGetVisualInfo(display, VisualScreenMask | VisualDepthMask | VisualClassMask, &wanted, &count);
    if (count == 0) {
        printf("SKIP: the server has no 32-bit TrueColor visual\n");
        printf("RESULT checks=%d failures=%d\n", checks, failures);
        return failures ? 1 : 0;
    }
    attributes.colormap = XCreateColormap(display, root, visuals[0].visual, AllocNone);
    Window alpha = XCreateWindow(display, root, 0, 0, 200, 100, 0, 32, InputOutput, visuals[0].visual,
                                 CWBorderPixel | CWColormap, &attributes);
    XFree(visuals);
    int depth = depthOf(display, alpha);
    CHECK(depth == 32, "the alpha window has depth 32, depth %d", depth);

    CHECK(!X11WindowSetOpaqueRegion(display, alpha, depth, false, 200, 100) && regionValues(display, alpha, values) == -1,
          "a window that is not opaque has no region");
    CHECK(X11WindowSetOpaqueRegion(display, alpha, depth, true, 200, 100) && regionValues(display, alpha, values) == 4 &&
                  values[0] == 0 && values[1] == 0 && values[2] == 200 && values[3] == 100,
          "an opaque alpha window covers all of itself");
    CHECK(X11WindowSetOpaqueRegion(display, alpha, depth, true, 320, 240) && regionValues(display, alpha, values) == 4 &&
                  values[2] == 320 && values[3] == 240,
          "a resize replaces the rectangle");
    CHECK(!X11WindowSetOpaqueRegion(display, alpha, depth, false, 320, 240) && regionValues(display, alpha, values) == -1,
          "ceasing to be opaque removes it");
    CHECK(!X11WindowSetOpaqueRegion(display, alpha, depth, false, 320, 240), "removing it again is harmless");

    printf("RESULT checks=%d failures=%d\n", checks, failures);
    XCloseDisplay(display);
    return failures ? 1 : 0;
}
