/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
/* Adds 60 Hz modes of the given sizes (WIDTHxHEIGHT ...) to the first output of the X server in
 * $DISPLAY, prints READY and stays connected until it is terminated: the X server deletes the
 * modes a client created when that client disconnects, so the modes exist only while this runs.
 * Xvfb has only the mode its -screen option names, and xrandr --newmode / --addmode cannot keep
 * a mode beyond its own invocation.
 * Used by coregraphics-display-mode-switch.sh. */
#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    Display *display = XOpenDisplay(NULL);
    if (!display || argc < 2)
        return 2;
    Window root = DefaultRootWindow(display);
    XRRScreenResources *resources = XRRGetScreenResources(display, root);
    if (!resources || resources->noutput < 1)
        return 2;
    for (int i = 1; i < argc; i++) {
        unsigned width, height;
        if (sscanf(argv[i], "%ux%u", &width, &height) != 2)
            return 2;
        char name[48];
        snprintf(name, sizeof name, "%ux%u_60", width, height);
        XRRModeInfo info;
        memset(&info, 0, sizeof info);
        info.width = width;
        info.height = height;
        info.hTotal = width + width / 5;
        info.vTotal = height + height / 20 + 3;
        info.hSyncStart = width + width / 40;
        info.hSyncEnd = width + width / 10;
        info.vSyncStart = height + 3;
        info.vSyncEnd = height + 6;
        info.dotClock = (unsigned long) info.hTotal * info.vTotal * 60;
        info.name = name;
        info.nameLength = (unsigned) strlen(name);
        RRMode mode = XRRCreateMode(display, root, &info);
        if (mode == None)
            return 1;
        XRRAddOutputMode(display, resources->outputs[0], mode);
    }
    XSync(display, False);
    XRRFreeScreenResources(resources);
    printf("READY\n");
    fflush(stdout);
    pause();
    return 0;
}
