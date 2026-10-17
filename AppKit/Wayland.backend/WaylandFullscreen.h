// Fullscreen policy and xdg_toplevel requests for the Wayland backend (see WaylandScale.h:
// plain C, so tests/wayland-fullscreen.c runs this very code against a compositor).
#ifndef WAYLAND_FULLSCREEN_H
#define WAYLAND_FULLSCREEN_H

#include <math.h>
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

// Every size comparison and every saved size goes through this one rounding:
// logical output sizes can be fractional (2560 / 1.5), compositor sizes are not.
static inline int32_t WaylandFullscreenRound(double value) {
    return (int32_t) lround(value);
}

// An output as the decision sees it: its logical size and whether the window's
// surface has entered it (wl_surface.enter).
typedef struct {
    int32_t width, height;
    bool entered;
} WaylandFullscreenOutput;

// Decides whether the window is fullscreen. *target is the index of the output to
// name in set_fullscreen, or -1 to let the compositor choose.
//
// A window that has entered some outputs may only be fullscreened onto one of
// them: matching the size of an output it is not on does not make it fullscreen
// material. A window that has entered none (before its first commit) is matched
// against all outputs, and an output is named only when exactly one has its size.
static inline bool WaylandFullscreenDecide(const WaylandFullscreenWindow *window,
                                           const WaylandFullscreenOutput *outputs, size_t count,
                                           int *target)
{
    *target = -1;
    if (window->fullScreenStyle)
        return true;
    if (window->titled || !window->canBecomeKey || window->popupOrMenu ||
        window->width <= 0 || window->height <= 0)
        return false;
    bool onOutput = false;
    for (size_t i = 0; i < count; i++)
        onOutput = onOutput || outputs[i].entered;
    size_t matches = 0;
    int first = -1;
    for (size_t i = 0; i < count; i++) {
        if (onOutput && !outputs[i].entered)
            continue;
        if (outputs[i].width != window->width || outputs[i].height != window->height)
            continue;
        if (matches++ == 0)
            first = (int) i;
    }
    if (matches == 0)
        return false;
    if (onOutput || matches == 1)
        *target = first;
    return true;
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
// compositor sizes a fullscreen window itself. After unset_fullscreen it sends
// either 0x0 ("choose your own size") or the size it remembered from before
// fullscreen (sway). The size to go back to is the one from before fullscreen,
// unless the application chose another with setFrame: while fullscreen: then
// the application's size wins over whatever the compositor remembered. A size
// the compositor sends for a window the application did not resize wins over
// the saved one. Sizes are the window content.
typedef struct {
    bool active;
    bool applicationSized;
    int32_t savedWidth, savedHeight;
} WaylandFullscreenTracker;

// The application resized the window. While fullscreen, that is the size to
// return to on leaving; otherwise there is nothing to remember.
static inline void WaylandFullscreenApplicationResized(WaylandFullscreenTracker *tracker,
                                                       int32_t width, int32_t height)
{
    if (!tracker->active)
        return;
    tracker->applicationSized = true;
    tracker->savedWidth = width;
    tracker->savedHeight = height;
}

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
        if (!configured || tracker->applicationSized) {
            *width = tracker->savedWidth;
            *height = tracker->savedHeight;
        }
        tracker->applicationSized = false;
    }
}

#endif
