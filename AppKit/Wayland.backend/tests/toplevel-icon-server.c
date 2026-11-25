/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A private compositor, only as much of one as a window of the AppKit Wayland backend needs (wl_compositor,
// wl_shm, one wl_output, xdg-shell), plus the xdg-toplevel-icon protocol. It checks what a client does with
// the icon protocol, raising the protocol errors a real compositor raises (a buffer that is not a square
// shm buffer, an icon changed after it was assigned, a buffer destroyed before the icon), and prints what
// each toplevel got when its surface commits:
//   ICON <title> <n> <size>@<scale>... <colour at the centre of the largest buffer, AARRGGBB>
//   ICON <title> none      the toplevel's icon was cleared
// and APPID <title> <app_id>. It renders nothing. Run it through wayland-toplevel-icon.sh.
//   toplevel-icon-server <socket name> [sizes <size>,<size>...] [no-manager] [remove-manager <seconds>]
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server.h>
#include "xdg-shell-server-protocol.h"
#include "xdg-toplevel-icon-v1-server-protocol.h"

#define MAX_BUFFERS 64

static struct wl_display *display;
static struct wl_global *manager_global;
static struct wl_event_loop *loop;
static const char *advertised_sizes = "";

struct icon_buffer {
    struct wl_resource *buffer;
    int scale;
};

struct icon;
struct buffer_watch {
    struct wl_listener listener;
    struct icon *icon;
};

struct icon {
    struct wl_resource *resource;
    struct icon_buffer buffers[MAX_BUFFERS];
    struct buffer_watch *watches[MAX_BUFFERS];
    int count;
    int assigned;
    int destroyed;
};

struct toplevel;
struct surface {
    struct wl_resource *resource;
    struct wl_resource *pending_buffer;
    struct wl_resource *frame;
    struct toplevel *toplevel;
};

struct toplevel {
    struct wl_resource *resource;
    struct surface *surface;
    char *title, *app_id;
    // What the icon request waiting for the next commit amounts to, printed when the surface commits.
    char *pending_report;
};

static void noop() {}

// ---- wl_surface

static char *make_report(struct toplevel *toplevel, struct icon *icon) {
    char *text = NULL;
    size_t length = 0;
    FILE *out = open_memstream(&text, &length);
    const char *title = toplevel->title ? toplevel->title : "";
    if (icon == NULL || icon->count == 0) {
        fprintf(out, "ICON %s none\n", title);
    } else {
        fprintf(out, "ICON %s %d", title, icon->count);
        int largest = 0;
        unsigned centre = 0;
        for (int i = 0; i < icon->count; i++) {
            struct wl_shm_buffer *shm = wl_shm_buffer_get(icon->buffers[i].buffer);
            int size = wl_shm_buffer_get_width(shm);
            fprintf(out, " %d@%d", size / icon->buffers[i].scale, icon->buffers[i].scale);
            if (size > largest) {
                largest = size;
                wl_shm_buffer_begin_access(shm);
                const uint32_t *pixels = wl_shm_buffer_get_data(shm);
                centre = pixels[(size / 2) * (wl_shm_buffer_get_stride(shm) / 4) + size / 2];
                wl_shm_buffer_end_access(shm);
            }
        }
        fprintf(out, " %08X\n", centre);
    }
    fclose(out);
    return text;
}

static void surface_attach(struct wl_client *c, struct wl_resource *r, struct wl_resource *buffer, int32_t x,
                           int32_t y) {
    struct surface *surface = wl_resource_get_user_data(r);
    surface->pending_buffer = buffer;
}

static void surface_frame(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct surface *surface = wl_resource_get_user_data(r);
    surface->frame = wl_resource_create(c, &wl_callback_interface, 1, id);
}

static void surface_commit(struct wl_client *c, struct wl_resource *r) {
    struct surface *surface = wl_resource_get_user_data(r);
    if (surface->pending_buffer != NULL) {
        wl_buffer_send_release(surface->pending_buffer);
        surface->pending_buffer = NULL;
    }
    if (surface->frame != NULL) {
        wl_callback_send_done(surface->frame, 0);
        wl_resource_destroy(surface->frame);
        surface->frame = NULL;
    }
    struct toplevel *toplevel = surface->toplevel;
    if (toplevel != NULL && toplevel->pending_report != NULL) {
        fputs(toplevel->pending_report, stdout);
        fflush(stdout);
        free(toplevel->pending_report);
        toplevel->pending_report = NULL;
    }
}

static void surface_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct wl_surface_interface surface_impl = {
    .destroy = surface_destroy_request,
    .attach = surface_attach,
    .damage = noop,
    .frame = surface_frame,
    .set_opaque_region = noop,
    .set_input_region = noop,
    .commit = surface_commit,
    .set_buffer_transform = noop,
    .set_buffer_scale = noop,
    .damage_buffer = noop,
    .offset = noop,
};

static void surface_gone(struct wl_resource *r) {
    struct surface *surface = wl_resource_get_user_data(r);
    if (surface->toplevel != NULL)
        surface->toplevel->surface = NULL;
    free(surface);
}

static void compositor_create_surface(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct surface *surface = calloc(1, sizeof(*surface));
    surface->resource = wl_resource_create(c, &wl_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(surface->resource, &surface_impl, surface, surface_gone);
}

static const struct wl_compositor_interface compositor_impl = {
    .create_surface = compositor_create_surface,
    .create_region = noop,
};

static void bind_compositor(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_compositor_interface, version, id);
    wl_resource_set_implementation(r, &compositor_impl, NULL, NULL);
}

// ---- wl_output

static void bind_output(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_output_interface, version, id);
    wl_output_send_geometry(r, 0, 0, 508, 286, WL_OUTPUT_SUBPIXEL_UNKNOWN, "test", "icon", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, 1920, 1080, 60000);
    if (version >= 2) {
        wl_output_send_scale(r, 1);
        wl_output_send_done(r);
    }
}

