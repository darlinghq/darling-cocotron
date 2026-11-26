/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// Minimal private compositor that sends xdg_wm_base.ping after the client maps
// a toplevel and expects xdg_wm_base.pong while the client's main thread is stalled.
#include <wayland-server.h>
#include <wayland-server-protocol.h>
#include "xdg-shell-server.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static struct wl_display *display;
static struct wl_resource *wm_base_resource;
static struct wl_event_source *ping_timer;
static struct wl_event_source *timeout_timer;
static const uint32_t kPingSerial = 0x12345678u;
static int ping_sent = 0;
static int pong_ok = 0;

static void destroy_res(struct wl_client *c, struct wl_resource *r) {
    (void) c;
    wl_resource_destroy(r);
}

static int on_timeout(void *data) {
    (void) data;
    if (!pong_ok) {
        fprintf(stderr, "PONG_TIMEOUT\n");
        fflush(stderr);
        wl_display_terminate(display);
    }
    return 0;
}

static int on_send_ping(void *data) {
    (void) data;
    if (wm_base_resource != NULL && !ping_sent) {
        ping_sent = 1;
        xdg_wm_base_send_ping(wm_base_resource, kPingSerial);
        wl_display_flush_clients(display);
        printf("PING_SENT serial=0x%x\n", kPingSerial);
        fflush(stdout);
        wl_event_source_timer_update(timeout_timer, 3000);
    }
    return 0;
}

static void toplevel_noop(struct wl_client *c, struct wl_resource *r) { (void) c; (void) r; }
static void toplevel_set_parent(struct wl_client *c, struct wl_resource *r, struct wl_resource *p) { (void) c; (void) r; (void) p; }
static void toplevel_set_str(struct wl_client *c, struct wl_resource *r, const char *s) { (void) c; (void) r; (void) s; }
static void toplevel_show_menu(struct wl_client *c, struct wl_resource *r, struct wl_resource *s, uint32_t ser, int32_t x, int32_t y) { (void) c; (void) r; (void) s; (void) ser; (void) x; (void) y; }
static void toplevel_move(struct wl_client *c, struct wl_resource *r, struct wl_resource *s, uint32_t ser) { (void) c; (void) r; (void) s; (void) ser; }
static void toplevel_resize(struct wl_client *c, struct wl_resource *r, struct wl_resource *s, uint32_t ser, uint32_t edges) { (void) c; (void) r; (void) s; (void) ser; (void) edges; }
static void toplevel_size(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h) { (void) c; (void) r; (void) w; (void) h; }
static void toplevel_fullscreen(struct wl_client *c, struct wl_resource *r, struct wl_resource *o) { (void) c; (void) r; (void) o; }

static const struct xdg_toplevel_interface toplevel_impl = {
    .destroy = destroy_res,
    .set_parent = toplevel_set_parent,
    .set_title = toplevel_set_str,
    .set_app_id = toplevel_set_str,
    .show_window_menu = toplevel_show_menu,
    .move = toplevel_move,
    .resize = toplevel_resize,
    .set_max_size = toplevel_size,
    .set_min_size = toplevel_size,
    .set_maximized = toplevel_noop,
    .unset_maximized = toplevel_noop,
    .set_fullscreen = toplevel_fullscreen,
    .unset_fullscreen = toplevel_noop,
    .set_minimized = toplevel_noop,
};

static void xdg_surface_get_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *toplevel = wl_resource_create(c, &xdg_toplevel_interface,
                                                      wl_resource_get_version(r), id);
    wl_resource_set_implementation(toplevel, &toplevel_impl, NULL, NULL);
    struct wl_array states;
    wl_array_init(&states);
    xdg_toplevel_send_configure(toplevel, 320, 200, &states);
    wl_array_release(&states);
    xdg_surface_send_configure(r, wl_display_next_serial(display));
    // Give the client time to enter its main-thread stall before sending ping.
    wl_event_source_timer_update(ping_timer, 300);
}

static void xdg_surface_ack_configure(struct wl_client *c, struct wl_resource *r, uint32_t serial) {
    (void) c;
    (void) r;
    (void) serial;
}

static const struct xdg_surface_interface xdg_surface_impl = {
    .destroy = destroy_res,
    .get_toplevel = xdg_surface_get_toplevel,
    .ack_configure = xdg_surface_ack_configure,
};

static void wm_create_positioner(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *pos = wl_resource_create(c, &xdg_positioner_interface,
                                                 wl_resource_get_version(r), id);
    wl_resource_set_implementation(pos, NULL, NULL, NULL);
}

