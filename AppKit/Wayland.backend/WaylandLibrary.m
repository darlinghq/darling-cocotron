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

#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <Foundation/NSString.h>
#include <elfcalls.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

extern struct elf_calls *_elfcalls;

struct WaylandLibrary WL;

static void *openLibrary(const char *name) {
    void *handle = _elfcalls->dlopen(name);
    if (handle == NULL) {
        const char *error = _elfcalls->dlerror();
        NSLog(@"Wayland backend: cannot load %s: %s", name,
              error ? error : "unknown error");
    }
    return handle;
}

static bool resolve(void *handle, const char *name, void **slot) {
    *slot = _elfcalls->dlsym(handle, name);
    if (*slot == NULL)
        NSLog(@"Wayland backend: missing native function %s", name);
    return *slot != NULL;
}

bool WaylandLibraryLoad(void) {
    static int loaded; // 0: not tried yet, 1: loaded, -1: failed

    if (loaded != 0)
        return loaded > 0;
    loaded = -1;

    if (_elfcalls == NULL) {
        NSLog(@"Wayland backend: native library loading isn't available");
        return false;
    }

    void *handle = openLibrary("libwayland-client.so.0");
    if (handle == NULL)
        return false;
#define WAYLAND_RESOLVE(name)                                                  \
    if (!resolve(handle, #name, (void **) &WL.name))                           \
        return false;
    WAYLAND_CLIENT_FUNCTIONS(WAYLAND_RESOLVE)

    handle = openLibrary("libxkbcommon.so.0");
    if (handle == NULL)
        return false;
    XKBCOMMON_FUNCTIONS(WAYLAND_RESOLVE)
#undef WAYLAND_RESOLVE

    // Optional: without it the pointer keeps whatever cursor the compositor shows.
    handle = openLibrary("libwayland-cursor.so.0");
    WL.hasCursor = handle != NULL;
#define WAYLAND_RESOLVE_OPTIONAL(name)                                         \
    if (WL.hasCursor && !resolve(handle, #name, (void **) &WL.name))           \
        WL.hasCursor = false;
    WAYLAND_CURSOR_FUNCTIONS(WAYLAND_RESOLVE_OPTIONAL)
#undef WAYLAND_RESOLVE_OPTIONAL

    WL.memfd_create = _elfcalls->dlsym(NULL, "memfd_create");

    loaded = 1;
    return true;
}

struct OpcodeCheck {
    const struct wl_interface *interface;
    bool event;
    int opcode;
    const char *name;
};

bool WaylandCheckOpcodes(void) {
    static const struct OpcodeCheck checks[] = {
            {&wl_display_interface, false, WP_DISPLAY_GET_REGISTRY, "get_registry"},
            {&wl_registry_interface, false, WP_REGISTRY_BIND, "bind"},
            {&wl_registry_interface, true, WP_REGISTRY_EV_GLOBAL, "global"},
            {&wl_registry_interface, true, WP_REGISTRY_EV_GLOBAL_REMOVE, "global_remove"},
            {&wl_callback_interface, true, WP_CALLBACK_EV_DONE, "done"},
            {&wl_compositor_interface, false, WP_COMPOSITOR_CREATE_SURFACE, "create_surface"},
            {&wl_shm_interface, false, WP_SHM_CREATE_POOL, "create_pool"},
            {&wl_shm_pool_interface, false, WP_SHM_POOL_CREATE_BUFFER, "create_buffer"},
            {&wl_shm_pool_interface, false, WP_SHM_POOL_DESTROY, "destroy"},
            {&wl_buffer_interface, false, WP_BUFFER_DESTROY, "destroy"},
            {&wl_buffer_interface, true, WP_BUFFER_EV_RELEASE, "release"},
            {&wl_surface_interface, false, WP_SURFACE_DESTROY, "destroy"},
            {&wl_surface_interface, false, WP_SURFACE_ATTACH, "attach"},
            {&wl_surface_interface, false, WP_SURFACE_DAMAGE, "damage"},
            {&wl_surface_interface, false, WP_SURFACE_FRAME, "frame"},
            {&wl_surface_interface, false, WP_SURFACE_COMMIT, "commit"},
            {&wl_surface_interface, false, WP_SURFACE_SET_BUFFER_SCALE, "set_buffer_scale"},
            {&wl_surface_interface, true, WP_SURFACE_EV_ENTER, "enter"},
            {&wl_surface_interface, true, WP_SURFACE_EV_LEAVE, "leave"},
            {&wl_surface_interface, false, WP_SURFACE_DAMAGE_BUFFER, "damage_buffer"},
            {&wl_seat_interface, false, WP_SEAT_GET_POINTER, "get_pointer"},
            {&wl_seat_interface, false, WP_SEAT_GET_KEYBOARD, "get_keyboard"},
            {&wl_seat_interface, true, WP_SEAT_EV_CAPABILITIES, "capabilities"},
            {&wl_pointer_interface, false, WP_POINTER_SET_CURSOR, "set_cursor"},
            {&wl_pointer_interface, false, WP_POINTER_RELEASE, "release"},
            {&wl_pointer_interface, true, WP_POINTER_EV_ENTER, "enter"},
            {&wl_pointer_interface, true, WP_POINTER_EV_LEAVE, "leave"},
            {&wl_pointer_interface, true, WP_POINTER_EV_MOTION, "motion"},
            {&wl_pointer_interface, true, WP_POINTER_EV_BUTTON, "button"},
            {&wl_pointer_interface, true, WP_POINTER_EV_AXIS, "axis"},
            {&wl_keyboard_interface, false, WP_KEYBOARD_RELEASE, "release"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_KEYMAP, "keymap"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_ENTER, "enter"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_LEAVE, "leave"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_KEY, "key"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_MODIFIERS, "modifiers"},
            {&wl_keyboard_interface, true, WP_KEYBOARD_EV_REPEAT_INFO, "repeat_info"},
            {&wl_output_interface, false, WP_OUTPUT_RELEASE, "release"},
            {&wl_output_interface, true, WP_OUTPUT_EV_MODE, "mode"},
            {&wl_output_interface, true, WP_OUTPUT_EV_DONE, "done"},
            {&wl_output_interface, true, WP_OUTPUT_EV_SCALE, "scale"},
            {&xdg_wm_base_interface, false, WP_WM_BASE_CREATE_POSITIONER, "create_positioner"},
            {&xdg_surface_interface, false, WP_XDG_SURFACE_GET_POPUP, "get_popup"},
            {&xdg_positioner_interface, false, WP_POSITIONER_DESTROY, "destroy"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_SIZE, "set_size"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_OFFSET, "set_offset"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_ANCHOR_RECT, "set_anchor_rect"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_ANCHOR, "set_anchor"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_GRAVITY, "set_gravity"},
            {&xdg_positioner_interface, false, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, "set_constraint_adjustment"},
            {&xdg_popup_interface, false, WP_POPUP_DESTROY, "destroy"},
            {&xdg_popup_interface, false, WP_POPUP_GRAB, "grab"},
            {&xdg_popup_interface, false, WP_POPUP_REPOSITION, "reposition"},
            {&xdg_popup_interface, true, WP_POPUP_EV_CONFIGURE, "configure"},
            {&xdg_popup_interface, true, WP_POPUP_EV_DONE, "popup_done"},
            {&xdg_wm_base_interface, false, WP_WM_BASE_GET_XDG_SURFACE, "get_xdg_surface"},
            {&xdg_wm_base_interface, false, WP_WM_BASE_PONG, "pong"},
            {&xdg_wm_base_interface, true, WP_WM_BASE_EV_PING, "ping"},
            {&xdg_surface_interface, false, WP_XDG_SURFACE_DESTROY, "destroy"},
            {&xdg_surface_interface, false, WP_XDG_SURFACE_GET_TOPLEVEL, "get_toplevel"},
            {&xdg_surface_interface, false, WP_XDG_SURFACE_ACK_CONFIGURE, "ack_configure"},
            {&xdg_surface_interface, true, WP_XDG_SURFACE_EV_CONFIGURE, "configure"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_DESTROY, "destroy"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_MOVE, "move"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_RESIZE, "resize"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_MAXIMIZED, "set_maximized"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_UNSET_MAXIMIZED, "unset_maximized"},
            {&zxdg_toplevel_decoration_v1_interface, true, WP_TOPLEVEL_DECORATION_EV_CONFIGURE, "configure"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_TITLE, "set_title"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_APP_ID, "set_app_id"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_MAX_SIZE, "set_max_size"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_MIN_SIZE, "set_min_size"},
            {&xdg_toplevel_interface, false, WP_TOPLEVEL_SET_MINIMIZED, "set_minimized"},
            {&xdg_toplevel_interface, true, WP_TOPLEVEL_EV_CONFIGURE, "configure"},
            {&xdg_toplevel_interface, true, WP_TOPLEVEL_EV_CLOSE, "close"},
            {&zxdg_decoration_manager_v1_interface, false,
             WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION, "get_toplevel_decoration"},
            {&zxdg_toplevel_decoration_v1_interface, false,
             WP_TOPLEVEL_DECORATION_DESTROY, "destroy"},
            {&zxdg_toplevel_decoration_v1_interface, false,
             WP_TOPLEVEL_DECORATION_SET_MODE, "set_mode"},
    };

    for (size_t i = 0; i < sizeof(checks) / sizeof(checks[0]); i++) {
        const struct OpcodeCheck *check = &checks[i];
        int count = check->event ? check->interface->event_count
                                 : check->interface->method_count;
        const struct wl_message *messages = check->event
                                                    ? check->interface->events
                                                    : check->interface->methods;

        if (check->opcode >= count ||
            strcmp(messages[check->opcode].name, check->name) != 0) {
            NSLog(@"Wayland backend: opcode %d of %s.%s doesn't match the "
                  @"protocol tables",
                  check->opcode, check->interface->name, check->name);
            return false;
        }
    }
    return true;
}

struct wl_proxy *WaylandMarshal(struct wl_proxy *proxy, uint32_t opcode,
                                const struct wl_interface *interface,
                                uint32_t flags, union wl_argument *args)
{
    return WL.wl_proxy_marshal_array_flags(proxy, opcode, interface,
                                           WL.wl_proxy_get_version(proxy),
                                           flags, args);
}

int WaylandCreateAnonymousFile(size_t size) {
    int fd = -1;

    if (WL.memfd_create != NULL)
        fd = WL.memfd_create("darling-wayland-shm", 1 /* MFD_CLOEXEC */);

    if (fd < 0 && _elfcalls->shm_open != NULL) {
        static unsigned counter;
        char name[64];

        for (int attempt = 0; fd < 0 && attempt < 16; attempt++) {
            snprintf(name, sizeof(name), "/darling-wayland-%d-%u", getpid(),
                     counter++);
            // shm_open runs natively, so these are the Linux values of
            // O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC.
            fd = _elfcalls->shm_open(name, 02 | 0100 | 0200 | 02000000, 0600);
        }
        if (fd >= 0)
            _elfcalls->shm_unlink(name);
    }

    if (fd < 0) {
        NSLog(@"Wayland backend: neither memfd_create nor shm_open gave shared "
              @"memory");
        return -1;
    }

    if (ftruncate(fd, (off_t) size) != 0) {
        NSLog(@"Wayland backend: cannot size shared memory to %zu bytes: %s", size,
              strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}
