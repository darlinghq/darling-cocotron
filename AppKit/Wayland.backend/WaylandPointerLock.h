// Pointer lock and relative motion for the Wayland backend (plain C, like
// WaylandScale.h, so tests/wayland-pointer-lock.c runs this code against a
// compositor).
//
// CGAssociateMouseAndMouseCursorPosition(false) freezes the cursor and delivers
// only deltas. On Wayland that is zwp_pointer_constraints_v1.lock_pointer plus
// zwp_relative_pointer_v1: while the lock is active the compositor sends no
// wl_pointer.motion, and relative_motion carries the deltas.
#ifndef WAYLAND_POINTER_LOCK_H
#define WAYLAND_POINTER_LOCK_H

#include <stdbool.h>
#include <stdint.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// A lock that lives until it is destroyed: it activates whenever the surface has
// pointer focus (a oneshot lock would be spent by the first focus change, e.g.
// Alt-Tab). The compositor may refuse to activate it at all; nothing is
// delivered then and the pointer behaves as before.
static inline struct wl_proxy *WaylandLockPointer(struct wl_proxy *constraints,
                                                  struct wl_proxy *surface,
                                                  struct wl_proxy *pointer)
{
    union wl_argument args[5] = {{.o = NULL},
                                 {.o = (struct wl_object *) surface},
                                 {.o = (struct wl_object *) pointer},
                                 {.o = NULL},
                                 {.u = WP_POINTER_CONSTRAINTS_LIFETIME_PERSISTENT}};
    return WaylandMarshal(constraints, WP_POINTER_CONSTRAINTS_LOCK_POINTER,
                          &zwp_locked_pointer_v1_interface, 0, args);
}

static inline struct wl_proxy *WaylandGetRelativePointer(struct wl_proxy *manager,
                                                         struct wl_proxy *pointer)
{
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) pointer}};
    return WaylandMarshal(manager, WP_RELATIVE_POINTER_MANAGER_GET_RELATIVE_POINTER,
                          &zwp_relative_pointer_v1_interface, 0, args);
}

// Unlocks. The hint is where the compositor should put the pointer, in
// surface-local coordinates, and it is double buffered state of the surface:
// it takes effect with a commit, so the commit comes before the destroy.
static inline void WaylandUnlockPointer(struct wl_proxy *locked, struct wl_proxy *relative,
                                        struct wl_proxy *surface, double hintX, double hintY)
{
    union wl_argument hint[2] = {{.f = wl_fixed_from_double(hintX)},
                                 {.f = wl_fixed_from_double(hintY)}};
    WaylandMarshal(locked, WP_LOCKED_POINTER_SET_CURSOR_POSITION_HINT, NULL, 0, hint);
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(surface, WP_SURFACE_COMMIT, NULL, 0, none);
    WaylandMarshal(locked, WP_LOCKED_POINTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
    WaylandMarshal(relative, WP_RELATIVE_POINTER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, none);
}

// Where a warp of the cursor puts it. The position is in the screen coordinates
// of the backend (the window frame's origin plus window coordinates, y up) and
// is clamped to the window content. `window` is the clamped position in window
// coordinates: the value every other writer of the window's last known cursor
// position stores (y up, origin at the content's bottom left). `surface` is the
// same point as wl_pointer.motion would report it: y down, origin at the surface's
// top left, so offset by the client-side decoration.
typedef struct {
    double windowX, windowY;
    double surfaceX, surfaceY;
} WaylandWarp;

static inline WaylandWarp WaylandWarpTarget(double positionX, double positionY,
                                            double frameX, double frameY,
                                            double frameWidth, double frameHeight,
                                            double offsetX, double offsetY)
{
    WaylandWarp warp;
    warp.windowX = positionX - frameX;
    warp.windowY = positionY - frameY;
    if (warp.windowX < 0) warp.windowX = 0;
    if (warp.windowX > frameWidth) warp.windowX = frameWidth;
    if (warp.windowY < 0) warp.windowY = 0;
    if (warp.windowY > frameHeight) warp.windowY = frameHeight;
    warp.surfaceX = warp.windowX + offsetX;
    warp.surfaceY = frameHeight - warp.windowY + offsetY;
    return warp;
}

// The delta of a zwp_relative_pointer_v1.relative_motion event, in the logical
// coordinates of wl_pointer.motion and with the pointer acceleration applied, as
// the deltas of an unlocked pointer have it. y grows downward.
static inline bool WaylandRelativeMotionDelta(uint32_t opcode, const union wl_argument *args,
                                              double *dx, double *dy)
{
    if (opcode != WP_RELATIVE_POINTER_EV_RELATIVE_MOTION)
        return false;
    *dx = wl_fixed_to_double(args[2].f);
    *dy = wl_fixed_to_double(args[3].f);
    return true;
}

#endif
