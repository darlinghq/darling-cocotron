/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// The session bus address used by Darling's portal clients. Kept below both AppKit and CoreGraphics
// so the CoreGraphics Wayland backend can use GlobalShortcuts without depending on AppKit, while
// AppKit's existing clients keep the same validation rules.
//
// D-Bus separates alternative addresses with ';' and accepts "unixexec:", which runs a program, and
// "autolaunch:", which may start a bus. Only one plain socket address (a path or an abstract name)
// is taken from the environment.

#ifndef DARLING_SESSION_BUS_ADDRESS_H
#define DARLING_SESSION_BUS_ADDRESS_H

#import <Foundation/NSString.h>
#include <dbus/dbus.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DARLING_SESSION_BUS_ADDRESS_MAX_LENGTH 1024

static inline BOOL DarlingPortalSessionBusAddressAllowed(const char *address) {
    if (strncmp(address, "unix:path=", 10) != 0 &&
        strncmp(address, "unix:abstract=", 14) != 0)
        return NO;
    if (strlen(address) >= DARLING_SESSION_BUS_ADDRESS_MAX_LENGTH)
        return NO;
    for (const unsigned char *c = (const unsigned char *) address; *c != '\0'; c++) {
        if (*c <= ' ' || *c >= 0x7f || *c == ';')
            return NO;
    }
    return strstr(address, "unixexec") == NULL;
}

static inline NSString *DarlingPortalSessionBusAddress(void) {
    const char *env = getenv("DBUS_SESSION_BUS_ADDRESS");

    if (env != NULL && env[0] != '\0')
        return DarlingPortalSessionBusAddressAllowed(env) ? [NSString stringWithUTF8String: env] : nil;

    const char *runtimeDirectory = getenv("XDG_RUNTIME_DIR");
    if (runtimeDirectory == NULL || runtimeDirectory[0] != '/')
        return nil;

    char path[DARLING_SESSION_BUS_ADDRESS_MAX_LENGTH];
    if (snprintf(path, sizeof(path), "%s/bus", runtimeDirectory) >=
        (int) sizeof(path))
        return nil;

    char *escaped = dbus_address_escape_value(path);
    NSString *address = nil;
    if (escaped != NULL)
        address = [NSString stringWithFormat: @"unix:path=%s", escaped];
    dbus_free(escaped);
    return address;
}

#endif
