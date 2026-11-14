/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Host test (no compositor, no Darling) for the pure coordinate helpers of
// WaylandPointerLock.h: the conversion from CoreGraphics' global space, which
// -[NSDisplay warpMouse:] takes, to the backend's screen space, and the clamped warp
// target inside a window.
//   cc -I.. -I../../../CoreGraphics/WaylandSupport -o wayland-screen-point \
//      wayland-screen-point.c $(pkg-config --cflags wayland-client)
#include <stdio.h>
#include "../WaylandPointerLock.h"

// The header only calls this from functions the test does not use.
struct wl_proxy *WaylandMarshal(struct wl_proxy *proxy, uint32_t opcode,
                                const struct wl_interface *interface, uint32_t flags,
                                union wl_argument *args)
{
    return NULL;
}

static int failures;
#define CHECK(x) do { if (!(x)) { failures++; fprintf(stderr, "line %d: %s\n", __LINE__, #x); } } while (0)

int main(void) {
    double x, y;
    // The top-left corner of a 1080-point-high primary screen is the top of its space.
    WaylandScreenPointFromCG(0, 0, 1080, &x, &y);
    CHECK(x == 0 && y == 1080);
    // The bottom-left corner.
    WaylandScreenPointFromCG(0, 1080, 1080, &x, &y);
    CHECK(x == 0 && y == 0);
    // A point on another screen to the right keeps its x; one above the primary has a
    // negative CoreGraphics y.
    WaylandScreenPointFromCG(2000, -200, 1080, &x, &y);
    CHECK(x == 2000 && y == 1280);

    // A window whose frame is at (100, 200), 400 x 300, no decoration offset: the
    // CoreGraphics point for its content's centre warps to the window's centre.
    WaylandScreenPointFromCG(300, 1080 - 350, 1080, &x, &y);
    WaylandWarp warp = WaylandWarpTarget(x, y, 100, 200, 400, 300, 0, 0);
    CHECK(warp.windowX == 200 && warp.windowY == 150);
    CHECK(warp.surfaceX == 200 && warp.surfaceY == 150);

    // Outside the window the target is clamped to its content.
    WaylandScreenPointFromCG(5000, -5000, 1080, &x, &y);
    warp = WaylandWarpTarget(x, y, 100, 200, 400, 300, 0, 0);
    CHECK(warp.windowX == 400 && warp.windowY == 300);
    WaylandScreenPointFromCG(-5000, 9000, 1080, &x, &y);
    warp = WaylandWarpTarget(x, y, 100, 200, 400, 300, 0, 0);
    CHECK(warp.windowX == 0 && warp.windowY == 0);

    // The surface point is y down and offset by the client-side decoration.
    warp = WaylandWarpTarget(100 + 10, 200 + 20, 100, 200, 400, 300, 3, 30);
    CHECK(warp.surfaceX == 13 && warp.surfaceY == 300 - 20 + 30);

    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
