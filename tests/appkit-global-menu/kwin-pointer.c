// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// A pointer for a KWin of its own, through libei. The file descriptor of the
// connection comes from KWin (org.kde.KWin.EIS.RemoteDesktop.connectToEIS);
// run-kwin.py passes it on. Commands on stdin, one per line:
//   move X Y    put the pointer at X, Y (pixels of the output)
//   click       press and release the left button
//   down, up    press, release the left button
//   key CODE    press and release the key with the evdev code CODE (Escape 1,
//               Return 28, Down 108)
//   quit
// Prints READY once the pointer exists and ACK after each command.
// Build: cc -o kwin-pointer kwin-pointer.c $(pkg-config --cflags --libs libei-1.0)
#include <libei.h>
#include <linux/input-event-codes.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2)
        return 2;
    struct ei *ei = ei_new_sender(NULL);
    ei_configure_name(ei, "darling-test-pointer");
    if (ei_setup_backend_fd(ei, atoi(argv[1])) != 0)
        return 2;

    struct ei_device *pointer = NULL, *keyboard = NULL;
    int sequence = 0, ready = 0, announced = 0;
    char line[128];
    struct pollfd fds[2] = {{ei_get_fd(ei), POLLIN, 0}, {0, POLLIN, 0}};

    for (;;) {
        ei_dispatch(ei);
        struct ei_event *event;
        while ((event = ei_get_event(ei)) != NULL) {
            switch (ei_event_get_type(event)) {
            case EI_EVENT_SEAT_ADDED:
                ei_seat_bind_capabilities(ei_event_get_seat(event), EI_DEVICE_CAP_POINTER_ABSOLUTE,
                                          EI_DEVICE_CAP_BUTTON, EI_DEVICE_CAP_KEYBOARD, NULL);
                break;
            case EI_EVENT_DEVICE_ADDED:
                if (pointer == NULL && ei_device_has_capability(ei_event_get_device(event),
                                                                EI_DEVICE_CAP_POINTER_ABSOLUTE))
                    pointer = ei_device_ref(ei_event_get_device(event));
                if (keyboard == NULL && ei_device_has_capability(ei_event_get_device(event), EI_DEVICE_CAP_KEYBOARD))
                    keyboard = ei_device_ref(ei_event_get_device(event));
                break;
            case EI_EVENT_DEVICE_RESUMED:
                // A device the compositor paused and resumes again has to start emulating again.
                if (ei_event_get_device(event) == keyboard)
                    ei_device_start_emulating(keyboard, ++sequence);
                if (ei_event_get_device(event) == pointer) {
                    ei_device_start_emulating(pointer, ++sequence);
                    ready = 1;
                    if (!announced) {
                        announced = 1;
                        puts("READY");
                        fflush(stdout);
                    }
                }
                break;
            case EI_EVENT_DEVICE_PAUSED:
                // Commands wait until the compositor resumes the pointer.
                if (ei_event_get_device(event) == pointer)
                    ready = 0;
                break;
            case EI_EVENT_DISCONNECT:
                return 1;
            default:
                break;
            }
            ei_event_unref(event);
        }
        if (poll(fds, ready ? 2 : 1, 200) <= 0 || !ready || !(fds[1].revents & (POLLIN | POLLHUP)))
            continue;
        if (fgets(line, sizeof line, stdin) == NULL)
            return 0;
        double x, y;
        if (sscanf(line, "move %lf %lf", &x, &y) == 2) {
            ei_device_pointer_motion_absolute(pointer, x, y);
        } else if (strncmp(line, "click", 5) == 0) {
            ei_device_button_button(pointer, BTN_LEFT, true);
            ei_device_frame(pointer, ei_now(ei));
            ei_dispatch(ei);
            usleep(60000);
            ei_device_button_button(pointer, BTN_LEFT, false);
        } else if (strncmp(line, "down", 4) == 0) {
            ei_device_button_button(pointer, BTN_LEFT, true);
        } else if (strncmp(line, "up", 2) == 0) {
            ei_device_button_button(pointer, BTN_LEFT, false);
        } else if (keyboard != NULL && sscanf(line, "key %lf", &x) == 1) {
            ei_device_keyboard_key(keyboard, (uint32_t) x, true);
            ei_device_frame(keyboard, ei_now(ei));
            ei_dispatch(ei);
            usleep(60000);
            ei_device_keyboard_key(keyboard, (uint32_t) x, false);
            ei_device_frame(keyboard, ei_now(ei));
        } else if (strncmp(line, "quit", 4) == 0) {
            ei_device_stop_emulating(pointer);
            ei_dispatch(ei);
            return 0;
        }
        ei_device_frame(pointer, ei_now(ei));
        ei_dispatch(ei);
        puts("ACK");
        fflush(stdout);
    }
}
