// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// Helper of coregraphics-x11-toplevel-events.sh: what a window system does to a window when the user closes it
// or part of it is uncovered.
//   probe close <window>               asks the window to close the way a window manager does (WM_DELETE_WINDOW)
//   probe expose <window> x y w h      has the server report the area as exposed (a repaint is asked for)
#include <X11/Xlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    Display *display = XOpenDisplay(NULL);
    if (display == NULL || argc < 3)
        return 2;
    Window window = (Window) strtoul(argv[2], NULL, 0);
    if (strcmp(argv[1], "close") == 0) {
        XEvent event = {0};
        event.xclient.type = ClientMessage;
        event.xclient.window = window;
        event.xclient.message_type = XInternAtom(display, "WM_PROTOCOLS", False);
        event.xclient.format = 32;
        event.xclient.data.l[0] = (long) XInternAtom(display, "WM_DELETE_WINDOW", False);
        event.xclient.data.l[1] = CurrentTime;
        XSendEvent(display, window, False, NoEventMask, &event);
    } else if (strcmp(argv[1], "expose") == 0 && argc == 7) {
        XClearArea(display, window, atoi(argv[3]), atoi(argv[4]), atoi(argv[5]), atoi(argv[6]), True);
    } else {
        return 2;
    }
    XSync(display, False);
    XCloseDisplay(display);
    return 0;
}
