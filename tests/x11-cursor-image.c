/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Moves the pointer to the root coordinates with XTest and prints what cursor the server shows there: "blank" when
 * the image has no visible pixel (the blank cursor of a hidden cursor, a 1x1 transparent image), else "visible WxH
 * hot=X,Y pixel=AARRGGBB" (the hot spot and the first pixel of the image).
 * Usage: x11-cursor-image <x> <y>
 * Build: cc -o x11-cursor-image x11-cursor-image.c -lX11 -lXtst -lXfixes
 */
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xfixes.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <x> <y>\n", argv[0]);
        return 2;
    }
    Display *display = XOpenDisplay(NULL);
    if (display == NULL) {
        fprintf(stderr, "cannot open the display\n");
        return 1;
    }
    XTestFakeMotionEvent(display, -1, atoi(argv[1]), atoi(argv[2]), CurrentTime);
    XSync(display, False);
    usleep(300000);
    XFixesCursorImage *image = XFixesGetCursorImage(display);
    if (image == NULL) {
        printf("none\n");
        return 1;
    }
    int visible = 0;
    for (unsigned long i = 0; i < (unsigned long) image->width * image->height; i++) {
        if ((image->pixels[i] >> 24) != 0)
            visible = 1;
    }
    if (visible)
        printf("visible %ux%u hot=%u,%u pixel=%08lx\n", image->width, image->height, image->xhot, image->yhot,
               (unsigned long) image->pixels[0] & 0xffffffffUL);
    else
        printf("blank\n");
    XFree(image);
    XCloseDisplay(display);
    return 0;
}
