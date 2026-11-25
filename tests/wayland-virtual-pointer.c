// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Test helper: a persistent wlr-virtual-pointer on the seat of the compositor in $WAYLAND_DISPLAY (a headless sway
// has no pointer device of its own). Prints READY, then for each "x y" line on stdin moves the pointer to that
// point of a 1920x1080 output, clicks the left button and prints CLICKED; for each "finger x y dy" line it moves
// the pointer there and scrolls vertically like a finger on a touchpad (axis source finger: two frames that
// move by dy, then an axis_stop frame) and prints SCROLLED; for each "drag x y dx dy" line it
// presses the left button at x, y, moves the pointer by dx, dy in eight steps, releases it and prints DRAGGED; for each "move x y" line it only moves the pointer there and prints MOVED.
// More commands, for tests that decode the pointer itself (each prints its name in capitals when it is done):
//   "abs x y" moves the pointer there (ABS); "rel dx dy" moves it by that much, which may be fractional (REL);
//   "button code state" presses (1) or releases (0) the Linux button with that code (BUTTON); "gap ms" waits (GAP);
//   "wheel axis steps" turns a mouse wheel by that many detents, 15 axis units each (WHEEL; axis 0 vertical, 1
//   horizontal); "axis axis value source" is one frame with that source (0 wheel, 1 finger, 2 continuous) (AXIS);
//   "stop axis source" is a frame that only says the axis stopped (STOP).
// Build: wayland-scanner client-header and private-code on wlr-virtual-pointer-unstable-v1.xml (wlr-protocols), then
// cc wayland-virtual-pointer.c wlr-virtual-pointer-unstable-v1.c -lwayland-client -lm
#define _GNU_SOURCE
#include <linux/input-event-codes.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
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

// Event timestamps are in milliseconds of a monotonic clock, as a real device's are: a client groups presses into
// double clicks by them
static uint32_t now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t) (ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}
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
    int x, y, dx, dy;
    uint32_t tick = now();
    char line[128];
    while (fgets(line, sizeof(line), stdin) != NULL) {
        if (sscanf(line, "drag %d %d %d %d", &x, &y, &dx, &dy) == 4) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, 1920, 1080);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            usleep(300000);
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            usleep(300000);
            for (int i = 1; i <= 8; i++) {
                zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x + dx * i / 8, y + dy * i / 8, 1920,
                                                        1080);
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                usleep(50000);
            }
            usleep(300000);
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            puts("DRAGGED");
            fflush(stdout);
            continue;
        }
        if (sscanf(line, "finger %d %d %d", &x, &y, &dy) == 3) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, tick += 10, x, y, 1920, 1080);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            usleep(300000);
            for (int i = 0; i < 2; i++) {
                zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
                zwlr_virtual_pointer_v1_axis(pointer, tick += 10, WL_POINTER_AXIS_VERTICAL_SCROLL,
                                             wl_fixed_from_int(dy));
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                usleep(100000);
            }
            zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_FINGER);
            zwlr_virtual_pointer_v1_axis_stop(pointer, tick += 10, WL_POINTER_AXIS_VERTICAL_SCROLL);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            puts("SCROLLED");
            fflush(stdout);
            continue;
        }
        if (sscanf(line, "move %d %d", &x, &y) == 2) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, 1920, 1080);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            puts("MOVED");
            fflush(stdout);
            continue;
        }
        {
            int a, b, c;
            double fx, fy;
            if (sscanf(line, "abs %d %d", &x, &y) == 2) {
                zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, 1920, 1080);
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("ABS");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "rel %lf %lf", &fx, &fy) == 2) {
                zwlr_virtual_pointer_v1_motion(pointer, now(), wl_fixed_from_double(fx), wl_fixed_from_double(fy));
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("REL");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "button %d %d", &a, &b) == 2) {
                zwlr_virtual_pointer_v1_button(pointer, now(), a,
                                               b ? WL_POINTER_BUTTON_STATE_PRESSED : WL_POINTER_BUTTON_STATE_RELEASED);
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("BUTTON");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "gap %d", &a) == 1) {
                usleep(a * 1000);
                puts("GAP");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "wheel %d %d", &a, &b) == 2) {
                zwlr_virtual_pointer_v1_axis_source(pointer, WL_POINTER_AXIS_SOURCE_WHEEL);
                zwlr_virtual_pointer_v1_axis_discrete(pointer, now(), a, wl_fixed_from_int(b * 15), b);
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("WHEEL");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "axis %d %lf %d", &a, &fx, &c) == 3) {
                zwlr_virtual_pointer_v1_axis_source(pointer, c);
                zwlr_virtual_pointer_v1_axis(pointer, now(), a, wl_fixed_from_double(fx));
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("AXIS");
                fflush(stdout);
                continue;
            }
            if (sscanf(line, "stop %d %d", &a, &c) == 2) {
                zwlr_virtual_pointer_v1_axis_source(pointer, c);
                zwlr_virtual_pointer_v1_axis_stop(pointer, now(), a);
                zwlr_virtual_pointer_v1_frame(pointer);
                wl_display_roundtrip(display);
                puts("STOP");
                fflush(stdout);
                continue;
            }
        }
        if (sscanf(line, "%d %d", &x, &y) != 2)
            break;
        zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), x, y, 1920, 1080);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        usleep(300000);
        zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        usleep(100000);
        zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
        zwlr_virtual_pointer_v1_frame(pointer);
        wl_display_roundtrip(display);
        puts("CLICKED");
        fflush(stdout);
    }
    return 0;
}
