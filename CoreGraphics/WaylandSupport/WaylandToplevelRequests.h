// xdg_toplevel requests that relate a window to another or change its state: plain C, so that the window system layer
// (CGSWindowWayland.m) and the tests that run these very requests against a compositor share them.
// The decisions of when to make them (window levels, fullscreen) are the UI layer's.
#ifndef WAYLAND_TOPLEVEL_REQUESTS_H
#define WAYLAND_TOPLEVEL_REQUESTS_H

#include <stdint.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// xdg_toplevel.set_parent relates a window to another toplevel: the compositor keeps the child above the parent and
// shows it with it. NULL makes the window a toplevel without a parent.
static inline void WaylandToplevelSetParent(struct wl_proxy *toplevel, struct wl_proxy *parent) {
    union wl_argument args[1] = {{.o = (struct wl_object *) parent}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_SET_PARENT, NULL, 0, args);
}

// xdg_toplevel.set_fullscreen takes the wl_output to cover, or NULL to let the compositor choose (normally the output the
// window is on).
static inline void WaylandToplevelSetFullscreen(struct wl_proxy *toplevel, struct wl_proxy *output) {
    union wl_argument args[1] = {{.o = (struct wl_object *) output}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_SET_FULLSCREEN, NULL, 0, args);
}

static inline void WaylandToplevelUnsetFullscreen(struct wl_proxy *toplevel) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_UNSET_FULLSCREEN, NULL, 0, args);
}

// xdg_toplevel.set_minimized: xdg-shell has no request that undoes it and no event that says a toplevel is minimized.
static inline void WaylandToplevelSetMinimized(struct wl_proxy *toplevel) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_SET_MINIMIZED, NULL, 0, args);
}

#endif
