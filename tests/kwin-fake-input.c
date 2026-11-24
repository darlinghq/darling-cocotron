// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Test helper: injects pointer and keyboard input into KWin through its fake input protocol (org_kde_kwin_fake_input,
// which KWin offers to clients that authenticate). Prints READY, then for each line on stdin does what it says and
// prints the command's name in capitals when it is done:
//   "abs x y" moves the pointer to that point of the screen (ABS); "rel dx dy" moves it by that much, which may be
//   fractional (REL); "button code state" presses (1) or releases (0) the Linux button with that code (BUTTON);
//   "key code state" does the same for the key with that evdev code (KEY); "axis axis value" scrolls (axis 0
//   vertical, 1 horizontal; positive is down and right) by that many axis units (AXIS); "gap ms" waits (GAP).
// Build: wayland-scanner client-header and private-code on the protocol XML of KWin's fake input (KWin's sources,
// src/wayland/protocols/fake-input.xml), then cc kwin-fake-input.c fake-input-protocol.c -lwayland-client -lm
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "fake-input-client-protocol.h"

static struct org_kde_kwin_fake_input *fake;

static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, "org_kde_kwin_fake_input"))
        fake = wl_registry_bind(registry, name, &org_kde_kwin_fake_input_interface, version < 4 ? version : 4);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {}
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
    if (!fake) {
        fprintf(stderr, "no fake input\n");
        return 2;
    }
    org_kde_kwin_fake_input_authenticate(fake, "kwin-fake-input", "test input");
    wl_display_roundtrip(display);
    puts("READY");
    fflush(stdout);
    char line[128];
    int a, b;
    double fx, fy;
    while (fgets(line, sizeof(line), stdin) != NULL) {
        if (sscanf(line, "abs %lf %lf", &fx, &fy) == 2) {
            org_kde_kwin_fake_input_pointer_motion_absolute(fake, wl_fixed_from_double(fx), wl_fixed_from_double(fy));
            puts("ABS");
        } else if (sscanf(line, "rel %lf %lf", &fx, &fy) == 2) {
            org_kde_kwin_fake_input_pointer_motion(fake, wl_fixed_from_double(fx), wl_fixed_from_double(fy));
            puts("REL");
        } else if (sscanf(line, "button %d %d", &a, &b) == 2) {
            org_kde_kwin_fake_input_button(fake, a, b);
            puts("BUTTON");
        } else if (sscanf(line, "key %d %d", &a, &b) == 2) {
            org_kde_kwin_fake_input_keyboard_key(fake, a, b);
            puts("KEY");
        } else if (sscanf(line, "axis %d %lf", &a, &fx) == 2) {
            org_kde_kwin_fake_input_axis(fake, a, wl_fixed_from_double(fx));
            puts("AXIS");
        } else if (sscanf(line, "gap %d", &a) == 1) {
            usleep(a * 1000);
            puts("GAP");
        } else {
            break;
        }
        wl_display_roundtrip(display);
        fflush(stdout);
    }
    return 0;
}
