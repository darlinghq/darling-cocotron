/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

/* Which process owns an X11 window, shared by the CoreGraphics and AppKit X11
 * backends.
 *
 * EWMH names a window's owner with _NET_WM_PID, a PID in the X server's
 * process namespace that is only meaningful together with WM_CLIENT_MACHINE,
 * the name of the machine that PID belongs to. Darling processes see PIDs of
 * their own namespace, so a window publishes the host PID darlingserver
 * reports for the process, and a PID read from a window is mapped back the
 * same way. A window whose PID maps to no Darling process belongs to some
 * other host program, and is none of a Darling process's business. */
#ifndef X11_WINDOW_OWNER_H
#define X11_WINDOW_OWNER_H

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <errno.h>
#include <sys/param.h>
#include <stdbool.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

/* Provided by libsystem_kernel; weak so that an older one only disables
 * this. Each returns 0 or an errno value. */
extern int __darling_host_pid(pid_t *host_pid) __attribute__((weak_import));
extern int __darling_pid_for_host_pid(pid_t host_pid, pid_t *pid)
        __attribute__((weak_import));

/* This process's PID as the host sees it, or 0 when unknown. The answer is
 * kept for as long as the process (the getpid() it was found for) lives. */
static inline pid_t X11WindowOwnerHostPID(void) {
    static pid_t cachedFor, cachedHostPID;
    pid_t self = getpid();

    if (cachedFor == self)
        return cachedHostPID;

    pid_t hostPID = 0;
    if (__darling_host_pid == NULL || __darling_host_pid(&hostPID) != 0)
        hostPID = 0;
    cachedHostPID = hostPID;
    cachedFor = self;
    return hostPID;
}

/* The name WM_CLIENT_MACHINE carries for this machine. */
static inline bool X11WindowOwnerMachineName(char *buffer, size_t size) {
    if (gethostname(buffer, size) != 0)
        return false;
    buffer[size - 1] = '\0';
    return buffer[0] != '\0';
}

/* Names this process as the owner of a top-level window. */
static inline void X11WindowOwnerPublish(Display *display, Window window) {
    pid_t hostPID = X11WindowOwnerHostPID();
    char machine[MAXHOSTNAMELEN];

    if (hostPID <= 0 ||
        !X11WindowOwnerMachineName(machine, sizeof(machine)))
        return;

    char *names[1] = {machine};
    XTextProperty property;
    if (XStringListToTextProperty(names, 1, &property)) {
        XSetWMClientMachine(display, window, &property);
        XFree(property.value);
    }

    long value = hostPID;
    XChangeProperty(display, window,
                    XInternAtom(display, "_NET_WM_PID", False), XA_CARDINAL,
                    32, PropModeReplace, (unsigned char *) &value, 1);
}

/* The Darling PID of the process owning a window, or 0 if it is not a
 * Darling process's window (or names no owner). */
static inline pid_t X11WindowOwnerPID(Display *display, Window window) {
    Atom pidAtom = XInternAtom(display, "_NET_WM_PID", True);
    if (pidAtom == None || __darling_pid_for_host_pid == NULL)
        return 0;

    Atom type;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    pid_t hostPID = 0;

    if (XGetWindowProperty(display, window, pidAtom, 0, 1, False,
                           XA_CARDINAL, &type, &format, &count, &remaining,
                           &data) == Success &&
        data != NULL && type == XA_CARDINAL && format == 32 && count == 1)
        hostPID = (pid_t) * (long *) data;
    if (data != NULL)
        XFree(data);
    if (hostPID <= 0)
        return 0;

    // The PID is only valid on the machine the window names.
    char machine[MAXHOSTNAMELEN];
    XTextProperty property;
    bool sameMachine = false;

    if (X11WindowOwnerMachineName(machine, sizeof(machine)) &&
        XGetWMClientMachine(display, window, &property)) {
        sameMachine = property.value != NULL && property.format == 8 &&
                      property.nitems == strlen(machine) &&
                      memcmp(property.value, machine, property.nitems) == 0;
        if (property.value != NULL)
            XFree(property.value);
    }
    if (!sameMachine)
        return 0;

    pid_t pid = 0;
    if (__darling_pid_for_host_pid(hostPID, &pid) != 0)
        return 0;
    return pid;
}

#endif
