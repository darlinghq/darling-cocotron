/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Presses and releases X key codes with XTest, with a pause after each event, for the drivers of the X11
 * keyboard tests (xdotool presses a modifier keysym together with an extra modifier of its own, and a key it
 * presses and releases within milliseconds is released before a client has read it).
 * Usage: x11-xtest-keys <pause in ms> <key code>:<1 for press, 0 for release>...
 * For example "x11-xtest-keys 150 50:1 38:1 38:0 50:0" types a with the left Shift key held on a PC keyboard.
 * Build: cc -o x11-xtest-keys x11-xtest-keys.c -lX11 -lXtst
 */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <pause ms> <keycode>:<state>...\n", argv[0]);
        return 2;
    }
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "cannot open the display\n");
        return 1;
    }
    long pause = atol(argv[1]);
    for (int i = 2; i < argc; i++) {
        unsigned int code, down;
        if (sscanf(argv[i], "%u:%u", &code, &down) != 2) {
            fprintf(stderr, "bad key event %s\n", argv[i]);
            return 2;
        }
        XTestFakeKeyEvent(display, code, down ? True : False, CurrentTime);
        XFlush(display);
        usleep(pause * 1000);
    }
    XCloseDisplay(display);
    return 0;
}