static void wm_get_xdg_surface(struct wl_client *c, struct wl_resource *r,
                               uint32_t id, struct wl_resource *surface) {
    (void) surface;
    struct wl_resource *xs = wl_resource_create(c, &xdg_surface_interface,
                                                wl_resource_get_version(r), id);
    wl_resource_set_implementation(xs, &xdg_surface_impl, NULL, NULL);
}

static void wm_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial) {
    (void) c;
    (void) r;
    printf("PONG_RECEIVED serial=0x%x\n", serial);
    fflush(stdout);
    if (serial == kPingSerial) {
        pong_ok = 1;
        printf("PONG_OK serial=0x%x\n", serial);
        fflush(stdout);
        wl_display_terminate(display);
    }
}

static const struct xdg_wm_base_interface wm_impl = {
    .destroy = destroy_res,
    .create_positioner = wm_create_positioner,
    .get_xdg_surface = wm_get_xdg_surface,
    .pong = wm_pong,
};

static void wm_destroyed(struct wl_resource *r) {
    if (wm_base_resource == r)
        wm_base_resource = NULL;
}

static void bind_wm(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    (void) data;
    struct wl_resource *r = wl_resource_create(c, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(r, &wm_impl, NULL, wm_destroyed);
    // Keep the most recent xdg_wm_base bound (AppKit's WaylandDisplay binds after CGS).
    wm_base_resource = r;
}

static void surface_attach(struct wl_client *c, struct wl_resource *r, struct wl_resource *b, int32_t x, int32_t y) { (void)c;(void)r;(void)b;(void)x;(void)y; }
static void surface_damage(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y, int32_t w, int32_t h) { (void)c;(void)r;(void)x;(void)y;(void)w;(void)h; }
static void surface_frame(struct wl_client *c, struct wl_resource *r, uint32_t cb) {
    struct wl_resource *res = wl_resource_create(c, &wl_callback_interface, 1, cb);
    wl_callback_send_done(res, 0);
    wl_resource_destroy(res);
}
static void surface_region(struct wl_client *c, struct wl_resource *r, struct wl_resource *reg) { (void)c;(void)r;(void)reg; }
static void surface_commit(struct wl_client *c, struct wl_resource *r) { (void)c;(void)r; }
static void surface_i32(struct wl_client *c, struct wl_resource *r, int32_t v) { (void)c;(void)r;(void)v; }

static const struct wl_surface_interface surface_impl = {
    .destroy = destroy_res,
    .attach = surface_attach,
    .damage = surface_damage,
    .frame = surface_frame,
    .set_opaque_region = surface_region,
    .set_input_region = surface_region,
    .commit = surface_commit,
    .set_buffer_transform = surface_i32,
    .set_buffer_scale = surface_i32,
    .damage_buffer = surface_damage,
};

static void create_surface(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *s = wl_resource_create(c, &wl_surface_interface,
                                               wl_resource_get_version(r), id);
    wl_resource_set_implementation(s, &surface_impl, NULL, NULL);
}

static const struct wl_compositor_interface compositor_impl = {.create_surface = create_surface};

static void bind_compositor(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    (void) data;
    struct wl_resource *r = wl_resource_create(c, &wl_compositor_interface, version, id);
    wl_resource_set_implementation(r, &compositor_impl, NULL, NULL);
}

static const struct wl_output_interface output_impl = {destroy_res};

static void bind_output(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    (void) data;
    struct wl_resource *r = wl_resource_create(c, &wl_output_interface, version, id);
    wl_resource_set_implementation(r, &output_impl, NULL, NULL);
    wl_output_send_geometry(r, 0, 0, 100, 100, WL_OUTPUT_SUBPIXEL_UNKNOWN,
                            "fixture", "output", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT, 1280, 800, 60000);
    if (version >= 2) {
        wl_output_send_scale(r, 1);
        wl_output_send_done(r);
    }
}

int main(void) {
    display = wl_display_create();
    if (!display)
        return 2;
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_display_init_shm(display);
    wl_global_create(display, &xdg_wm_base_interface, 2, NULL, bind_wm);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    const char *socket = wl_display_add_socket_auto(display);
    if (!socket)
        return 2;
    struct wl_event_loop *loop = wl_display_get_event_loop(display);
    ping_timer = wl_event_loop_add_timer(loop, on_send_ping, NULL);
    timeout_timer = wl_event_loop_add_timer(loop, on_timeout, NULL);
    wl_event_source_timer_update(timeout_timer, 15000);
    printf("READY %s\n", socket);
    fflush(stdout);
    wl_display_run(display);
    wl_display_destroy_clients(display);
    wl_display_destroy(display);
    return pong_ok ? 0 : 1;
}
