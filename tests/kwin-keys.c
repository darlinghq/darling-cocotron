// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// Input injector for the tests that run on KWin, which has no virtual keyboard or pointer protocol: KWin offers
// the key and pointer requests of org_kde_kwin_fake_input to a client that authenticates (kwin-fake-input.xml describes that
// interface of KDE's public protocol as far as it is used here). Needs a KWin whose settings allow it (a
// private kwin_wayland --virtual does).
// Build on the host:
//   wayland-scanner client-header kwin-fake-input.xml fake-input-client-protocol.h
//   wayland-scanner private-code kwin-fake-input.xml fake-input-protocol.c
//   cc -o kwin-keys kwin-keys.c fake-input-protocol.c -lwayland-client -lm
// kwin-keys <delay-ms> [<event> ...]: injects input into KWin through its fake input protocol, waiting <delay-ms>
// between the events. An event is one of
//   <evdev-key-code>:<state>   a key (state 1 = press, 0 = release)
//   wNNN                       waits NNN milliseconds
//   aX,Y                       moves the pointer to X, Y (logical pixels of the layout)
//   rDX,DY                     moves the pointer by DX, DY (what a locked pointer reports as relative motion)
//   bCODE:STATE                a pointer button by its evdev code (272 is the left one), state as for keys
//   vN                         turns the wheel by N (vertical, positive scrolls down; one notch is 15)
// Without events on the command line they are read from standard input, one per line (see below).
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
    // The pointer and keyboard KWin makes for the injected input exist while this process does: with no
    // events on the command line the events are read from standard input, one per line, and each is
    // answered with the line "DONE" once it is injected, so that a test keeps one device for a whole run.
    char line[128];
    for (int i = 2; argc > 2 ? i < argc : fgets(line, sizeof(line), stdin) != NULL; i++) {
        char *event = argc > 2 ? argv[i] : line;
        if (argc <= 2)
            event[strcspn(event, "\n")] = 0;
        if (event[0] == 'w') { // wNNN: wait NNN milliseconds
            usleep(atol(event + 1) * 1000);
        } else {
            unsigned code, state;
            double x, y;
            if (sscanf(event, "a%lf,%lf", &x, &y) == 2) {
                org_kde_kwin_fake_input_pointer_motion_absolute(fake, wl_fixed_from_double(x), wl_fixed_from_double(y));
            } else if (sscanf(event, "r%lf,%lf", &x, &y) == 2) {
                org_kde_kwin_fake_input_pointer_motion(fake, wl_fixed_from_double(x), wl_fixed_from_double(y));
            } else if (sscanf(event, "b%u:%u", &code, &state) == 2) {
                org_kde_kwin_fake_input_button(fake, code, state);
            } else if (sscanf(event, "v%lf", &x) == 1) {
                org_kde_kwin_fake_input_axis(fake, 0, wl_fixed_from_double(x));
            } else {
                if (sscanf(event, "%u:%u", &code, &state) != 2) return 3;
                org_kde_kwin_fake_input_keyboard_key(fake, code, state);
            }
            wl_display_roundtrip(display);
            usleep(delay * 1000);
        }
        if (argc <= 2) {
            puts("DONE");
            fflush(stdout);
        }
    }
    wl_display_roundtrip(display);
    return 0;
}
