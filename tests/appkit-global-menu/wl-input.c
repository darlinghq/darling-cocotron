// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// A pointer and a keyboard for a headless sway (or another wlroots compositor),
// through the virtual pointer and virtual keyboard protocols. Both devices
// stay for as long as the program runs, so the seat keeps its capabilities.
// Commands on stdin, one per line:
//   move X Y    put the pointer at X, Y (pixels of the output, WIDTH x HEIGHT)
//   click       press and release the left button
//   down, up    press, release the left button
//   key CODE    press and release the key with the evdev code CODE (Escape 1,
//               Return 28, Down 108)
//   quit
// Prints READY once the devices exist and ACK after each command.
// The protocol glue is generated from wl-input.xml by wayland-scanner.
// Build: see run-bar-tracking.py.
// Usage: wl-input WIDTH HEIGHT   (WAYLAND_DISPLAY names the compositor)
#define _GNU_SOURCE
#include "wl-input-client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <linux/input-event-codes.h>
#include <xkbcommon/xkbcommon.h>
#include <wayland-client.h>

static struct wl_seat *seat;
static struct zwlr_virtual_pointer_manager_v1 *pointer_manager;
static struct zwp_virtual_keyboard_manager_v1 *keyboard_manager;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_seat") && seat == NULL)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (!strcmp(interface, "zwlr_virtual_pointer_manager_v1"))
        pointer_manager = wl_registry_bind(registry, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
    else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
        keyboard_manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}

static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
}

static const struct wl_registry_listener listener = {global, global_remove};

static uint32_t now(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
    if (argc < 3)
        return 2;
    unsigned width = atoi(argv[1]), height = atoi(argv[2]);
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL)
        return 2;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (seat == NULL || pointer_manager == NULL || keyboard_manager == NULL)
        return 2;

    struct zwlr_virtual_pointer_v1 *pointer = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(pointer_manager, seat);
    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(keyboard_manager, seat);

    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, NULL, XKB_KEYMAP_COMPILE_NO_FLAGS);
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("keymap", 0);
    if (fd < 0 || ftruncate(fd, size) != 0)
        return 2;
    void *map = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    memcpy(map, text, size);
    munmap(map, size);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    wl_display_roundtrip(display);

    puts("READY");
    fflush(stdout);
    char line[128];
    while (fgets(line, sizeof line, stdin) != NULL) {
        double x, y;
        if (sscanf(line, "move %lf %lf", &x, &y) == 2) {
            zwlr_virtual_pointer_v1_motion_absolute(pointer, now(), (unsigned) x, (unsigned) y, width, height);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (strncmp(line, "click", 5) == 0) {
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
            zwlr_virtual_pointer_v1_frame(pointer);
            wl_display_roundtrip(display);
            usleep(60000);
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (strncmp(line, "down", 4) == 0) {
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (strncmp(line, "up", 2) == 0) {
            zwlr_virtual_pointer_v1_button(pointer, now(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
            zwlr_virtual_pointer_v1_frame(pointer);
        } else if (sscanf(line, "key %lf", &x) == 1) {
            zwp_virtual_keyboard_v1_key(keyboard, now(), (unsigned) x, WL_KEYBOARD_KEY_STATE_PRESSED);
            wl_display_roundtrip(display);
            usleep(60000);
            zwp_virtual_keyboard_v1_key(keyboard, now(), (unsigned) x, WL_KEYBOARD_KEY_STATE_RELEASED);
        } else if (strncmp(line, "quit", 4) == 0) {
            break;
        }
        wl_display_roundtrip(display);
        puts("ACK");
        fflush(stdout);
    }
    return 0;
}
