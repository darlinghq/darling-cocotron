/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Host test (no display server, no Darling): the X11 and Wayland backends decide
// "is this window fullscreen" through the one rule in DarlingFullscreenPolicy.h, so for
// the same window they agree. Build from the repository root:
//   cc -ICoreGraphics/WaylandSupport -o fullscreen-policy tests/fullscreen-policy.c
//      $(pkg-config --cflags --libs wayland-client x11 xrandr)  (one command line)
#include "../AppKit/DarlingFullscreenPolicy.h"
#include "../AppKit/Wayland.backend/WaylandFullscreen.h"
#include "../AppKit/X11.backend/X11Fullscreen.h"
#include <stdio.h>

// The Wayland header only calls this from helpers the test does not use.
struct wl_proxy *WaylandMarshal(struct wl_proxy *proxy, uint32_t opcode,
                                const struct wl_interface *interface, uint32_t flags,
                                union wl_argument *args)
{
    return NULL;
}

static int failures;
#define CHECK(x) do { if (!(x)) { failures++; fprintf(stderr, "line %d: %s\n", __LINE__, #x); } } while (0)

int main(void) {
    // The shared rule: style bit, else untitled and covering a monitor.
    CHECK(DarlingFullscreenWanted(true, true, false));
    CHECK(DarlingFullscreenWanted(true, false, false));
    CHECK(!DarlingFullscreenWanted(false, true, true));
    CHECK(!DarlingFullscreenWanted(false, false, false));
    CHECK(DarlingFullscreenWanted(false, false, true));

    // Both backends agree with it for every combination. The Wayland window is 1920x1080
    // and covers the one output exactly when `covers` is set (otherwise the output is 1px wider).
    for (int style = 0; style < 2; style++)
        for (int titled = 0; titled < 2; titled++)
            for (int covers = 0; covers < 2; covers++) {
                bool expected = DarlingFullscreenWanted(style, titled, covers);
                CHECK(X11FullscreenWanted(false, style, titled, covers) == expected);
                CHECK(!X11FullscreenWanted(true, style, titled, covers)); // override-redirect: never

                WaylandFullscreenWindow window = {style, titled, true, false, 1920, 1080};
                WaylandFullscreenOutput output = {covers ? 1920 : 1921, 1080, false};
                int target;
                CHECK(WaylandFullscreenDecide(&window, &output, 1, &target) == expected);
            }

    // A window that cannot become key or is a popup is not promoted by size, but the style bit still wins.
    WaylandFullscreenWindow popup = {false, false, true, true, 1920, 1080};
    WaylandFullscreenOutput output = {1920, 1080, false};
    int target;
    CHECK(!WaylandFullscreenDecide(&popup, &output, 1, &target) && target == -1);
    popup.fullScreenStyle = true;
    CHECK(WaylandFullscreenDecide(&popup, &output, 1, &target) && target == -1);

    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
