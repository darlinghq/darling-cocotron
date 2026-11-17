// Copyright (C) 2026 Lubos Dolezel
//
// Host test for AppKit/X11.backend/X11RoundedShape.h: a window whose corners are cut has a bounding region
// without the corner pixels and with all others, and a radius of 0 restores the whole rectangle. Use
// tests/x11-rounded-shape.sh, which runs it on its own Xvfb.
// Build: cc x11-rounded-shape.c -lX11 -lXext -lm
#include "../AppKit/X11.backend/X11RoundedShape.h"
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

/* Whether the pixel is part of the window's bounding region. */
static bool inRegion(Display *display, Window window, int x, int y) {
    int count = 0, ordering;
    XRectangle *rectangles = XShapeGetRectangles(display, window, ShapeBounding, &count, &ordering);
    bool inside = false;
    for (int i = 0; i < count; i++)
        if (x >= rectangles[i].x && x < rectangles[i].x + rectangles[i].width && y >= rectangles[i].y &&
            y < rectangles[i].y + rectangles[i].height)
            inside = true;
    if (rectangles)
        XFree(rectangles);
    return inside;
}

int main(void) {
    CHECK(X11RoundedCornerInset(5, 0) > X11RoundedCornerInset(5, 1) && X11RoundedCornerInset(5, 1) >= X11RoundedCornerInset(5, 4),
          "the outer rows are cut more than the inner ones");
    CHECK(X11RoundedCornerInset(5, 0) == 3 && X11RoundedCornerInset(5, 4) == 1, "radius 5: %d, %d", X11RoundedCornerInset(5, 0), X11RoundedCornerInset(5, 4));
    CHECK(X11RoundedCornerInset(0, 0) == 0 && X11RoundedCornerInset(5, 5) == 0 && X11RoundedCornerInset(5, -1) == 0,
          "no inset without a corner row");

    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-rounded-shape.sh\n");
        return 2;
    }
    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 120, 80, 0, 0, 0);
    XMapWindow(display, window);
    XSync(display, False);

    CHECK(inRegion(display, window, 0, 0), "an unshaped window includes its corner");

    CHECK(X11WindowSetRoundedCorners(display, window, 120, 80, 8), "SHAPE is available");
    XSync(display, False);
    CHECK(!inRegion(display, window, 0, 0), "top left corner pixel is cut");
    CHECK(!inRegion(display, window, 119, 0), "top right corner pixel is cut");
    CHECK(!inRegion(display, window, 0, 79), "bottom left corner pixel is cut");
    CHECK(!inRegion(display, window, 119, 79), "bottom right corner pixel is cut");
    CHECK(inRegion(display, window, 60, 0), "the middle of the top edge stays");
    CHECK(inRegion(display, window, 0, 40), "the middle of the left edge stays");
    CHECK(inRegion(display, window, 119, 40), "the middle of the right edge stays");
    CHECK(inRegion(display, window, 60, 79), "the middle of the bottom edge stays");
    CHECK(inRegion(display, window, 8, 8) && inRegion(display, window, 111, 71), "the inner corners stay");

    /* A window too small for two corners is left whole, and a radius of 0 removes the shape. */
    CHECK(X11WindowSetRoundedCorners(display, window, 10, 10, 8), "a small window is accepted");
    XSync(display, False);
    CHECK(inRegion(display, window, 0, 0), "a window smaller than two radii keeps its corners");
    X11WindowSetRoundedCorners(display, window, 120, 80, 8);
    X11WindowSetRoundedCorners(display, window, 120, 80, 0);
    XSync(display, False);
    CHECK(inRegion(display, window, 0, 0) && inRegion(display, window, 119, 79), "radius 0 restores the rectangle");

    printf("%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures ? 1 : 0;
}
