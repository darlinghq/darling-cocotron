/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A minimal compositor with one output that offers wlr-output-management-unstable-v1, for
// wlr-output-mode-switch.sh: it lists several modes, tests and applies configurations,
// and prints what happens ("APPLIED 1024x768@60000", "TESTED ...") so the runner can check
// the sequence of modes. It renders nothing. With the argument "cancel-once" the first
// configuration is answered with "cancelled" after the serial moved on (an output state
// change between the client's last done event and its request), which a client has to retry.
// The mode in effect when it exits is printed as "FINAL WxH@R".
#include <wayland-server.h>
#include "wlr-output-management-unstable-v1-server.h"
#include "xdg-shell-server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

struct mode {
    int width, height, refresh;
    int preferred;
    struct wl_resource *resource; // the mode object of the (single) bound manager's head
};

static struct mode modes[] = {
    {1280, 720, 60000, 1, NULL},
    {1024, 768, 60000, 0, NULL},
    {1024, 768, 75000, 0, NULL},
    {800, 600, 60000, 0, NULL},
};
#define MODE_COUNT (sizeof modes / sizeof modes[0])

static struct wl_display *display;
static struct wl_resource *outputs[8], *managers[8], *heads[8];
static int output_count, manager_count;
static struct mode *current = &modes[0];
static uint32_t serial = 1;
static int cancel_once;

struct configuration {
    struct wl_resource *resource;
    uint32_t serial;
    int head_configured;
    struct mode *mode; // NULL: keep the current one
    int used;
};

