// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Test helper: a persistent wlr-virtual-pointer on the seat of the compositor in $WAYLAND_DISPLAY (a headless sway
// has no pointer device of its own). Prints READY, then for each "x y" line on stdin moves the pointer to that
// point of a 1920x1080 output, clicks the left button and prints CLICKED.
// Build: wayland-scanner client-header and private-code on wlr-virtual-pointer-unstable-v1.xml (wlr-protocols), then
// cc wayland-virtual-pointer.c wlr-virtual-pointer-unstable-v1.c -lwayland-client
#define _GNU_SOURCE
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *manager;

static void global(void *data, struct wl_registry *registry, uint32_t id, const char *name, uint32_t version) {
    if (!strcmp(name, "wl_seat"))
        seat = wl_registry_bind(registry, id, &wl_seat_interface, 1);
    else if (!strcmp(name, "zwlr_virtual_pointer_manager_v1"))
        manager = wl_registry_bind(registry, id, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t id) {}
static const struct wl_registry_listener listener = {global, global_remove};

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "no Wayland display\n");
        return 2;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager) {
        fprintf(stderr, "no seat or virtual pointer manager\n");
        return 2;
    }
    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
    wl_display_roundtrip(display);
    puts("READY");
    fflush(stdout);
    int x, y;
    uint32_t time = 0;
    while (scanf("%d %d", &x, &y) == 2) {
        zwlr_virtual_pointer_v1_motion_absolute(pointer, time += 10, x, y, 1920, 1080);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        usleep(300000);
        zwlr_virtual_pointer_v1_button(pointer, time += 10, BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        usleep(100000);
        zwlr_virtual_pointer_v1_button(pointer, time += 10, BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        puts("CLICKED");
        fflush(stdout);
    }
    return 0;
}
