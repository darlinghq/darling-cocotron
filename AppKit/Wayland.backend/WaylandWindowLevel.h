// xdg_toplevel requests for window levels (see DarlingWindowLevelPolicy.h): plain C, so
// tests/wayland-window-level.c runs this very code against a compositor.
#ifndef WAYLAND_WINDOW_LEVEL_H
#define WAYLAND_WINDOW_LEVEL_H

#include "WaylandLibrary.h"
#include "WaylandProtocol.h"
#include "../DarlingWindowLevelPolicy.h"

// xdg_toplevel.set_parent relates a window to another toplevel: the compositor keeps the child
// above the parent and shows it with it. NULL makes the window a toplevel without a parent.
static inline void WaylandToplevelSetParent(struct wl_proxy *toplevel, struct wl_proxy *parent) {
    union wl_argument args[1] = {{.o = (struct wl_object *) parent}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_SET_PARENT, NULL, 0, args);
}

#endif
