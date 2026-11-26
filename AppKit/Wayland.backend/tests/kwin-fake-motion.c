// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// Pointer mover for the tests that run on KWin, which has no virtual pointer protocol: KWin offers the
// pointer requests of org_kde_kwin_fake_input to a client that authenticates (tests/kwin-fake-input.xml
// describes that interface of KDE's public protocol as far as it is used here). Needs a KWin whose
// settings allow it (a private kwin_wayland --virtual does).
// Build on the host:
//   wayland-scanner client-header kwin-fake-input.xml fake-input-client-protocol.h
//   wayland-scanner private-code kwin-fake-input.xml fake-input-protocol.c
//   cc -o kwin-fake-motion kwin-fake-motion.c fake-input-protocol.c -lwayland-client
// kwin-fake-motion <seconds> <dx> <dy> <delay-ms>: stays connected for <seconds> (the virtual pointer exists
// as long as the client does, and a client that binds wl_seat after it sees the pointer) and moves the
// pointer by (dx, dy) every <delay-ms>, turning round after 30 moves, so that it crosses a window anywhere
// on the output again and again.
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
    if (argc != 5) { fprintf(stderr, "usage: kwin-fake-motion seconds dx dy delay-ms\n"); return 3; }
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "no display\n"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &listener, NULL);
    wl_display_roundtrip(display);
    if (!fake) { fprintf(stderr, "no fake input\n"); return 2; }
    org_kde_kwin_fake_input_authenticate(fake, "pointer-test", "move the pointer across a window");
    wl_display_roundtrip(display);
    int seconds = atoi(argv[1]), delay = atoi(argv[4]);
    int dx = atoi(argv[2]), dy = atoi(argv[3]);
    for (long moves = 0; moves < (long) seconds * 1000 / (delay > 0 ? delay : 1); moves++) {
        if (moves % 30 == 0 && moves > 0) { dx = -dx; dy = -dy; }
        org_kde_kwin_fake_input_pointer_motion(fake, wl_fixed_from_int(dx), wl_fixed_from_int(dy));
        wl_display_roundtrip(display);
        usleep(delay * 1000);
    }
    return 0;
}
