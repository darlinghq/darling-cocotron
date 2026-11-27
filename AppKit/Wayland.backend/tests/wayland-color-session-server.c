/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// A private compositor for color management, sessions and the Linux render protocols. It
// advertises an sRGB/P3 display with HDR headroom, parametric descriptions with v3 surface
// feedback, premultiplied electrical alpha, a linear ARGB8888 dma-buf, explicit sync and fifo.
// It renders nothing and prints the protocol activity used by wayland-color-session.sh.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <wayland-server.h>
#include "color-management-v1-server-protocol.h"
#include "color-representation-v1-server-protocol.h"
#include "xdg-shell-server-protocol.h"
#include "xdg-session-management-v1-server-protocol.h"
#include "linux-dmabuf-v1-server-protocol.h"
#include "linux-drm-syncobj-v1-server-protocol.h"
#include "fifo-v1-server-protocol.h"

static struct wl_display *display;
static const char *session_id = "test-session-1";

struct toplevel;
struct surface {
    struct wl_resource *resource;
    struct wl_resource *buffer;
    struct wl_resource *frame;
    struct toplevel *toplevel;
    uint32_t commits;
    uint32_t primaries, tf;
};

struct toplevel {
    struct wl_resource *resource;
    struct surface *surface;
    char *title;
};

struct description {
    uint32_t primaries, tf;
};

struct creator {
    uint32_t primaries, tf;
};

struct session {
    uint32_t reason;
    char *id;
};

static void noop() {}

// ---- Core protocol and xdg-shell

static void surface_attach(struct wl_client *c, struct wl_resource *r, struct wl_resource *buffer,
                           int32_t x, int32_t y) {
    struct surface *surface = wl_resource_get_user_data(r);
    surface->buffer = buffer;
}

static void surface_frame(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct surface *surface = wl_resource_get_user_data(r);
    surface->frame = wl_resource_create(c, &wl_callback_interface, 1, id);
}