// ---- xdg-shell

static void toplevel_set_title(struct wl_client *c, struct wl_resource *r, const char *title) {
    struct toplevel *toplevel = wl_resource_get_user_data(r);
    free(toplevel->title);
    toplevel->title = strdup(title);
}

static void toplevel_set_app_id(struct wl_client *c, struct wl_resource *r, const char *app_id) {
    struct toplevel *toplevel = wl_resource_get_user_data(r);
    free(toplevel->app_id);
    toplevel->app_id = strdup(app_id);
    printf("APPID %s %s\n", toplevel->title ? toplevel->title : "", app_id);
    fflush(stdout);
}

static void toplevel_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct xdg_toplevel_interface toplevel_impl = {
    .destroy = toplevel_destroy_request,
    .set_parent = noop,
    .set_title = toplevel_set_title,
    .set_app_id = toplevel_set_app_id,
    .show_window_menu = noop,
    .move = noop,
    .resize = noop,
    .set_max_size = noop,
    .set_min_size = noop,
    .set_maximized = noop,
    .unset_maximized = noop,
    .set_fullscreen = noop,
    .unset_fullscreen = noop,
    .set_minimized = noop,
};

static void toplevel_gone(struct wl_resource *r) {
    struct toplevel *toplevel = wl_resource_get_user_data(r);
    if (toplevel->surface != NULL)
        toplevel->surface->toplevel = NULL;
    free(toplevel->title);
    free(toplevel->app_id);
    free(toplevel->pending_report);
    free(toplevel);
}

struct xdg_surface_data {
    struct surface *surface;
    struct wl_resource *resource;
};