static void destroy_resource(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static void send_output_state(struct wl_resource *output) {
    wl_output_send_geometry(output, 0, 0, 340, 190, WL_OUTPUT_SUBPIXEL_UNKNOWN, "fixture", "output",
                            WL_OUTPUT_TRANSFORM_NORMAL);
    for (size_t i = 0; i < MODE_COUNT; i++)
        wl_output_send_mode(output, &modes[i] == current ? WL_OUTPUT_MODE_CURRENT : 0, modes[i].width,
                            modes[i].height, modes[i].refresh);
    wl_output_send_scale(output, 1);
    wl_output_send_done(output);
}

static void head_release(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}
static const struct zwlr_output_head_v1_interface head_impl = {head_release};
static void mode_release(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}
static const struct zwlr_output_mode_v1_interface mode_impl = {mode_release};

static void announce_head(struct wl_client *client, struct wl_resource *manager) {
    struct wl_resource *head = wl_resource_create(client, &zwlr_output_head_v1_interface,
                                                  wl_resource_get_version(manager), 0);
    wl_resource_set_implementation(head, &head_impl, NULL, NULL);
    heads[manager_count - 1] = head;
    zwlr_output_manager_v1_send_head(manager, head);
    zwlr_output_head_v1_send_name(head, "FIXTURE-1");
    zwlr_output_head_v1_send_description(head, "Fixture output");
    zwlr_output_head_v1_send_physical_size(head, 340, 190);
    for (size_t i = 0; i < MODE_COUNT; i++) {
        struct wl_resource *mode = wl_resource_create(client, &zwlr_output_mode_v1_interface,
                                                      wl_resource_get_version(manager), 0);
        wl_resource_set_implementation(mode, &mode_impl, NULL, NULL);
        modes[i].resource = mode;
        zwlr_output_head_v1_send_mode(head, mode);
        zwlr_output_mode_v1_send_size(mode, modes[i].width, modes[i].height);
        zwlr_output_mode_v1_send_refresh(mode, modes[i].refresh);
        if (modes[i].preferred)
            zwlr_output_mode_v1_send_preferred(mode);
    }
    zwlr_output_head_v1_send_enabled(head, 1);
    zwlr_output_head_v1_send_current_mode(head, current->resource);
    zwlr_output_head_v1_send_position(head, 0, 0);
    zwlr_output_head_v1_send_transform(head, WL_OUTPUT_TRANSFORM_NORMAL);
    zwlr_output_head_v1_send_scale(head, wl_fixed_from_int(1));
    zwlr_output_manager_v1_send_done(manager, serial);
}

// Configuration head: only the mode matters here.
static void config_head_set_mode(struct wl_client *client, struct wl_resource *resource,
                                 struct wl_resource *mode) {
    struct configuration *configuration = wl_resource_get_user_data(resource);
    for (size_t i = 0; i < MODE_COUNT; i++)
        if (modes[i].resource == mode)
            configuration->mode = &modes[i];
}
static void config_head_set_custom_mode(struct wl_client *c, struct wl_resource *r, int32_t w, int32_t h,
                                        int32_t refresh) {}
static void config_head_set_position(struct wl_client *c, struct wl_resource *r, int32_t x, int32_t y) {}
static void config_head_set_transform(struct wl_client *c, struct wl_resource *r, int32_t t) {}
static void config_head_set_scale(struct wl_client *c, struct wl_resource *r, wl_fixed_t scale) {}
static void config_head_set_adaptive_sync(struct wl_client *c, struct wl_resource *r, uint32_t state) {}
static const struct zwlr_output_configuration_head_v1_interface config_head_impl = {
    config_head_set_mode, config_head_set_custom_mode, config_head_set_position,
    config_head_set_transform, config_head_set_scale, config_head_set_adaptive_sync,
};

static void configuration_enable_head(struct wl_client *client, struct wl_resource *resource, uint32_t id,
                                      struct wl_resource *head) {
    struct configuration *configuration = wl_resource_get_user_data(resource);
    if (configuration->head_configured) {
        wl_resource_post_error(resource, ZWLR_OUTPUT_CONFIGURATION_V1_ERROR_ALREADY_CONFIGURED_HEAD,
                               "head configured twice");
        return;
    }
    configuration->head_configured = 1;
    struct wl_resource *child = wl_resource_create(client, &zwlr_output_configuration_head_v1_interface,
                                                   wl_resource_get_version(resource), id);
    wl_resource_set_implementation(child, &config_head_impl, configuration, NULL);
}
static void configuration_disable_head(struct wl_client *client, struct wl_resource *resource,
                                       struct wl_resource *head) {
    struct configuration *configuration = wl_resource_get_user_data(resource);
    configuration->head_configured = 1;
    puts("DISABLED");
    fflush(stdout);
}

static void configuration_finish(struct wl_resource *resource, int apply) {
    struct configuration *configuration = wl_resource_get_user_data(resource);
    if (configuration->used) {
        wl_resource_post_error(resource, ZWLR_OUTPUT_CONFIGURATION_V1_ERROR_ALREADY_USED, "used twice");
        return;
    }
    configuration->used = 1;
    if (!configuration->head_configured) {
        wl_resource_post_error(resource, ZWLR_OUTPUT_CONFIGURATION_V1_ERROR_UNCONFIGURED_HEAD,
                               "head not configured");
        return;
    }
    if (cancel_once || configuration->serial != serial) {
        // The client's information is outdated: bump the serial and tell it the new state.
        cancel_once = 0;
        serial++;
        zwlr_output_configuration_v1_send_cancelled(resource);
        for (int i = 0; i < manager_count; i++)
            zwlr_output_manager_v1_send_done(managers[i], serial);
        puts("CANCELLED");
        fflush(stdout);
        return;
    }
    struct mode *mode = configuration->mode ? configuration->mode : current;
    printf("%s %dx%d@%d\n", apply ? "APPLY" : "TESTED", mode->width, mode->height, mode->refresh);
    if (apply && mode != current) {
        current = mode;
        serial++;
        for (int i = 0; i < manager_count; i++) {
            zwlr_output_head_v1_send_current_mode(heads[i], current->resource);
            zwlr_output_manager_v1_send_done(managers[i], serial);
        }
        for (int i = 0; i < output_count; i++)
            send_output_state(outputs[i]);
        printf("APPLIED %dx%d@%d\n", mode->width, mode->height, mode->refresh);
    }
    zwlr_output_configuration_v1_send_succeeded(resource);
    fflush(stdout);
}
static void configuration_apply(struct wl_client *client, struct wl_resource *resource) {
    configuration_finish(resource, 1);
}
static void configuration_test(struct wl_client *client, struct wl_resource *resource) {
    configuration_finish(resource, 0);
}
static void configuration_destroy_request(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}
static const struct zwlr_output_configuration_v1_interface configuration_impl = {
    configuration_enable_head, configuration_disable_head, configuration_apply, configuration_test,
    configuration_destroy_request,
};
static void configuration_free(struct wl_resource *resource) {
    free(wl_resource_get_user_data(resource));
}

static void manager_create_configuration(struct wl_client *client, struct wl_resource *resource, uint32_t id,
                                         uint32_t config_serial) {
    struct configuration *configuration = calloc(1, sizeof *configuration);
    configuration->serial = config_serial;
    configuration->resource = wl_resource_create(client, &zwlr_output_configuration_v1_interface,
                                                 wl_resource_get_version(resource), id);
    wl_resource_set_implementation(configuration->resource, &configuration_impl, configuration, configuration_free);
}
static void manager_stop(struct wl_client *client, struct wl_resource *resource) {
    zwlr_output_manager_v1_send_finished(resource);
    wl_resource_destroy(resource);
}
static const struct zwlr_output_manager_v1_interface manager_impl = {
    manager_create_configuration, manager_stop,
};
static void bind_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &zwlr_output_manager_v1_interface, version, id);
    wl_resource_set_implementation(resource, &manager_impl, NULL, NULL);
    managers[manager_count++] = resource;
    announce_head(client, resource);
}

