// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// A minimal Wayland compositor for tests/appkit-window-occlusion-wayland.sh. It offers wl_compositor, wl_shm,
// one wl_output and xdg_wm_base version 6, shows nothing, and reports the xdg_toplevel suspended state the way a
// compositor does for a toplevel it stops repainting: it suspends each toplevel two seconds after the toplevel's
// first configure was acknowledged (and whenever the client asks to be minimized), and lifts the suspension three
// seconds later. Prints SUSPENDED and RESUMED lines. Usage: wayland-suspended-server <socket name>
// Build: cc wayland-suspended-server.c xdg-shell-server.c -lwayland-server (xdg-shell-server-protocol.h and
// xdg-shell-server.c come from wayland-scanner server-header and private-code on xdg-shell.xml)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server.h>

#include "xdg-shell-server-protocol.h"

static struct wl_display *display;

struct toplevel {
    struct wl_resource *surface, *toplevel;
    struct wl_event_source *timer;
    int phase; // 0 not yet shown, 1 waiting to suspend, 2 suspended, 3 resumed
};

static void send_state(struct toplevel *t, int suspended) {
    struct wl_array states;
    wl_array_init(&states);
    uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
    uint32_t count = 0;
    if (suspended) {
        *state = XDG_TOPLEVEL_STATE_SUSPENDED;
        count = 1;
    }
    states.size = count * sizeof(uint32_t);
    xdg_toplevel_send_configure(t->toplevel, 0, 0, &states);
    xdg_surface_send_configure(t->surface, wl_display_next_serial(display));
    wl_array_release(&states);
}

static int timer_fired(void *data) {
    struct toplevel *t = data;
    if (t->phase == 1) {
        t->phase = 2;
        send_state(t, 1);
        printf("SUSPENDED\n");
        fflush(stdout);
        wl_event_source_timer_update(t->timer, 3000);
    } else if (t->phase == 2) {
        t->phase = 3;
        send_state(t, 0);
        printf("RESUMED\n");
        fflush(stdout);
    }
    return 0;
}

static void noop(struct wl_client *client, struct wl_resource *resource) {}
static void destroy_request(struct wl_client *client, struct wl_resource *resource) { wl_resource_destroy(resource); }

// wl_surface: every request is accepted and ignored.
static void surface_attach(struct wl_client *c, struct wl_resource *r, struct wl_resource *b, int32_t x, int32_t y) {}
static void surface_damage(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) {}
static void surface_frame(struct wl_client *c, struct wl_resource *r, uint32_t callback) {
    struct wl_resource *cb = wl_resource_create(c, &wl_callback_interface, 1, callback);
    wl_callback_send_done(cb, 0);
    wl_resource_destroy(cb);
}
static void surface_region(struct wl_client *c, struct wl_resource *r, struct wl_resource *region) {}
static void surface_int(struct wl_client *c, struct wl_resource *r, int32_t value) {}
static const struct wl_surface_interface surface_impl = {
    .destroy = destroy_request, .attach = surface_attach, .damage = surface_damage, .frame = surface_frame,
    .set_opaque_region = surface_region, .set_input_region = surface_region, .commit = noop,
    .set_buffer_transform = surface_int, .set_buffer_scale = surface_int, .damage_buffer = surface_damage,
};

static void region_rect(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) {}
static const struct wl_region_interface region_impl = {destroy_request, region_rect, region_rect};

static void create_surface(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *s = wl_resource_create(c, &wl_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(s, &surface_impl, NULL, NULL);
}
static void create_region(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *s = wl_resource_create(c, &wl_region_interface, 1, id);
    wl_resource_set_implementation(s, &region_impl, NULL, NULL);
}
static const struct wl_compositor_interface compositor_impl = {create_surface, create_region};
static void bind_compositor(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_compositor_interface, version, id);
    wl_resource_set_implementation(r, &compositor_impl, NULL, NULL);
}

static void bind_output(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_output_interface, version, id);
    wl_resource_set_implementation(r, &(struct wl_output_interface){destroy_request}, NULL, NULL);
    wl_output_send_geometry(r, 0, 0, 500, 300, WL_OUTPUT_SUBPIXEL_UNKNOWN, "test", "output", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, 1920, 1080, 60000);
    if (version >= 2) {
        wl_output_send_scale(r, 1);
        wl_output_send_done(r);
    }
}