static void surface_commit(struct wl_client *c, struct wl_resource *r) {
    struct surface *surface = wl_resource_get_user_data(r);
    surface->commits++;
    if (surface->buffer != NULL) {
        wl_buffer_send_release(surface->buffer);
        surface->buffer = NULL;
    }
    if (surface->frame != NULL) {
        wl_callback_send_done(surface->frame, 0);
        wl_resource_destroy(surface->frame);
        surface->frame = NULL;
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

static void bind_output(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_output_interface, version, id);
    wl_output_send_geometry(r, 0, 0, 508, 286, WL_OUTPUT_SUBPIXEL_UNKNOWN,
                            "test", "color", WL_OUTPUT_TRANSFORM_NORMAL);
    wl_output_send_mode(r, WL_OUTPUT_MODE_CURRENT | WL_OUTPUT_MODE_PREFERRED, 1920, 1080, 60000);
    if (version >= 2) {
        wl_output_send_scale(r, 1);
        wl_output_send_done(r);
    }
}

static void toplevel_set_title(struct wl_client *c, struct wl_resource *r, const char *title) {
    struct toplevel *toplevel = wl_resource_get_user_data(r);
    free(toplevel->title);
    toplevel->title = strdup(title);
}

static void toplevel_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct xdg_toplevel_interface toplevel_impl = {
    .destroy = toplevel_destroy_request,
    .set_parent = noop,
    .set_title = toplevel_set_title,
    .set_app_id = noop,
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
    free(toplevel);
}

struct xdg_surface_data {
    struct surface *surface;
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

static void wm_get_xdg_surface(struct wl_client *c, struct wl_resource *r, uint32_t id,
                               struct wl_resource *surface) {
    struct xdg_surface_data *xs = calloc(1, sizeof(*xs));
    xs->surface = wl_resource_get_user_data(surface);
    struct wl_resource *xr = wl_resource_create(c, &xdg_surface_interface, wl_resource_get_version(r), id);
    wl_resource_set_implementation(xr, &xdg_surface_impl, xs, xdg_surface_gone);
}

static const struct xdg_wm_base_interface wm_impl = {
    .destroy = xdg_surface_destroy_request,
    .create_positioner = noop,
    .get_xdg_surface = wm_get_xdg_surface,
    .pong = noop,
};

static void bind_wm(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(r, &wm_impl, NULL, NULL);
}

// ---- wp_color_manager_v1

static void description_gone(struct wl_resource *r) {
    free(wl_resource_get_user_data(r));
}

static void send_description_info(struct wl_resource *info, struct description *description) {
    wp_image_description_info_v1_send_primaries(info, 640000, 330000, 300000, 600000,
                                                150000, 600000, 312700, 329000);
    wp_image_description_info_v1_send_primaries_named(info, description->primaries);
    wp_image_description_info_v1_send_tf_named(info, description->tf);
    wp_image_description_info_v1_send_luminances(info, 1, 400, 203);
    wp_image_description_info_v1_send_target_primaries(info, 640000, 330000, 300000, 600000,
                                                       150000, 600000, 312700, 329000);
    wp_image_description_info_v1_send_target_luminance(info, 1000, 1000);
    wp_image_description_info_v1_send_target_max_cll(info, 1000);
    wp_image_description_info_v1_send_target_max_fall(info, 400);
    printf("OUTPUT_INFO primaries=%u tf=%u max=%u reference=%u target=%u\n",
           description->primaries, description->tf, 400, 203, 1000);
    fflush(stdout);
    wp_image_description_info_v1_send_done(info);
    wl_resource_destroy(info);
}

static void description_get_information(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *info = wl_resource_create(c, &wp_image_description_info_v1_interface,
                                                  wl_resource_get_version(r), id);
    wl_resource_set_implementation(info, NULL, wl_resource_get_user_data(r), NULL);
    send_description_info(info, wl_resource_get_user_data(r));
}

static void description_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct wp_image_description_v1_interface description_impl = {
    .destroy = description_destroy,
    .get_information = description_get_information,
};

static struct wl_resource *new_description(struct wl_client *c, uint32_t id,
                                           uint32_t primaries, uint32_t tf) {
    struct description *description = calloc(1, sizeof(*description));
    description->primaries = primaries;
    description->tf = tf;
    struct wl_resource *r = wl_resource_create(c, &wp_image_description_v1_interface, 3, id);
    wl_resource_set_implementation(r, &description_impl, description, description_gone);
    wp_image_description_v1_send_ready2(r, 0, 1);
    return r;
}

static void color_output_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void color_output_get_image_description(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    // The compositor's output is a wide-gamut, HDR-capable display.
    new_description(c, id, 9 /* display_p3 */, 9 /* srgb */);
}

static const struct wp_color_management_output_v1_interface color_output_impl = {
    .destroy = color_output_destroy,
    .get_image_description = color_output_get_image_description,
};

static void color_output_gone(struct wl_resource *r) {}

static void manager_get_output(struct wl_client *c, struct wl_resource *r, uint32_t id,
                               struct wl_resource *output) {
    struct wl_resource *color_output = wl_resource_create(c, &wp_color_management_output_v1_interface,
                                                          wl_resource_get_version(r), id);
    wl_resource_set_implementation(color_output, &color_output_impl, NULL, color_output_gone);
}

static void color_surface_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void color_surface_set_image_description(struct wl_client *c, struct wl_resource *r,
                                                 struct wl_resource *description, uint32_t intent) {
    struct surface *surface = wl_resource_get_user_data(r);
    struct description *info = wl_resource_get_user_data(description);
    surface->primaries = info->primaries;
    surface->tf = info->tf;
    printf("SURFACE_COLOR %s primaries=%u tf=%u\n",
           surface->toplevel != NULL && surface->toplevel->title != NULL
                   ? surface->toplevel->title : "",
           info->primaries, info->tf);
    fflush(stdout);
}

static void color_surface_unset_image_description(struct wl_client *c, struct wl_resource *r) {
    (void) c;
    (void) r;
}

static const struct wp_color_management_surface_v1_interface color_surface_impl = {
    .destroy = color_surface_destroy,
    .set_image_description = color_surface_set_image_description,
    .unset_image_description = color_surface_unset_image_description,
};

static void color_surface_gone(struct wl_resource *r) {}

static void manager_get_surface(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                struct wl_resource *surface) {
    struct wl_resource *color_surface = wl_resource_create(c, &wp_color_management_surface_v1_interface,
                                                           wl_resource_get_version(r), id);
    wl_resource_set_implementation(color_surface, &color_surface_impl,
                                   wl_resource_get_user_data(surface), color_surface_gone);
}

static void feedback_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void feedback_get_preferred(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    printf("COLOR_FEEDBACK get_preferred identity=1\n");
    fflush(stdout);
    new_description(c, id, 9 /* display_p3 */, 9 /* srgb */);
}

static void feedback_get_preferred_parametric(struct wl_client *c, struct wl_resource *r,
                                              uint32_t id) {
    printf("COLOR_FEEDBACK get_preferred_parametric identity=1\n");
    fflush(stdout);
    new_description(c, id, 9 /* display_p3 */, 9 /* srgb */);
}

static const struct wp_color_management_surface_feedback_v1_interface feedback_impl = {
    .destroy = feedback_destroy,
    .get_preferred = feedback_get_preferred,
    .get_preferred_parametric = feedback_get_preferred_parametric,
};

static void feedback_gone(struct wl_resource *r) {}

static void manager_get_surface_feedback(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                         struct wl_resource *surface) {
    struct wl_resource *feedback =
            wl_resource_create(c, &wp_color_management_surface_feedback_v1_interface, 3, id);
    wl_resource_set_implementation(feedback, &feedback_impl,
                                   wl_resource_get_user_data(surface), feedback_gone);
}

static void creator_gone(struct wl_resource *r) {
    free(wl_resource_get_user_data(r));
}

static void creator_set_tf_named(struct wl_client *c, struct wl_resource *r, uint32_t tf) {
    ((struct creator *) wl_resource_get_user_data(r))->tf = tf;
}

static void creator_set_primaries_named(struct wl_client *c, struct wl_resource *r, uint32_t primaries) {
    ((struct creator *) wl_resource_get_user_data(r))->primaries = primaries;
}

static void creator_set_luminances(struct wl_client *c, struct wl_resource *r,
                                   uint32_t min, uint32_t max, uint32_t reference) {
    printf("HDR_LUMINANCES min=%u max=%u reference=%u\n", min, max, reference);
    fflush(stdout);
}

static void creator_set_max_cll(struct wl_client *c, struct wl_resource *r, uint32_t value) {
    printf("HDR_MAX_CLL %u\n", value);
    fflush(stdout);
}

static void creator_set_max_fall(struct wl_client *c, struct wl_resource *r, uint32_t value) {
    printf("HDR_MAX_FALL %u\n", value);
    fflush(stdout);
}

static void params_create(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct creator *creator = wl_resource_get_user_data(r);
    new_description(c, id, creator->primaries, creator->tf);
    wl_resource_destroy(r);
}

static const struct wp_image_description_creator_params_v1_interface params_impl = {
    .create = params_create,
    .set_tf_named = creator_set_tf_named,
    .set_primaries_named = creator_set_primaries_named,
    .set_luminances = creator_set_luminances,
    .set_max_cll = creator_set_max_cll,
    .set_max_fall = creator_set_max_fall,
};

static void manager_create_params(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *creator = wl_resource_create(c, &wp_image_description_creator_params_v1_interface,
                                                     wl_resource_get_version(r), id);
    wl_resource_set_implementation(creator, &params_impl, calloc(1, sizeof(struct creator)), creator_gone);
}

static void manager_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct wp_color_manager_v1_interface color_manager_impl = {
    .destroy = manager_destroy,
    .get_output = manager_get_output,
    .get_surface = manager_get_surface,
    .get_surface_feedback = manager_get_surface_feedback,
    .create_parametric_creator = manager_create_params,
};

static void bind_color_manager(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wp_color_manager_v1_interface, version, id);
    wl_resource_set_implementation(r, &color_manager_impl, NULL, NULL);
    wp_color_manager_v1_send_supported_intent(r, 0 /* perceptual */);
    wp_color_manager_v1_send_supported_feature(r, 1 /* parametric */);
    wp_color_manager_v1_send_supported_feature(r, 4 /* set_luminances */);
    wp_color_manager_v1_send_supported_primaries_named(r, 9 /* display_p3 */);
    wp_color_manager_v1_send_supported_tf_named(r, 9 /* srgb */);
    wp_color_manager_v1_send_done(r);
}

// ---- wp_color_representation_manager_v1

static void representation_surface_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void representation_surface_set_alpha(struct wl_client *c, struct wl_resource *r, uint32_t mode) {
    struct surface *surface = wl_resource_get_user_data(r);
    printf("SURFACE_ALPHA %s mode=%u\n",
           surface->toplevel != NULL && surface->toplevel->title != NULL
                   ? surface->toplevel->title : "",
           mode);
    fflush(stdout);
}

static const struct wp_color_representation_surface_v1_interface representation_surface_impl = {
    .destroy = representation_surface_destroy,
    .set_alpha_mode = representation_surface_set_alpha,
};

static void representation_surface_gone(struct wl_resource *r) {}

static void representation_get_surface(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                        struct wl_resource *surface) {
    struct wl_resource *client = wl_resource_create(c, &wp_color_representation_surface_v1_interface,
                                                    wl_resource_get_version(r), id);
    wl_resource_set_implementation(client, &representation_surface_impl,
                                   wl_resource_get_user_data(surface), representation_surface_gone);
}

static const struct wp_color_representation_manager_v1_interface representation_manager_impl = {
    .destroy = manager_destroy,
    .get_surface = representation_get_surface,
};

static void bind_representation_manager(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wp_color_representation_manager_v1_interface,
                                               version, id);
    wl_resource_set_implementation(r, &representation_manager_impl, NULL, NULL);
    wp_color_representation_manager_v1_send_supported_alpha_mode(r, 0 /* premultiplied_electrical */);
    wp_color_representation_manager_v1_send_done(r);
}

