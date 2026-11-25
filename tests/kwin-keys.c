// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// Key injector for the tests that run on KWin, which has no virtual keyboard protocol: KWin offers the key
// requests of org_kde_kwin_fake_input to a client that authenticates (kwin-fake-input.xml describes that
// interface of KDE's public protocol as far as it is used here). Needs a KWin whose settings allow it (a
// private kwin_wayland --virtual does).
// Build on the host:
//   wayland-scanner client-header kwin-fake-input.xml fake-input-client-protocol.h
//   wayland-scanner private-code kwin-fake-input.xml fake-input-protocol.c
//   cc -o kwin-keys kwin-keys.c fake-input-protocol.c -lwayland-client
// kwin-keys <delay-ms> <evdev-key-code:state|wNNN> ...: injects keys into KWin through its fake input protocol
// (state 1 = press, 0 = release), waiting <delay-ms> between the events.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "fake-input-client-protocol.h"

static struct org_kde_kwin_fake_input *fake;
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (strcmp(interface, "org_kde_kwin_fake_input") == 0)
        fake = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface, 4);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener listener = {global, global_remove};

int main(int argc, char **argv) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!fake) { fprintf(stderr, "no fake input\n"); return 2; }
    org_kde_kwin_fake_input_authenticate(fake, "keyboard-test", "test input");
    wl_display_roundtrip(display);
    int delay = atoi(argv[1]);
    for (int i = 2; i < argc; i++) {
        if (argv[i][0] == 'w') { // wNNN: wait NNN ms
            usleep(atol(argv[i] + 1) * 1000);
            continue;
        }
        unsigned code, state;
        if (sscanf(argv[i], "%u:%u", &code, &state) != 2) return 3;
        org_kde_kwin_fake_input_keyboard_key(fake, code, state);
        wl_display_roundtrip(display);
        usleep(delay * 1000);
    }
    wl_display_roundtrip(display);
    return 0;
}