static void xdg_surface_get_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct xdg_surface_data *xs = wl_resource_get_user_data(r);
    struct toplevel *toplevel = calloc(1, sizeof(*toplevel));
    toplevel->surface = xs->surface;
    xs->surface->toplevel = toplevel;
    toplevel->resource = wl_resource_create(c, &xdg_toplevel_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(toplevel->resource, &toplevel_impl, toplevel, toplevel_gone);
    struct wl_array states;
    wl_array_init(&states);
    xdg_toplevel_send_configure(toplevel->resource, 0, 0, &states);
    wl_array_release(&states);
    xdg_surface_send_configure(r, wl_display_next_serial(display));
}

static void xdg_surface_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct xdg_surface_interface xdg_surface_impl = {
    .destroy = xdg_surface_destroy_request,
    .get_toplevel = xdg_surface_get_toplevel,
    .get_popup = noop,
    .set_window_geometry = noop,
    .ack_configure = noop,
};

static void xdg_surface_gone(struct wl_resource *r) {
    free(wl_resource_get_user_data(r));
}

static void wm_get_xdg_surface(struct wl_client *c, struct wl_resource *r, uint32_t id, struct wl_resource *surface) {
    struct xdg_surface_data *xs = calloc(1, sizeof(*xs));
    xs->surface = wl_resource_get_user_data(surface);
    xs->resource = wl_resource_create(c, &xdg_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(xs->resource, &xdg_surface_impl, xs, xdg_surface_gone);
}

static void wm_pong(struct wl_client *c, struct wl_resource *r, uint32_t serial) {}

static const struct xdg_wm_base_interface wm_impl = {
    .destroy = xdg_surface_destroy_request,
    .create_positioner = noop,
    .get_xdg_surface = wm_get_xdg_surface,
    .pong = wm_pong,
};

static void bind_wm(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(r, &wm_impl, NULL, NULL);
}

// ---- xdg-toplevel-icon

// A buffer given to an icon may not go away while the icon exists.
static void buffer_destroyed(struct wl_listener *listener, void *data) {
    struct buffer_watch *watch = (struct buffer_watch *) listener;
    wl_list_remove(&listener->link);
    wl_list_init(&listener->link);
    if (!watch->icon->destroyed)
        wl_resource_post_error(watch->icon->resource, XDG_TOPLEVEL_ICON_V1_ERROR_NO_BUFFER,
                               "a buffer was destroyed before its icon");
}

static void icon_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void icon_set_name(struct wl_client *c, struct wl_resource *r, const char *name) {
    struct icon *icon = wl_resource_get_user_data(r);
    if (icon->assigned)
        wl_resource_post_error(r, XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE, "icon already assigned");
}

static void icon_add_buffer(struct wl_client *c, struct wl_resource *r, struct wl_resource *buffer, int32_t scale) {
    struct icon *icon = wl_resource_get_user_data(r);
    if (icon->assigned) {
        wl_resource_post_error(r, XDG_TOPLEVEL_ICON_V1_ERROR_IMMUTABLE, "icon already assigned");
        return;
    }
    struct wl_shm_buffer *shm = wl_shm_buffer_get(buffer);
    if (shm == NULL || wl_shm_buffer_get_width(shm) != wl_shm_buffer_get_height(shm) || scale < 1 ||
        icon->count >= MAX_BUFFERS) {
        wl_resource_post_error(r, XDG_TOPLEVEL_ICON_V1_ERROR_INVALID_BUFFER, "not a square shm buffer");
        return;
    }
    // A later buffer of the same size and scale replaces the earlier one.
    for (int i = 0; i < icon->count; i++) {
        if (wl_shm_buffer_get_width(wl_shm_buffer_get(icon->buffers[i].buffer)) == wl_shm_buffer_get_width(shm) &&
            icon->buffers[i].scale == scale) {
            icon->buffers[i].buffer = buffer;
            return;
        }
    }
    icon->buffers[icon->count].buffer = buffer;
    icon->buffers[icon->count].scale = scale;
    struct buffer_watch *watch = calloc(1, sizeof(*watch));
    watch->listener.notify = buffer_destroyed;
    watch->icon = icon;
    wl_resource_add_destroy_listener(buffer, &watch->listener);
    icon->watches[icon->count] = watch;
    icon->count++;
}

static const struct xdg_toplevel_icon_v1_interface icon_impl = {
    .destroy = icon_destroy_request,
    .set_name = icon_set_name,
    .add_buffer = icon_add_buffer,
};

static void icon_gone(struct wl_resource *r) {
    struct icon *icon = wl_resource_get_user_data(r);
    icon->destroyed = 1;
    for (int i = 0; i < icon->count; i++) {
        if (!wl_list_empty(&icon->watches[i]->listener.link))
            wl_list_remove(&icon->watches[i]->listener.link);
        free(icon->watches[i]);
    }
    free(icon);
}

static void manager_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void manager_create_icon(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct icon *icon = calloc(1, sizeof(*icon));
    icon->resource = wl_resource_create(c, &xdg_toplevel_icon_v1_interface, 1, id);
    wl_resource_set_implementation(icon->resource, &icon_impl, icon, icon_gone);
}

static void manager_set_icon(struct wl_client *c, struct wl_resource *r, struct wl_resource *toplevel_resource,
                             struct wl_resource *icon_resource) {
    struct toplevel *toplevel = wl_resource_get_user_data(toplevel_resource);
    struct icon *icon = icon_resource ? wl_resource_get_user_data(icon_resource) : NULL;
    if (icon != NULL)
        icon->assigned = 1;
    // The pixels are read now: the client may destroy the buffers once it destroys the icon.
    free(toplevel->pending_report);
    toplevel->pending_report = make_report(toplevel, icon);
}

static const struct xdg_toplevel_icon_manager_v1_interface manager_impl = {
    .destroy = manager_destroy_request,
    .create_icon = manager_create_icon,
    .set_icon = manager_set_icon,
};

static void bind_manager(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_toplevel_icon_manager_v1_interface, version, id);
    wl_resource_set_implementation(r, &manager_impl, NULL, NULL);
    char *sizes = strdup(advertised_sizes);
    for (char *s = strtok(sizes, ","); s != NULL; s = strtok(NULL, ","))
        xdg_toplevel_icon_manager_v1_send_icon_size(r, atoi(s));
    free(sizes);
    xdg_toplevel_icon_manager_v1_send_done(r);
}

