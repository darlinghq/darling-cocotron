// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// A minimal Wayland compositor for tests/appkit-wayland-ping.sh. It offers wl_compositor, wl_shm, one wl_output and
// xdg_wm_base version 6, shows nothing, and tests whether the client answers xdg_wm_base.ping: from the first
// acknowledged configure of a toplevel on, it sends a ping every 400 ms and prints "PONG <serial> <latency in ms>" for
// each answer. 300 ms after the first acknowledgement it also configures the toplevel to 400x300 (a client whose
// xdg_surface events are dispatched on the wrong thread shows that in the test). When the client disconnects, it prints
// "SUMMARY pings=<n> answered=<n> max_latency_ms=<n>" and exits. Usage: wayland-ping-server <socket name>
// Build: cc wayland-ping-server.c xdg-shell-server.c -lwayland-server (xdg-shell-server-protocol.h and xdg-shell-server.c
// come from wayland-scanner server-header and private-code on xdg-shell.xml)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-server.h>

#include "xdg-shell-server-protocol.h"

static struct wl_display *display;
static struct wl_resource *wm_base, *toplevel_surface, *toplevel;
static struct wl_event_source *ping_timer, *resize_timer;
static int pings, answered;
static long max_latency_ms;
static int resized;

#define MAX_PINGS 256
static struct {
    uint32_t serial;
    struct timespec sent;
    int open;
} outstanding[MAX_PINGS];

static long ms_since(const struct timespec *then) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (now.tv_sec - then->tv_sec) * 1000 + (now.tv_nsec - then->tv_nsec) / 1000000;
}

static int send_ping(void *data) {
    if (wm_base != NULL && pings < MAX_PINGS) {
        uint32_t serial = wl_display_next_serial(display);
        outstanding[pings].serial = serial;
        outstanding[pings].open = 1;
        clock_gettime(CLOCK_MONOTONIC, &outstanding[pings].sent);
        pings++;
        xdg_wm_base_send_ping(wm_base, serial);
        wl_display_flush_clients(display);
    }
    wl_event_source_timer_update(ping_timer, 400);
    return 0;
}

static void configure(int width, int height) {
    struct wl_array states;
    wl_array_init(&states);
    xdg_toplevel_send_configure(toplevel, width, height, &states);
    xdg_surface_send_configure(toplevel_surface, wl_display_next_serial(display));
    wl_array_release(&states);
}

static int send_resize(void *data) {
    if (toplevel != NULL && !resized) {
        resized = 1;
        configure(400, 300);
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
    .unset_fullscreen = noop, .set_minimized = noop,
};

static void xdg_surface_get_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    toplevel_surface = r;
    toplevel = wl_resource_create(c, &xdg_toplevel_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(toplevel, &toplevel_impl, NULL, NULL);
    configure(0, 0);
}
static void xdg_surface_ack(struct wl_client *c, struct wl_resource *r, uint32_t serial) {
    static int first = 1;
    if (first) {
        first = 0;
        wl_event_source_timer_update(ping_timer, 400);
        wl_event_source_timer_update(resize_timer, 300);
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
static void wm_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial) {
    for (int i = 0; i < pings; i++) {
        if (outstanding[i].open && outstanding[i].serial == serial) {
            long latency = ms_since(&outstanding[i].sent);
            outstanding[i].open = 0;
            answered++;
            if (latency > max_latency_ms)
                max_latency_ms = latency;
            printf("PONG %u %ld\n", serial, latency);
            fflush(stdout);
            return;
        }
    }
}
static void wm_create_positioner(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    wl_resource_create(c, &xdg_positioner_interface, wl_resource_get_version(r), id);
}
static const struct xdg_wm_base_interface wm_impl = {
    .destroy = destroy_request, .create_positioner = wm_create_positioner, .get_xdg_surface = wm_get_xdg_surface,
    .pong = wm_pong,
};
static void wm_destroyed(struct wl_resource *r) {
    if (wm_base == r)
        wm_base = NULL;
}
static void bind_wm(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(r, &wm_impl, NULL, wm_destroyed);
    wm_base = r;
}

static struct wl_listener client_destroyed;
static void client_gone(struct wl_listener *listener, void *data) {
    // A ping sent just before the client left may have had no time to be answered: it does not count.
    int counted = 0;
    for (int i = 0; i < pings; i++)
        if (!outstanding[i].open || ms_since(&outstanding[i].sent) >= 300)
            counted++;
    printf("SUMMARY pings=%d answered=%d max_latency_ms=%ld\n", counted, answered, max_latency_ms);
    fflush(stdout);
    wl_display_terminate(display);
}
static void client_created(struct wl_listener *listener, void *data) {
    client_destroyed.notify = client_gone;
    wl_client_add_destroy_listener(data, &client_destroyed);
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
    struct wl_listener created = {.notify = client_created};
    wl_display_add_client_created_listener(display, &created);
    struct wl_event_loop *loop = wl_display_get_event_loop(display);
    ping_timer = wl_event_loop_add_timer(loop, send_ping, NULL);
    resize_timer = wl_event_loop_add_timer(loop, send_resize, NULL);
    wl_display_init_shm(display);
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    wl_global_create(display, &xdg_wm_base_interface, 6, NULL, bind_wm);
    printf("LISTENING\n");
    fflush(stdout);
    wl_display_run(display);
    return 0;
}
