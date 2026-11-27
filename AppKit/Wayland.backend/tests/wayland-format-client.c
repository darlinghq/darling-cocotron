/*
  Copyright (C) 2026 Lubos Dolezel

  Licensed under the MIT license, the same as the rest of this project.
*/
// Guest-side client for the "formats" scenario of wayland-color-session-server. It reads the
// dma-buf surface feedback table and checks that the compositor can advertise both ordinary
// ARGB8888 and half-float ARGB16161616F/XRGB16161616F buffers with a linear modifier. The table
// layout is the one in linux-dmabuf-v1.xml: a 32-bit format, 32 bits of padding, a 64-bit
// modifier.
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
#include "linux-dmabuf-v1-client-protocol.h"

#define DRM_FORMAT_ARGB8888 0x34325241u
#define DRM_FORMAT_XRGB8888 0x34325258u
#define DRM_FORMAT_ARGB16161616F 0x48345241u
#define DRM_FORMAT_XRGB16161616F 0x48345258u
#define DRM_FORMAT_MOD_LINEAR 0ULL

struct format_entry {
    uint32_t format;
    uint32_t padding;
    uint64_t modifier;
} __attribute__((packed));

static struct wl_compositor *compositor;
static struct zwp_linux_dmabuf_v1 *dmabuf;
static uint8_t *table;
static uint32_t tableSize;
static uint32_t expected[] = {
    DRM_FORMAT_ARGB8888, DRM_FORMAT_XRGB8888,
    DRM_FORMAT_ARGB16161616F, DRM_FORMAT_XRGB16161616F,
};
static uint32_t seen;
static int complete;

static void registryGlobal(void *data, struct wl_registry *registry, uint32_t name,
                           const char *interface, uint32_t version) {
    (void) data;
    if (strcmp(interface, "wl_compositor") == 0)
        compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (strcmp(interface, "zwp_linux_dmabuf_v1") == 0)
        dmabuf = wl_registry_bind(registry, name, &zwp_linux_dmabuf_v1_interface,
                                  version < 4 ? version : 4);
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

static void feedbackDone(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback) {
    (void) data;
    (void) feedback;
    complete = 1;
}

static void formatTable(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback, int32_t fd,
                        uint32_t size) {
    (void) data;
    (void) feedback;
    free(table);
    table = NULL;
    tableSize = 0;
    if (fd < 0 || size < sizeof(struct format_entry) || size % sizeof(struct format_entry) != 0)
        return;
    uint8_t *bytes = malloc(size);
    size_t total = 0;
    while (total < size) {
        ssize_t count = read(fd, bytes + total, size - total);
        if (count <= 0)
            break;
        total += (size_t) count;
    }
    if (total == size) {
        table = bytes;
        tableSize = size;
    } else {
        free(bytes);
    }
}

static void mainDevice(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback,
                       struct wl_array *device) {
    (void) data;
    (void) feedback;
    (void) device;
}

static void trancheDone(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback) {
    (void) data;
    (void) feedback;
}

static void trancheTargetDevice(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback,
                                struct wl_array *device) {
    (void) data;
    (void) feedback;
    (void) device;
}

static void trancheFormats(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback,
                           struct wl_array *indices) {
    (void) data;
    (void) feedback;
    uint16_t *index = indices->data;
    for (size_t i = 0; i < indices->size / sizeof(*index); i++) {
        if ((size_t) index[i] * sizeof(struct format_entry) + sizeof(struct format_entry) > tableSize)
            continue;
        struct format_entry entry;
        memcpy(&entry, table + (size_t) index[i] * sizeof(entry), sizeof(entry));
        printf("CLIENT_FORMAT index=%u format=%08" PRIx32 " modifier=%016" PRIx64 "\n",
               index[i], entry.format, entry.modifier);
        if (seen < sizeof(expected) / sizeof(expected[0]) &&
            entry.format == expected[seen] && entry.modifier == DRM_FORMAT_MOD_LINEAR)
            seen++;
    }
}

static void trancheFlags(void *data, struct zwp_linux_dmabuf_feedback_v1 *feedback,
                         uint32_t flags) {
    (void) data;
    (void) feedback;
    (void) flags;
}

static const struct zwp_linux_dmabuf_feedback_v1_listener feedbackListener = {
    .done = feedbackDone,
    .format_table = formatTable,
    .main_device = mainDevice,
    .tranche_done = trancheDone,
    .tranche_target_device = trancheTargetDevice,
    .tranche_formats = trancheFormats,
    .tranche_flags = trancheFlags,
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
    if (compositor == NULL || dmabuf == NULL) {
        fprintf(stderr, "missing wl_compositor or zwp_linux_dmabuf_v1\n");
        return 2;
    }

    struct wl_surface *surface = wl_compositor_create_surface(compositor);
    struct zwp_linux_dmabuf_feedback_v1 *feedback =
        zwp_linux_dmabuf_v1_get_surface_feedback(dmabuf, surface);
    if (feedback == NULL || zwp_linux_dmabuf_feedback_v1_add_listener(feedback, &feedbackListener,
                                                                     NULL) < 0)
        return 2;
    wl_display_flush(display);

    time_t deadline = time(NULL) + 5;
    while (!complete && time(NULL) < deadline) {
        wl_display_dispatch_pending(display);
        struct pollfd pfd = {.fd = wl_display_get_fd(display), .events = POLLIN};
        if (poll(&pfd, 1, 100) <= 0)
            continue;
        if (wl_display_dispatch(display) < 0)
            break;
    }

    printf("CLIENT done entries=%u\n", seen);
    fflush(stdout);
    int status = complete && seen == sizeof(expected) / sizeof(expected[0]) ? 0 : 1;
    free(table);
    zwp_linux_dmabuf_feedback_v1_destroy(feedback);
    wl_surface_destroy(surface);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    return status;
}
