// Fullscreen policy and xdg_toplevel requests for the Wayland backend (see WaylandScale.h:
// plain C, so tests/wayland-fullscreen.c runs this very code against a compositor).
#ifndef WAYLAND_FULLSCREEN_H
#define WAYLAND_FULLSCREEN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// Whether a toplevel should be fullscreen. NSWindowStyleMaskFullScreen asks for
// it outright. A borderless, untitled window that can become key and is as
// large as one output is how games and media players do borderless fullscreen
// on macOS; the compositor cannot tell, so it must be asked. Only the size is
// compared: xdg-shell gives clients no position, so a window's origin says
// nothing about the output it is on.
typedef struct {
    bool fullScreenStyle, titled, canBecomeKey, popupOrMenu;
    int32_t width, height; // logical size of the window content
} WaylandFullscreenWindow;

// Index of the first output whose logical size equals the window's, or -1.
static inline int WaylandFullscreenOutputIndex(const WaylandFullscreenWindow *window,
                                               const int32_t (*sizes)[2], size_t count)
{
    for (size_t i = 0; window->width > 0 && window->height > 0 && i < count; i++)
        if (sizes[i][0] == window->width && sizes[i][1] == window->height)
            return (int) i;
    return -1;
}

static inline bool WaylandFullscreenWanted(const WaylandFullscreenWindow *window,
                                           const int32_t (*sizes)[2], size_t count)
{
    if (window->fullScreenStyle)
        return true;
    if (window->titled || !window->canBecomeKey || window->popupOrMenu)
        return false;
    return WaylandFullscreenOutputIndex(window, sizes, count) >= 0;
}

// xdg_toplevel.set_fullscreen takes the wl_output to cover, or NULL to let the
// compositor choose (normally the output the window is on).
static inline void WaylandToplevelSetFullscreen(struct wl_proxy *toplevel,
                                                struct wl_proxy *output)
{
    union wl_argument args[1] = {{.o = (struct wl_object *) output}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_SET_FULLSCREEN, NULL, 0, args);
}

static inline void WaylandToplevelUnsetFullscreen(struct wl_proxy *toplevel) {
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(toplevel, WP_TOPLEVEL_UNSET_FULLSCREEN, NULL, 0, args);
}

static inline bool WaylandStatesContain(const struct wl_array *states, uint32_t state) {
    const uint32_t *entry;
    wl_array_for_each (entry, states)
        if (*entry == state)
            return true;
    return false;
}

// What the window size becomes at the end of a configure sequence. The
// compositor sizes a fullscreen window itself and, after unset_fullscreen,
// may send 0x0 ("choose your own size") instead of the old size, so the size
// from before fullscreen is kept to restore. Sizes are the window content.
typedef struct {
    bool active;
    int32_t savedWidth, savedHeight;
} WaylandFullscreenTracker;

static inline void WaylandFullscreenConfigure(WaylandFullscreenTracker *tracker,
                                              bool fullscreen,
                                              int32_t currentWidth, int32_t currentHeight,
                                              int32_t configuredWidth, int32_t configuredHeight,
                                              int32_t *width, int32_t *height)
{
    bool configured = configuredWidth > 0 && configuredHeight > 0;
    *width = configured ? configuredWidth : 0;
    *height = configured ? configuredHeight : 0;
    if (fullscreen && !tracker->active) {
        tracker->active = true;
        tracker->savedWidth = currentWidth;
        tracker->savedHeight = currentHeight;
    } else if (!fullscreen && tracker->active) {
        tracker->active = false;
        if (!configured) {
            *width = tracker->savedWidth;
            *height = tracker->savedHeight;
        }
    }
}

#endif