static void toplevel_destroyed(struct wl_resource *r) {
    struct toplevel *t = wl_resource_get_user_data(r);
    if (t->timer)
        wl_event_source_remove(t->timer);
    free(t);
}
static void toplevel_set_minimized(struct wl_client *c, struct wl_resource *r) {
    struct toplevel *t = wl_resource_get_user_data(r);
    if (t->phase == 0)
        return;
    t->phase = 2;
    send_state(t, 1);
    printf("SUSPENDED\n");
    fflush(stdout);
    wl_event_source_timer_update(t->timer, 3000);
}
static void toplevel_parent(struct wl_client *c, struct wl_resource *r, struct wl_resource *p) {}
static void toplevel_string(struct wl_client *c, struct wl_resource *r, const char *s) {}
static void toplevel_menu(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial,
                          int32_t x, int32_t y) {}
static void toplevel_move(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial) {}
static void toplevel_resize(struct wl_client *c, struct wl_resource *r, struct wl_resource *seat, uint32_t serial,
                            uint32_t edges) {}
static void toplevel_size(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) {}
static void toplevel_fullscreen(struct wl_client *c, struct wl_resource *r, struct wl_resource *output) {}
static const struct xdg_toplevel_interface toplevel_impl = {
    .destroy = destroy_request, .set_parent = toplevel_parent, .set_title = toplevel_string,
    .set_app_id = toplevel_string, .show_window_menu = toplevel_menu, .move = toplevel_move,
    .resize = toplevel_resize, .set_max_size = toplevel_size, .set_min_size = toplevel_size,
    .set_maximized = noop, .unset_maximized = noop, .set_fullscreen = toplevel_fullscreen,
    .unset_fullscreen = noop, .set_minimized = toplevel_set_minimized,
};

static void xdg_surface_get_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct toplevel *t = calloc(1, sizeof *t);
    t->surface = r;
    t->toplevel = wl_resource_create(c, &xdg_toplevel_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(t->toplevel, &toplevel_impl, t, toplevel_destroyed);
    t->timer = wl_event_loop_add_timer(wl_display_get_event_loop(display), timer_fired, t);
    wl_resource_set_user_data(r, t);
    send_state(t, 0);
}
static void xdg_surface_ack(struct wl_client *c, struct wl_resource *r, uint32_t serial) {
    struct toplevel *t = wl_resource_get_user_data(r);
    if (t != NULL && t->phase == 0) {
        t->phase = 1;
        wl_event_source_timer_update(t->timer, 2000);
    }
}
static void xdg_surface_geometry(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w,
                                 int32_t h) {}
static const struct xdg_surface_interface xdg_surface_impl = {
    .destroy = destroy_request, .get_toplevel = xdg_surface_get_toplevel, .get_popup = NULL,
    .set_window_geometry = xdg_surface_geometry, .ack_configure = xdg_surface_ack,
};

static void wm_get_xdg_surface(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *surface) {
    struct wl_resource *s = wl_resource_create(c, &xdg_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(s, &xdg_surface_impl, NULL, NULL);
}
static void wm_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial) {}
static const struct xdg_wm_base_interface wm_impl = {
    .destroy = destroy_request, .create_positioner = NULL, .get_xdg_surface = wm_get_xdg_surface, .pong = wm_pong,
};
static void bind_wm(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(r, &wm_impl, NULL, NULL);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: %s <socket name>\n", argv[0]);
        return 2;
    }
    display = wl_display_create();
    if (!display || wl_display_add_socket(display, argv[1]) != 0) {
        fprintf(stderr, "cannot create the socket %s (is XDG_RUNTIME_DIR set?)\n", argv[1]);
        return 2;
    }
    wl_display_init_shm(display);
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    wl_global_create(display, &xdg_wm_base_interface, 6, NULL, bind_wm);
    printf("LISTENING\n");
    fflush(stdout);
    wl_display_run(display);
    return 0;
}
