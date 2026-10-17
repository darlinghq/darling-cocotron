// Host test for AppKit/X11.backend/X11InputShape.h: a window with an empty input region is transparent to the
// pointer, and the default region makes it clickable again. The server decides which window is under the pointer,
// so the test asks it. Use tests/x11-input-shape.sh, which runs it on its own Xvfb.
// Build: cc x11-input-shape.c -lX11 -lXext
#include "../AppKit/X11.backend/X11InputShape.h"
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

/* The top-level window the server finds under the pointer at (x, y). */
static Window windowUnder(Display *display, int x, int y) {
    Window root = DefaultRootWindow(display), reportedRoot, child = None;
    int rootX, rootY, windowX, windowY;
    unsigned int mask;
    XWarpPointer(display, None, root, 0, 0, 0, 0, x, y);
    XSync(display, False);
    XQueryPointer(display, root, &reportedRoot, &child, &rootX, &rootY, &windowX, &windowY, &mask);
    return child;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-input-shape.sh\n");
        return 2;
    }
    int major = 0, minor = 0;
    CHECK(XShapeQueryVersion(display, &major, &minor) && X11ShapeVersionHasInput(major, minor),
          "the server's SHAPE %d.%d has input regions", major, minor);
    CHECK(!X11ShapeVersionHasInput(1, 0) && X11ShapeVersionHasInput(1, 1) && X11ShapeVersionHasInput(1, 2) &&
                  X11ShapeVersionHasInput(2, 0) && !X11ShapeVersionHasInput(0, 9),
          "input regions need SHAPE 1.1 or later");
    Window root = DefaultRootWindow(display);
    Window below = XCreateSimpleWindow(display, root, 0, 0, 400, 400, 0, 0, 0);
    Window overlay = XCreateSimpleWindow(display, root, 100, 100, 100, 100, 0, 0, 0);
    XMapWindow(display, below);
    XMapWindow(display, overlay);
    XSync(display, False);

    CHECK(windowUnder(display, 150, 150) == overlay, "an ordinary overlay takes the pointer");

    CHECK(X11WindowSetIgnoresMouseEvents(display, overlay, true), "SHAPE is available");
    XSync(display, False);
    CHECK(windowUnder(display, 151, 151) == below, "a click-through overlay lets the pointer reach the window below");
    CHECK(windowUnder(display, 101, 101) == below, "also near its corner");

    /* Only the input region is emptied: the window is still drawn, its bounding region is whole. */
    int rectangleCount = 0, ordering;
    XRectangle *rectangles = XShapeGetRectangles(display, overlay, ShapeBounding, &rectangleCount, &ordering);
    CHECK(rectangleCount == 1 && rectangles && rectangles[0].width == 100 && rectangles[0].height == 100,
          "the overlay stays visible (%d bounding rectangles)", rectangleCount);
    if (rectangles)
        XFree(rectangles);

    X11WindowSetIgnoresMouseEvents(display, overlay, true);
    XSync(display, False);
    CHECK(windowUnder(display, 152, 152) == below, "asking again changes nothing");

    X11WindowSetIgnoresMouseEvents(display, overlay, false);
    XSync(display, False);
    CHECK(windowUnder(display, 153, 153) == overlay, "restoring the default region makes it clickable again");
    CHECK(windowUnder(display, 300, 300) == below, "points outside the overlay still go to the window below");

    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
