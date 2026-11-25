/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// Native Linux key injector for compositors with the virtual keyboard protocol (sway, other wlroots ones),
// with the same command line as kwin-keys.c: virtual-keyboard-keys <delay-ms> <evdev-key-code>:<1|0>...
// presses (1) or releases (0) the evdev key codes (KEY_A is 30) and waits <delay-ms> after each event; wNNN
// waits NNN ms. The keyboard has the keymap of the "us" XKB layout, so a key has its usual key code (unlike
// the keys of wtype, which has a keymap of its own), and the helper reports the modifier state of the
// modifier keys and Caps Lock to the compositor.
// The keyboard exists for the length of the run; the seat gains the keyboard capability when it starts, so
// the first events are sent after a pause of 300 ms to let a client bind its keyboard.
// Build: wayland-scanner client-header wayland-virtual-keyboard.xml virtual-keyboard-client.h, private-code
// into virtual-keyboard-protocol.c, and cc -o virtual-keyboard-keys virtual-keyboard-keys.c
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

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <delay ms> <code>:<1|0>|w<ms>...\n", argv[0]);
        return 2;
    }
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
    struct xkb_rule_names names = {.layout = "us"};
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (keymap == NULL)
        return 2;
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    size_t size = strlen(text) + 1;
    int fd = memfd_create("keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, text, size) != (ssize_t) size)
        return 2;
    struct zwp_virtual_keyboard_v1 *keyboard = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
    close(fd);
    free(text);
    xkb_keymap_unref(keymap);
    wl_display_roundtrip(display);
    usleep(300000);

    uint32_t depressed = 0, locked = 0;
    long delay = atol(argv[1]);
    for (int i = 2; i < argc; i++) {
        if (argv[i][0] == 'w') { // wNNN: wait NNN ms
            usleep(atol(argv[i] + 1) * 1000);
            continue;
        }
        unsigned code, down;
        if (sscanf(argv[i], "%u:%u", &code, &down) != 2)
            return 2;
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        zwp_virtual_keyboard_v1_key(keyboard, now.tv_sec * 1000 + now.tv_nsec / 1000000, code, down);
        // A virtual keyboard does not make the compositor derive the modifier state from the keys: the client
        // reports it (the bits of the "us" keymap: Shift 1, Caps Lock 2, Control 4, Alt 8, Super 64).
        uint32_t bit = code == 42 || code == 54 ? 1 : code == 29 || code == 97 ? 4 : code == 56 || code == 100 ? 8 : code == 125 || code == 126 ? 64 : 0;
        if (bit != 0) {
            depressed = down ? depressed | bit : depressed & ~bit;
            zwp_virtual_keyboard_v1_modifiers(keyboard, depressed, 0, locked, 0);
        } else if (code == 58 && down) {
            locked ^= 2;
            zwp_virtual_keyboard_v1_modifiers(keyboard, depressed, 0, locked, 0);
        }
        wl_display_roundtrip(display);
        usleep(delay * 1000);
    }
    usleep(100000);
    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_display_roundtrip(display);
    return 0;
}