static const struct wl_output_interface output_impl = {destroy_resource};
static void bind_output(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wl_output_interface, version, id);
    wl_resource_set_implementation(resource, &output_impl, NULL, NULL);
    outputs[output_count++] = resource;
    send_output_state(resource);
}

static const struct wl_surface_interface surface_impl = {.destroy = destroy_resource};
static void create_surface(struct wl_client *client, struct wl_resource *resource, uint32_t id) {
    struct wl_resource *surface = wl_resource_create(client, &wl_surface_interface,
                                                     wl_resource_get_version(resource), id);
    wl_resource_set_implementation(surface, &surface_impl, NULL, NULL);
}
static const struct wl_compositor_interface compositor_impl = {.create_surface = create_surface};
static void bind_compositor(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &wl_compositor_interface, version, id);
    wl_resource_set_implementation(resource, &compositor_impl, NULL, NULL);
}
static const struct xdg_wm_base_interface wm_impl = {.destroy = destroy_resource};
static void bind_wm(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_resource *resource = wl_resource_create(client, &xdg_wm_base_interface, version, id);
    wl_resource_set_implementation(resource, &wm_impl, NULL, NULL);
}

static void terminate(int signal) {
    printf("FINAL %dx%d@%d\n", current->width, current->height, current->refresh);
    fflush(stdout);
    wl_display_terminate(display);
}

int main(int argc, char **argv) {
    cancel_once = argc > 1 && strcmp(argv[1], "cancel-once") == 0;
    display = wl_display_create();
    if (!display)
        return 2;
    wl_global_create(display, &wl_compositor_interface, 4, NULL, bind_compositor);
    wl_display_init_shm(display);
    wl_global_create(display, &xdg_wm_base_interface, 1, NULL, bind_wm);
    wl_global_create(display, &wl_output_interface, 2, NULL, bind_output);
    wl_global_create(display, &zwlr_output_manager_v1_interface, 4, NULL, bind_manager);
    const char *socket = wl_display_add_socket_auto(display);
    if (!socket)
        return 2;
    signal(SIGTERM, terminate);
    signal(SIGINT, terminate);
    printf("READY %s\n", socket);
    fflush(stdout);
    wl_display_run(display);
    wl_display_destroy_clients(display);
    wl_display_destroy(display);
    return 0;
}