// ---- xdg_session_manager_v1

static void session_gone(struct wl_resource *r) {
    struct session *session = wl_resource_get_user_data(r);
    free(session->id);
    free(session);
}

static void session_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void toplevel_session_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void toplevel_session_rename(struct wl_client *c, struct wl_resource *r, const char *name) {}

static const struct xdg_toplevel_session_v1_interface toplevel_session_impl = {
    .destroy = toplevel_session_destroy,
    .rename = toplevel_session_rename,
};

static void session_add(struct wl_client *c, struct wl_resource *r, uint32_t id,
                        struct wl_resource *toplevel, const char *name, int restoring) {
    struct session *session = wl_resource_get_user_data(r);
    struct toplevel *client_toplevel = wl_resource_get_user_data(toplevel);
    int before_commit = client_toplevel->surface != NULL && client_toplevel->surface->commits == 0;
    printf("SESSION reason=%u id=%s op=%s name=%s before_commit=%d\n",
           session->reason, session->id, restoring ? "restore" : "add", name, before_commit);
    fflush(stdout);
    struct wl_resource *client = wl_resource_create(c, &xdg_toplevel_session_v1_interface, 1, id);
    wl_resource_set_implementation(client, &toplevel_session_impl, NULL, NULL);
    if (restoring)
        xdg_toplevel_session_v1_send_restored(client);
}

