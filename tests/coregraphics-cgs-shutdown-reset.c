/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <stdint.h>
#include <stdio.h>

// Window server SPI that closes every connection of the process.
extern void CGSShutdownServerConnections(void);

int main(void) {
    CGSConnectionID first = CGSMainConnectionID();
    if (first == 0)
        return 10;

    CGSShutdownServerConnections();

    // The old id named a connection that is gone; asking again must make a new
    // one instead of handing the dead id back.
    CGSConnectionID second = CGSMainConnectionID();
    printf("connection %u -> %u\n", first, second);
    if (second == 0)
        return 11;
    if (second == first)
        return 12;
    if (CGSMainConnectionID() != second)
        return 13;

    // The new connection is usable: no window exists here, so the call fails on the window, not the connection.
    CGError error = CGSSetWindowAlpha(second, UINT32_MAX, 0.5f);
    if (error != kCGErrorIllegalArgument && error != kCGErrorNotImplemented)
        return 20;
    return 0;
}
