// Copyright (C) 2026 Lubos Dolezel
//
// A scripted Wayland input method for tests of a toolkit's text input support: see README.md.
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>
#include "im-client.h"

static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static struct zwp_input_method_v2 *method;
static uint32_t serial;
static int active, pending_active, script_done;

static void registry_global(void *data, struct wl_registry *registry, uint32_t name,
                            const char *interface, uint32_t version) {
    if (strcmp(interface, "wl_seat") == 0 && seat == NULL)
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
    else if (strcmp(interface, "zwp_input_method_manager_v2") == 0)
        manager = wl_registry_bind(registry, name, &zwp_input_method_manager_v2_interface, 1);
}
static void registry_remove(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {registry_global, registry_remove};

static void im_activate(void *d, struct zwp_input_method_v2 *m) { pending_active = 1; }
static void im_deactivate(void *d, struct zwp_input_method_v2 *m) { pending_active = 0; }
// What the client says of its text is printed, for a driver that checks it.
static void im_surrounding(void *d, struct zwp_input_method_v2 *m, const char *t, uint32_t c, uint32_t a) {
    printf("surrounding \"%s\" %u %u\n", t, c, a);
    fflush(stdout);
}
static void im_cause(void *d, struct zwp_input_method_v2 *m, uint32_t cause) {}
static void im_content_type(void *d, struct zwp_input_method_v2 *m, uint32_t hint, uint32_t purpose) {
    printf("content_type %u %u\n", hint, purpose);
    fflush(stdout);
}
static void im_done(void *d, struct zwp_input_method_v2 *m) {
    serial++;
    active = pending_active;
}
static void im_unavailable(void *d, struct zwp_input_method_v2 *m) {
    fprintf(stderr, "another input method is running\n");
    exit(1);
}
static const struct zwp_input_method_v2_listener im_listener = {
    im_activate, im_deactivate, im_surrounding, im_cause, im_content_type, im_done, im_unavailable};

// Dispatches events for about `ms` milliseconds.
static void pump(struct wl_display *display, int ms) {
    for (int i = 0; i < ms / 10; i++) {
        wl_display_flush(display);
        if (wl_display_prepare_read(display) == 0) {
            struct pollfd pfd = {wl_display_get_fd(display), POLLIN, 0};
            if (poll(&pfd, 1, 10) > 0)
                wl_display_read_events(display);
            else
                wl_display_cancel_read(display);
        }
        wl_display_dispatch_pending(display);
    }
}

// One state of the input method: text deleted around the caret (bytes), the final text, the composition.
static void step_delete(struct wl_display *display, unsigned before, unsigned after, const char *preedit, int begin,
                        int end, const char *commit) {
    if (before != 0 || after != 0)
        zwp_input_method_v2_delete_surrounding_text(method, before, after);
    if (commit != NULL)
        zwp_input_method_v2_commit_string(method, commit);
    zwp_input_method_v2_set_preedit_string(method, preedit, begin, end);
    zwp_input_method_v2_commit(method, serial);
    pump(display, 400);
}

static void step(struct wl_display *display, const char *preedit, int begin, int end, const char *commit) {
    step_delete(display, 0, 0, preedit, begin, end, commit);
}

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (display == NULL) {
        fprintf(stderr, "no compositor\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (seat == NULL || manager == NULL) {
        fprintf(stderr, "the compositor has no input method protocol\n");
        return 1;
    }
    method = zwp_input_method_manager_v2_get_input_method(manager, seat);
    zwp_input_method_v2_add_listener(method, &im_listener, NULL);
    wl_display_roundtrip(display);
    printf("ready\n");
    fflush(stdout);

    // Wait for a client to enable text input (up to a minute).
    for (int i = 0; i < 600 && !active; i++)
        pump(display, 100);
    if (!active) {
        fprintf(stderr, "no text input became active\n");
        return 1;
    }
    pump(display, 300);
    step(display, "ka", 2, 2, NULL);
    step(display, "\xe3\x81\x8b", 3, 3, NULL);
    // The final text, with no composition left.
    step(display, "", 0, 0, "\xe3\x81\x8b");
    step(display, "x", 1, 1, NULL);
    // Cancelled: no composition and nothing committed.
    step(display, "", 0, 0, NULL);
    // Outside the BMP: U+20BB7 (4 bytes of UTF-8, a surrogate pair in UTF-16) after "a", with the caret after it
    // (byte 5), then two such characters committed (U+20BB7 and U+1F600).
    step(display, "a\xf0\xa0\xae\xb7", 5, 5, NULL);
    step(display, "", 0, 0, "\xf0\xa0\xae\xb7\xf0\x9f\x98\x80");
    // Text deleted around the caret (1 byte before it, 4 after) and non-ASCII text (U+00FC) committed: a client that
    // says what its text is gets the deletion.
    step_delete(display, 1, 4, "", 0, 0, "\xc3\xbc");
    printf("done\n");
    fflush(stdout);
    pump(display, 500);
    return 0;
}
