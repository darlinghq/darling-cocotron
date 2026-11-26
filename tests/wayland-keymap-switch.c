/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// Native Linux fixture for compositors with the virtual keyboard protocol (sway, other wlroots ones):
// creates a keyboard for the seat and, on command, gives it the keymap of an XKB layout and presses a
// key. A compositor sends the keymap of the keyboard that is used to every client that has the keyboard
// focus, so the clients see the keymap change.
//
// Commands on standard input, one per line:
//   layout NAME   upload the keymap of the XKB layout NAME (us, de, ...)
//   key CODE      press and release the evdev key CODE (KEY_Y is 21)
//   quit
// Prints KEYBOARD_READY when the keyboard exists and "DONE <command>" after each command.
// Build: wayland-scanner client-header wayland-virtual-keyboard.xml virtual-keyboard-client.h, private-code
// into virtual-keyboard-protocol.c, and cc -o wayland-keymap-switch wayland-keymap-switch.c
// virtual-keyboard-protocol.c -lwayland-client -lxkbcommon.
#define _GNU_SOURCE
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;

static void global(void *data, struct wl_registry *registry, uint32_t id, const char *name, uint32_t version) {
    if (!strcmp(name, "wl_seat") && seat == NULL)
        seat = wl_registry_bind(registry, id, &wl_seat_interface, 1);
    else if (!strcmp(name, "zwp_virtual_keyboard_manager_v1"))
        manager = wl_registry_bind(registry, id, &zwp_virtual_keyboard_manager_v1_interface, 1);
}

static void removed(void *data, struct wl_registry *registry, uint32_t id) {}

static const struct wl_registry_listener listener = {global, removed};

static int uploadLayout(struct zwp_virtual_keyboard_v1 *keyboard, struct xkb_context *context, const char *layout) {
    struct xkb_rule_names names = {.layout = layout};
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (keymap == NULL)
        return -1;
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t) size)
        return -1;
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    close(fd);
    free(text);
    xkb_keymap_unref(keymap);
    return 0;
}

static void press(struct zwp_virtual_keyboard_v1 *keyboard, unsigned code) {
    for (int down = 1; down >= 0; down--) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        zwp_virtual_keyboard_v1_key(keyboard, now.tv_sec * 1000 + now.tv_nsec / 1000000, code, down);
        usleep(50000);
    }
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "no compositor\n");
        return 2;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (seat == NULL || manager == NULL) {
        fprintf(stderr, "the compositor has no virtual keyboard protocol\n");
        return 2;
    }
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    if (uploadLayout(keyboard, context, "us") != 0)
        return 2;
    wl_display_roundtrip(display);
    puts("KEYBOARD_READY");
    fflush(stdout);

    char line[128];
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\n")] = 0;
        char arg[64];
        unsigned code;
        if (sscanf(line, "layout %63s", arg) == 1) {
            if (uploadLayout(keyboard, context, arg) != 0) {
                printf("ERROR %s\n", line);
                fflush(stdout);
                continue;
            }
        } else if (sscanf(line, "key %u", &code) == 1) {
            press(keyboard, code);
        } else if (!strcmp(line, "quit")) {
            break;
        }
        wl_display_roundtrip(display);
        printf("DONE %s\n", line);
        fflush(stdout);
    }
    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_display_roundtrip(display);
    return 0;
}
