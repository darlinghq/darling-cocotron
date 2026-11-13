/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

// The warp glue of CGDirectDisplay.m against the real backend: argument checks,
// clipping to the desktop, and the point CGEventGetLocation reports afterwards.
// The conversion arithmetic itself is covered on the host by cg-warp-mouse.sh.
// Needs a display (run on the X server of the guest).

static CGPoint pointer(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint location = event ? CGEventGetLocation(event) : CGPointMake(NAN, NAN);
    if (event)
        CFRelease(event);
    return location;
}

int main(void) {
    CGDirectDisplayID display = CGMainDisplayID();
    if (display == kCGNullDirectDisplay) {
        printf("no display\n");
        return 2;
    }
    CGRect bounds = CGDisplayBounds(display);
    if (bounds.size.width < 4 || bounds.size.height < 4)
        return 3;

    // Non-finite points are rejected before anything moves.
    CGPoint before = pointer();
    if (CGWarpMouseCursorPosition(CGPointMake(NAN, 1)) != kCGErrorIllegalArgument)
        return 10;
    if (CGWarpMouseCursorPosition(CGPointMake(1, INFINITY)) != kCGErrorIllegalArgument)
        return 11;
    CGPoint after = pointer();
    if (before.x != after.x || before.y != after.y)
        return 12;

    // An id no display owns has no corner to be relative to.
    if (CGDisplayMoveCursorToPoint(0x7ffffff0u, CGPointMake(5, 5)) != kCGErrorIllegalArgument)
        return 13;

    // A point inside the desktop is where the pointer ends up.
    CGPoint target = CGPointMake(bounds.origin.x + 10, bounds.origin.y + 20);
    if (CGWarpMouseCursorPosition(target) != kCGErrorSuccess)
        return 20;
    CGPoint got = pointer();
    printf("warp to %g,%g -> %g,%g\n", target.x, target.y, got.x, got.y);
    if (fabs(got.x - target.x) > 1 || fabs(got.y - target.y) > 1)
        return 21;

    // The same point addressed relative to the display's own corner.
    if (CGDisplayMoveCursorToPoint(display, CGPointMake(30, 40)) != kCGErrorSuccess)
        return 22;
    got = pointer();
    if (fabs(got.x - (bounds.origin.x + 30)) > 1 || fabs(got.y - (bounds.origin.y + 40)) > 1)
        return 23;

    // Far outside the desktop: clipped to the last device pixel inside the corner.
    if (CGWarpMouseCursorPosition(CGPointMake(1e9, 1e9)) != kCGErrorSuccess)
        return 30;
    got = pointer();
    printf("far corner -> %g,%g (display %g x %g)\n", got.x, got.y, bounds.size.width, bounds.size.height);
    if (got.x >= bounds.origin.x + bounds.size.width || got.y >= bounds.origin.y + bounds.size.height)
        return 31;
    if (got.x < bounds.origin.x + bounds.size.width - 2 || got.y < bounds.origin.y + bounds.size.height - 2)
        return 32;
    if (CGWarpMouseCursorPosition(CGPointMake(-1e9, -1e9)) != kCGErrorSuccess)
        return 33;
    got = pointer();
    if (got.x < bounds.origin.x || got.x > bounds.origin.x + 2 || got.y < bounds.origin.y || got.y > bounds.origin.y + 2)
        return 34;
    return 0;
}
