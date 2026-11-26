/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Moves the pointer, presses and releases buttons and keys with XTest, with a pause after each step, for the
 * drivers of the X11 pointer tests.
 * Usage: x11-xtest-pointer <pause in ms> <step>...
 *   m:<x>:<y>   move the pointer to the root coordinates
 *   b:<n>:<1|0> press (1) or release (0) the button n (1 left, 2 middle, 3 right)
 *   k:<code>:<1|0> press or release the key with the X key code
 *   w:<ms>      wait
 *   e:<window>:<button>:<time>  send a press of the button to the X window with the server time (XSendEvent)
 * For example "x11-xtest-pointer 80 m:200:200 b:1:1 b:1:0" clicks the left button at 200, 200.
 * Build: cc -o x11-xtest-pointer x11-xtest-pointer.c -lX11 -lXtst
 */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <pause ms> <step>...\n", argv[0]);
        return 2;
    }
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "cannot open the display\n");
        return 1;
    }
    long pause = atol(argv[1]);
    for (int i = 2; i < argc; i++) {
        int a, b;
        long ms;
        unsigned long win;
        if (sscanf(argv[i], "m:%d:%d", &a, &b) == 2) {
            XTestFakeMotionEvent(display, -1, a, b, CurrentTime);
        } else if (sscanf(argv[i], "b:%d:%d", &a, &b) == 2) {
            XTestFakeButtonEvent(display, (unsigned int) a, b ? True : False, CurrentTime);
        } else if (sscanf(argv[i], "k:%d:%d", &a, &b) == 2) {
            XTestFakeKeyEvent(display, (unsigned int) a, b ? True : False, CurrentTime);
        } else if (sscanf(argv[i], "e:%lu:%d:%ld", &win, &b, &ms) == 3) {
            XEvent event;
            memset(&event, 0, sizeof(event));
            event.xbutton.type = ButtonPress;
            event.xbutton.display = display;
            event.xbutton.window = (Window) win;
            event.xbutton.root = DefaultRootWindow(display);
            event.xbutton.time = (Time) ms;
            event.xbutton.x = event.xbutton.y = 20;
            event.xbutton.x_root = event.xbutton.y_root = 20;
            event.xbutton.button = (unsigned int) b;
            event.xbutton.same_screen = True;
            XSendEvent(display, event.xbutton.window, False, ButtonPressMask, &event);
        } else if (sscanf(argv[i], "w:%ld", &ms) == 1) {
            XFlush(display);
            usleep(ms * 1000);
            continue;
        } else {
            fprintf(stderr, "bad step %s\n", argv[i]);
            return 2;
        }
        XFlush(display);
        usleep(pause * 1000);
    }
    XCloseDisplay(display);
    return 0;
}
