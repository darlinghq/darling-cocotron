/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>

// The warp glue of CGDirectDisplay.m against the real backend: argument checks (non-finite coordinates),
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

    // A coordinate that is not a finite number is taken as 0 on its own axis, and the warp succeeds (QUIRK of
    // CGDirectDisplay.m: the Macs do this, 26.7.3 and 10.14.4, also for infinity, which is not clamped to the far edge).
    // The expectation is the global point, so the desktop is assumed to start at the origin.
    struct { double x, y, wantX, wantY; } nonFinite[] = {
        {NAN, 60, 0, 60}, {70, NAN, 70, 0}, {NAN, NAN, 0, 0},
        {INFINITY, 60, 0, 60}, {-INFINITY, 60, 0, 60}, {70, INFINITY, 70, 0}, {70, -INFINITY, 70, 0},
        {INFINITY, INFINITY, 0, 0},
    };
    for (unsigned i = 0; i < sizeof nonFinite / sizeof nonFinite[0]; i++) {
        if (CGWarpMouseCursorPosition(CGPointMake(bounds.origin.x + 200, bounds.origin.y + 150)) != kCGErrorSuccess)
            return 10;
        if (CGWarpMouseCursorPosition(CGPointMake(nonFinite[i].x, nonFinite[i].y)) != kCGErrorSuccess) {
            printf("non-finite case %u: not success\n", i);
            return 11;
        }
        CGPoint at = pointer();
        printf("non-finite case %u -> %g,%g\n", i, at.x, at.y);
        if (fabs(at.x - nonFinite[i].wantX) > 1 || fabs(at.y - nonFinite[i].wantY) > 1)
            return 12;
    }
    if (CGDisplayMoveCursorToPoint(display, CGPointMake(NAN, 45)) != kCGErrorSuccess)
        return 14;
    CGPoint nanMove = pointer();
    if (fabs(nanMove.x - bounds.origin.x) > 1 || fabs(nanMove.y - (bounds.origin.y + 45)) > 1)
        return 15;

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