static void session_add_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                 struct wl_resource *toplevel, const char *name) {
    session_add(c, r, id, toplevel, name, 0);
}

static void session_restore_toplevel(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                     struct wl_resource *toplevel, const char *name) {
    session_add(c, r, id, toplevel, name, 1);
}

static const struct xdg_session_v1_interface session_impl = {
    .destroy = session_destroy,
    .remove = session_destroy,
    .add_toplevel = session_add_toplevel,
    .restore_toplevel = session_restore_toplevel,
};

static void manager_get_session(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                uint32_t reason, const char *requested_id) {
    struct session *session = calloc(1, sizeof(*session));
    session->reason = reason;
    session->id = strdup(requested_id != NULL ? requested_id : session_id);
    struct wl_resource *client = wl_resource_create(c, &xdg_session_v1_interface, 1, id);
    wl_resource_set_implementation(client, &session_impl, session, session_gone);
    xdg_session_v1_send_created(client, session_id);
}

static const struct xdg_session_manager_v1_interface session_manager_impl = {
    .destroy = manager_destroy,
    .get_session = manager_get_session,
};

static void bind_session_manager(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &xdg_session_manager_v1_interface, version, id);
    wl_resource_set_implementation(r, &session_manager_impl, NULL, NULL);
}

// ---- zwp_linux_dmabuf_v1

static void buffer_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct wl_buffer_interface buffer_impl = {
    .destroy = buffer_destroy,
};

static void buffer_gone(struct wl_resource *r) {}

static struct wl_resource *new_buffer(struct wl_client *c, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wl_buffer_interface, 1, id);
    wl_resource_set_implementation(r, &buffer_impl, NULL, buffer_gone);
    return r;
}

static void params_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void params_add(struct wl_client *c, struct wl_resource *r, int fd, uint32_t plane,
                       uint32_t offset, uint32_t stride, uint32_t hi, uint32_t lo) {
    (void) plane;
    (void) offset;
    (void) stride;
    (void) hi;
    (void) lo;
    if (fd >= 0)
        close(fd);
}

static void dmabuf_params_create(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                 int32_t width, int32_t height, uint32_t format, uint32_t flags) {
    new_buffer(c, id);
    printf("DMABUF_BUFFER %dx%d format=%u flags=%u\n", width, height, format, flags);
    fflush(stdout);
    wl_resource_destroy(r);
}

