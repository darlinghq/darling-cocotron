// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
// Host tool of tests/coregraphics-x11-menu-input.sh: tries to grab the pointer and the keyboard on the root window as another
// client and prints "pointer=<status> keyboard=<status>" (0 is GrabSuccess, 1 AlreadyGrabbed), releasing what it got.
// Build: cc x11-grab-probe.c -lX11
#include <X11/Xlib.h>
#include <stdio.h>

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display)
        return 2;
    Window root = DefaultRootWindow(display);
    int pointer = XGrabPointer(display, root, False, ButtonPressMask, GrabModeAsync, GrabModeAsync, None, None, CurrentTime);
    int keyboard = XGrabKeyboard(display, root, False, GrabModeAsync, GrabModeAsync, CurrentTime);
    printf("pointer=%d keyboard=%d\n", pointer, keyboard);
    XUngrabPointer(display, CurrentTime);
    XUngrabKeyboard(display, CurrentTime);
    XCloseDisplay(display);
    return 0;
}
