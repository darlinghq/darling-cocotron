/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// Guest-side client for the "surface" scenario of wayland-color-session-server. It stands in for
// three surfaces of a window: the toplevel and two OpenGL subwindows. Each one gets its own color-management surface and feedback. When the compositor
// changes the preferred description, every surface independently chooses a new description with
// BT.2020/PQ HDR metadata; the server logs show which surface made which choice.
#define _GNU_SOURCE
#include <inttypes.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "color-management-v1-client-protocol.h"

struct client_surface {
    const char *label;
    struct wl_surface *surface;
    struct wp_color_management_surface_v1 *color;
    struct wp_color_management_surface_feedback_v1 *feedback;
    uint32_t id;
    int changes;
};

static struct wl_compositor *compositor;
static struct wp_color_manager_v1 *colorManager;
static struct client_surface surfaces[3];
static int totalChanges;

static void registryGlobal(void *data, struct wl_registry *registry, uint32_t name,
                           const char *interface, uint32_t version) {
    (void) data;
    if (strcmp(interface, "wl_compositor") == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, "wp_color_manager_v1") == 0)
        colorManager = wl_registry_bind(registry, name, &wp_color_manager_v1_interface, 3);
}

static void registryGlobalRemove(void *data, struct wl_registry *registry, uint32_t name) {
    (void) data;
    (void) registry;
    (void) name;
}

static const struct wl_registry_listener registryListener = {
    .global = registryGlobal,
    .global_remove = registryGlobalRemove,
};

static void chooseDescription(struct client_surface *surface, int hdr) {
    struct wp_image_description_creator_params_v1 *creator =
            wp_color_manager_v1_create_parametric_creator(colorManager);
    if (creator == NULL)
        return;
    wp_image_description_creator_params_v1_set_primaries_named(creator, hdr ? 6 : 9);
    wp_image_description_creator_params_v1_set_tf_named(creator, hdr ? 11 : 9);
    wp_image_description_creator_params_v1_set_luminances(creator, hdr ? 50 : 1,
                                                           hdr ? 1000 : 400, 203);
    wp_image_description_creator_params_v1_set_max_cll(creator, hdr ? 2000 : 1000);
    wp_image_description_creator_params_v1_set_max_fall(creator, hdr ? 500 : 400);
    struct wp_image_description_v1 *description =
            wp_image_description_creator_params_v1_create(creator);
    if (description != NULL) {
        wp_color_management_surface_v1_set_image_description(surface->color, description, 0);
        wp_image_description_v1_destroy(description);
    }
}

static void changed(struct client_surface *surface, uint64_t identity) {
    printf("CLIENT_CHANGED label=%s identity=%" PRIu64 "\n", surface->label, identity);
    // The first event captures the identity of the description we already requested. Only the
    // compositor's later announcement is a change that needs a new description.
    if (identity == 2)
        return;
    surface->changes++;
    totalChanges++;
    chooseDescription(surface, 1);
    wp_color_management_surface_feedback_v1_get_preferred_parametric(surface->feedback);
    wl_display_flush(wl_proxy_get_display((struct wl_proxy *) surface->surface));
}

static void preferredChangedOld(void *data,
                                struct wp_color_management_surface_feedback_v1 *feedback,
                                uint32_t identity) {
    (void) feedback;
    changed((struct client_surface *) data, identity);
}

static void preferredChanged(void *data,
                             struct wp_color_management_surface_feedback_v1 *feedback,
                             uint32_t identityHigh, uint32_t identityLow) {
    (void) feedback;
    changed((struct client_surface *) data, ((uint64_t) identityHigh << 32) | identityLow);
}

static const struct wp_color_management_surface_feedback_v1_listener feedbackListener = {
    .preferred_changed = preferredChangedOld,
    .preferred_changed2 = preferredChanged,
};

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "cannot connect\n");
        return 2;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, NULL);
    wl_display_roundtrip(display);
    if (compositor == NULL || colorManager == NULL) {
        fprintf(stderr, "missing wl_compositor or wp_color_manager_v1\n");
        return 2;
    }

    static const char *labels[3] = {"parent", "opengl", "second"};
    for (size_t i = 0; i < 3; i++) {
        struct client_surface *surface = &surfaces[i];
        surface->label = labels[i];
        surface->surface = wl_compositor_create_surface(compositor);
        surface->id = wl_proxy_get_id((struct wl_proxy *) surface->surface);
        surface->color = wp_color_manager_v1_get_surface(colorManager, surface->surface);
        surface->feedback = wp_color_manager_v1_get_surface_feedback(colorManager, surface->surface);
        if (surface->color == NULL || surface->feedback == NULL)
            return 2;
        wp_color_management_surface_feedback_v1_add_listener(surface->feedback, &feedbackListener,
                                                             surface);
        printf("CLIENT_SURFACE label=%s id=%" PRIu32 "\n", surface->label, surface->id);
        chooseDescription(surface, 0);
        wp_color_management_surface_feedback_v1_get_preferred_parametric(surface->feedback);
    }
    wl_display_flush(display);
    wl_display_roundtrip(display);

    time_t deadline = time(NULL) + 5;
    while (totalChanges < 3 && time(NULL) < deadline) {
        wl_display_dispatch_pending(display);
        struct pollfd pfd = {.fd = wl_display_get_fd(display), .events = POLLIN};
        if (poll(&pfd, 1, 100) <= 0)
            continue;
        if (wl_display_dispatch(display) < 0)
            break;
    }
    // Wait until the compositor has processed the last surface's new description before exiting.
    wl_display_roundtrip(display);
    printf("CLIENT done changes=%d\n", totalChanges);
    fflush(stdout);
    wl_display_disconnect(display);
    return totalChanges == 3 ? 0 : 1;
}