static void dmabuf_params_create_immed(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                       int32_t width, int32_t height, uint32_t format,
                                       uint32_t flags) {
    new_buffer(c, id);
    printf("DMABUF_BUFFER %dx%d format=%u flags=%u\n", width, height, format, flags);
    fflush(stdout);
    // Keep the params resource alive: our client leaves it around in case the compositor reports a
    // failed import, and sends destroy when it is done with the buffer.
}

static const struct zwp_linux_buffer_params_v1_interface dmabuf_params_impl = {
    .destroy = params_destroy,
    .add = params_add,
    .create = dmabuf_params_create,
    .create_immed = dmabuf_params_create_immed,
};

static void params_gone(struct wl_resource *r) {}

static void dmabuf_create_params(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *params = wl_resource_create(c, &zwp_linux_buffer_params_v1_interface, 4, id);
    wl_resource_set_implementation(params, &dmabuf_params_impl, NULL, params_gone);
}

static void dmabuf_feedback_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct zwp_linux_dmabuf_feedback_v1_interface dmabuf_feedback_impl = {
    .destroy = dmabuf_feedback_destroy,
};

static void send_dmabuf_feedback(struct wl_resource *feedback, int surface) {
    printf("DMABUF_FEEDBACK surface=%d entries=1\n", surface);
    fflush(stdout);

    // One packed table entry: DRM_FORMAT_ARGB8888 ('AR24') with the linear modifier.
    const uint8_t entry[12] = {'A', 'R', '2', '4', 0, 0, 0, 0, 0, 0, 0, 0};
    int fd = memfd_create("darling-dmabuf-feedback", MFD_CLOEXEC);
    if (fd >= 0 && write(fd, entry, sizeof(entry)) == sizeof(entry) && lseek(fd, 0, SEEK_SET) == 0) {
        zwp_linux_dmabuf_feedback_v1_send_format_table(feedback, fd, sizeof(entry));
        struct wl_array indices;
        wl_array_init(&indices);
        uint16_t zero = 0;
        memcpy(wl_array_add(&indices, sizeof(zero)), &zero, sizeof(zero));
        zwp_linux_dmabuf_feedback_v1_send_tranche_formats(feedback, &indices);
        wl_array_release(&indices);
        zwp_linux_dmabuf_feedback_v1_send_tranche_done(feedback);
    }
    if (fd >= 0)
        close(fd);
    zwp_linux_dmabuf_feedback_v1_send_done(feedback);
}

static void dmabuf_get_default_feedback(struct wl_client *c, struct wl_resource *r, uint32_t id) {
    struct wl_resource *feedback =
            wl_resource_create(c, &zwp_linux_dmabuf_feedback_v1_interface, 1, id);
    wl_resource_set_implementation(feedback, &dmabuf_feedback_impl, NULL, NULL);
    send_dmabuf_feedback(feedback, 0);
}

static void dmabuf_get_surface_feedback(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                        struct wl_resource *surface) {
    struct wl_resource *feedback =
            wl_resource_create(c, &zwp_linux_dmabuf_feedback_v1_interface, 1, id);
    wl_resource_set_implementation(feedback, &dmabuf_feedback_impl, NULL, NULL);
    send_dmabuf_feedback(feedback, 1);
}

static const struct zwp_linux_dmabuf_v1_interface dmabuf_impl = {
    .destroy = manager_destroy,
    .create_params = dmabuf_create_params,
    .get_default_feedback = dmabuf_get_default_feedback,
    .get_surface_feedback = dmabuf_get_surface_feedback,
};

static void bind_dmabuf(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &zwp_linux_dmabuf_v1_interface, version, id);
    wl_resource_set_implementation(r, &dmabuf_impl, NULL, NULL);
    zwp_linux_dmabuf_v1_send_format(r, 0x34325241 /* DRM_FORMAT_ARGB8888 */);
    zwp_linux_dmabuf_v1_send_modifier(r, 0x34325241, 0, 0);
}

// ---- wp_linux_drm_syncobj_manager_v1