static int remove_manager(void *data) {
    wl_global_remove(manager_global);
    printf("MANAGER removed\n");
    fflush(stdout);
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: toplevel-icon-server <socket> [sizes a,b] [no-manager] [remove-manager <s>]\n");
        return 2;
    }
    int with_manager = 1;
    int remove_after = 0;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "sizes") && i + 1 < argc)
            advertised_sizes = argv[++i];
        else if (!strcmp(argv[i], "no-manager"))
            with_manager = 0;
        else if (!strcmp(argv[i], "remove-manager") && i + 1 < argc)
            remove_after = atoi(argv[++i]);
    }
    display = wl_display_create();
    loop = wl_display_get_event_loop(display);
    if (wl_display_add_socket(display, argv[1]) != 0) {
        fprintf(stderr, "cannot create the socket\n");
        return 1;
    }
    wl_display_init_shm(display);
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    wl_global_create(display, &xdg_wm_base_interface, 1, NULL, bind_wm);
    if (with_manager)
        manager_global = wl_global_create(display, &xdg_toplevel_icon_manager_v1_interface, 1, NULL, bind_manager);
    if (remove_after > 0 && with_manager) {
        struct wl_event_source *timer = wl_event_loop_add_timer(loop, remove_manager, NULL);
        wl_event_source_timer_update(timer, remove_after * 1000);
    }
    printf("SERVER ready\n");
    fflush(stdout);
    wl_display_run(display);
    return 0;
}
