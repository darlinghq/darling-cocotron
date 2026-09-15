/* Native Wayland and xkbcommon functions used by the Wayland backend.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#ifndef WAYLAND_LIBRARY_H
#define WAYLAND_LIBRARY_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <wayland-client-core.h>
#include <wayland-cursor.h>
#include <xkbcommon/xkbcommon.h>

// libwayland-client, libwayland-cursor and libxkbcommon are Linux libraries. They are
// loaded with dlopen() when the Wayland backend is selected, so the bundle has no
// link-time dependency on them and costs nothing when X11 is used.
//
// Darwin arm64 passes variadic arguments on the stack and Linux arm64 passes them in
// registers, so no variadic function may be called across that boundary. Every
// function listed here takes a fixed number of arguments. In particular requests go
// through wl_proxy_marshal_array_flags() instead of the variadic
// wl_proxy_marshal_flags() used by wayland-scanner's inline stubs, and events arrive
// through wl_proxy_add_dispatcher() instead of listener structs, which libwayland calls
// through libffi with the Linux convention (events with more than 8 arguments would
// put arguments on the stack, where the two ABIs lay them out differently).
#define WAYLAND_CLIENT_FUNCTIONS(X)                                            \
    X(wl_display_connect)                                                      \
    X(wl_display_disconnect)                                                   \
    X(wl_display_get_fd)                                                       \
    X(wl_display_get_error)                                                    \
    X(wl_display_dispatch_pending)                                             \
    X(wl_display_prepare_read)                                                 \
    X(wl_display_read_events)                                                  \
    X(wl_display_cancel_read)                                                  \
    X(wl_display_flush)                                                        \
    X(wl_display_roundtrip)                                                    \
    X(wl_proxy_marshal_array_flags)                                            \
    X(wl_proxy_add_dispatcher)                                                 \
    X(wl_proxy_get_user_data)                                                  \
    X(wl_proxy_get_version)                                                    \
    X(wl_proxy_destroy)

#define XKBCOMMON_FUNCTIONS(X)                                                 \
    X(xkb_context_new)                                                         \
    X(xkb_context_unref)                                                       \
    X(xkb_keymap_new_from_buffer)                                              \
    X(xkb_keymap_unref)                                                        \
    X(xkb_keymap_key_repeats)                                                  \
    X(xkb_keymap_key_get_syms_by_level)                                        \
    X(xkb_keymap_layout_get_name)                                              \
    X(xkb_state_new)                                                           \
    X(xkb_state_unref)                                                         \
    X(xkb_state_update_mask)                                                   \
    X(xkb_state_key_get_one_sym)                                               \
    X(xkb_state_key_get_utf8)                                                  \
    X(xkb_state_key_get_layout)                                                \
    X(xkb_state_mod_name_is_active)                                            \
    X(xkb_state_serialize_layout)                                              \
    X(xkb_keysym_to_utf32)

#define WAYLAND_CURSOR_FUNCTIONS(X)                                            \
    X(wl_cursor_theme_load)                                                    \
    X(wl_cursor_theme_destroy)                                                 \
    X(wl_cursor_theme_get_cursor)                                              \
    X(wl_cursor_image_get_buffer)

// Each member has the exact type of the prototype in the host headers.
struct WaylandLibrary {
#define WAYLAND_FUNCTION_POINTER(name) __typeof__(name) *name;
    WAYLAND_CLIENT_FUNCTIONS(WAYLAND_FUNCTION_POINTER)
    XKBCOMMON_FUNCTIONS(WAYLAND_FUNCTION_POINTER)
    WAYLAND_CURSOR_FUNCTIONS(WAYLAND_FUNCTION_POINTER)
#undef WAYLAND_FUNCTION_POINTER
    // From the native C library, NULL when unavailable.
    int (*memfd_create)(const char *name, unsigned int flags);
    // NO when libwayland-cursor couldn't be loaded; cursors are then left to the compositor.
    bool hasCursor;
};

extern struct WaylandLibrary WL;

// Loads the libraries once. Returns false (after logging why) when any required one is missing.
bool WaylandLibraryLoad(void);

// Compares the hand-written opcodes in WaylandProtocol.h with the generated protocol tables.
bool WaylandCheckOpcodes(void);

// Sends a request; `interface` is the interface of the new object for requests that create one.
struct wl_proxy *WaylandMarshal(struct wl_proxy *proxy, uint32_t opcode,
                                const struct wl_interface *interface,
                                uint32_t flags, union wl_argument *args);

// Returns a file descriptor for `size` bytes of anonymous shared memory, or -1.
int WaylandCreateAnonymousFile(size_t size);

#endif