static void syncobj_surface_destroy(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static void syncobj_set_acquire_point(struct wl_client *c, struct wl_resource *r,
                                      struct wl_resource *timeline, uint32_t hi, uint32_t lo) {
    printf("SYNCOBJ_ACQUIRE point=%u\n", lo);
    fflush(stdout);
}

static void syncobj_set_release_point(struct wl_client *c, struct wl_resource *r,
                                      struct wl_resource *timeline, uint32_t hi, uint32_t lo) {
    printf("SYNCOBJ_RELEASE point=%u\n", lo);
    fflush(stdout);
}

static const struct wp_linux_drm_syncobj_surface_v1_interface syncobj_surface_impl = {
    .destroy = syncobj_surface_destroy,
    .set_acquire_point = syncobj_set_acquire_point,
    .set_release_point = syncobj_set_release_point,
};

static void syncobj_surface_gone(struct wl_resource *r) {}

static void syncobj_get_surface(struct wl_client *c, struct wl_resource *r, uint32_t id,
                                struct wl_resource *surface) {
    struct wl_resource *client = wl_resource_create(c, &wp_linux_drm_syncobj_surface_v1_interface, 1, id);
    wl_resource_set_implementation(client, &syncobj_surface_impl, NULL, syncobj_surface_gone);
}

static void syncobj_import_timeline(struct wl_client *c, struct wl_resource *r, uint32_t id, int fd) {
    struct wl_resource *timeline =
            wl_resource_create(c, &wp_linux_drm_syncobj_timeline_v1_interface, 1, id);
    wl_resource_set_implementation(timeline, NULL, NULL, NULL);
    printf("SYNCOBJ_TIMELINE fd=%d\n", fd >= 0 ? 1 : 0);
    fflush(stdout);
    if (fd >= 0)
        close(fd);
}

static const struct wp_linux_drm_syncobj_manager_v1_interface syncobj_manager_impl = {
    .destroy = manager_destroy,
    .get_surface = syncobj_get_surface,
    .import_timeline = syncobj_import_timeline,
};

static void bind_syncobj(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wp_linux_drm_syncobj_manager_v1_interface, version, id);
    wl_resource_set_implementation(r, &syncobj_manager_impl, NULL, NULL);
}

// ---- wp_fifo_manager_v1

static void fifo_set_barrier(struct wl_client *c, struct wl_resource *r) {
    printf("FIFO_BARRIER set\n");
    fflush(stdout);
}

static void fifo_wait_barrier(struct wl_client *c, struct wl_resource *r) {
    printf("FIFO_BARRIER wait\n");
    fflush(stdout);
}

static void fifo_destroy_request(struct wl_client *c, struct wl_resource *r) {
    wl_resource_destroy(r);
}

static const struct wp_fifo_v1_interface fifo_impl = {
    .set_barrier = fifo_set_barrier,
    .wait_barrier = fifo_wait_barrier,
    .destroy = fifo_destroy_request,
};

static void fifo_gone(struct wl_resource *r) {}

static void fifo_get_fifo(struct wl_client *c, struct wl_resource *r, uint32_t id,
                          struct wl_resource *surface) {
    struct wl_resource *fifo = wl_resource_create(c, &wp_fifo_v1_interface, 1, id);
    wl_resource_set_implementation(fifo, &fifo_impl, NULL, fifo_gone);
}

static const struct wp_fifo_manager_v1_interface fifo_manager_impl = {
    .destroy = manager_destroy,
    .get_fifo = fifo_get_fifo,
};

static void bind_fifo(struct wl_client *c, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *r = wl_resource_create(c, &wp_fifo_manager_v1_interface, version, id);
    wl_resource_set_implementation(r, &fifo_manager_impl, NULL, NULL);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: wayland-color-session-server <socket name>\n");
        return 2;
    }
    display = wl_display_create();
    wl_display_init_shm(display);
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    wl_global_create(display, &xdg_wm_base_interface, 1, NULL, bind_wm);
    wl_global_create(display, &wp_color_manager_v1_interface, 3, NULL, bind_color_manager);
    wl_global_create(display, &wp_color_representation_manager_v1_interface, 1, NULL,
                     bind_representation_manager);
    wl_global_create(display, &xdg_session_manager_v1_interface, 1, NULL, bind_session_manager);
    wl_global_create(display, &zwp_linux_dmabuf_v1_interface, 4, NULL, bind_dmabuf);
    wl_global_create(display, &wp_linux_drm_syncobj_manager_v1_interface, 1, NULL, bind_syncobj);
    wl_global_create(display, &wp_fifo_manager_v1_interface, 1, NULL, bind_fifo);
    if (wl_display_add_socket(display, argv[1]) < 0) {
        fprintf(stderr, "cannot create socket %s\n", argv[1]);
        return 2;
    }
    printf("SERVER ready\n");
    fflush(stdout);
    wl_display_run(display);
    wl_display_destroy(display);
    return 0;
}
