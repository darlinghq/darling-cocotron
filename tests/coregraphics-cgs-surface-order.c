/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// A surface of a CGS window is shown and hidden with CGSOrderSurface() (X11: it is the X window that the
// surface is, and it is mapped or unmapped). A new surface is not shown until it is ordered in; ordering it out
// hides it again; a surface that does not exist and a mode that is not available are errors. Needs an X server
// (the program prints SKIP on any other window system) and is for 64-bit processes, which read the state of the X
// window through the process's own connection.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>


#ifdef __LP64__
// The part of XWindowAttributes up to the map state (Xlib.h, on a 64-bit system); the rest is padding
typedef struct {
    int x, y, width, height, border_width, depth;
    void *visual;
    unsigned long root;
    int class_, bit_gravity, win_gravity, backing_store;
    unsigned long backing_planes, backing_pixel;
    int save_under;
    unsigned long colormap;
    int map_installed, map_state;
    char rest[64];
} WindowAttributes;
extern int XGetWindowAttributes(void *display, unsigned long window, WindowAttributes *attributes);
extern int XSync(void *display, int discard);
enum { kUnmapped = 0, kViewable = 2 };
#endif

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void)
{
#ifndef __LP64__
    printf("SKIP coregraphics-cgs-surface-order (64-bit only)\n");
    return 0;
#else
    CGSConnectionID cid = CGSMainConnectionID();
    void *display = cid ? _CGSNativeDisplay(cid) : NULL;
    if (!display) {
        printf("SKIP coregraphics-cgs-surface-order (no window system)\n");
        return 0;
    }
    CGRect frame = CGRectMake(100, 120, 200, 150);
    CGSRegionRef region = NULL;
    CGSWindowID wid = 0;
    CGSSurfaceID sid = 0;
    CGSNewRegionWithRect(&frame, &region);
    CHECK(CGSNewWindow(cid, 0, 0, 0, region, &wid) == kCGErrorSuccess && wid != 0);
    CGSRegionRelease(region);
    CHECK(CGSOrderWindow(cid, wid, 2, 0) == kCGErrorSuccess);
    CHECK(CGSAddSurface(cid, wid, &sid) == kCGErrorSuccess && sid != 0);
    CHECK(CGSSetSurfaceBounds(cid, wid, sid, CGRectMake(0, 0, 200, 150)) == kCGErrorSuccess);
    unsigned long native = (unsigned long) _CGSNativeWindowForSurfaceID(cid, wid, sid);
    WindowAttributes attributes;
    CHECK(native != 0);

    // a new surface is not shown
    XSync(display, 0);
    memset(&attributes, 0, sizeof(attributes));
    CHECK(XGetWindowAttributes(display, native, &attributes) != 0 && attributes.map_state == kUnmapped);

    // ordered in it is shown, ordered out it is hidden again
    CHECK(CGSOrderSurface(cid, wid, sid, 1, 0) == kCGErrorSuccess);
    XSync(display, 0);
    memset(&attributes, 0, sizeof(attributes));
    CHECK(XGetWindowAttributes(display, native, &attributes) != 0 && attributes.map_state == kViewable);
    CHECK(attributes.width == 200 && attributes.height == 150);
    CHECK(CGSOrderSurface(cid, wid, sid, 0, 0) == kCGErrorSuccess);
    XSync(display, 0);
    CHECK(XGetWindowAttributes(display, native, &attributes) != 0 && attributes.map_state == kUnmapped);
    CHECK(CGSOrderSurface(cid, wid, sid, 2, 0) == kCGErrorSuccess);
    XSync(display, 0);
    CHECK(XGetWindowAttributes(display, native, &attributes) != 0 && attributes.map_state == kViewable);

    // below is not available, and a surface that is not there is an error
    CHECK(CGSOrderSurface(cid, wid, sid, -1, 0) == kCGErrorNotImplemented);
    CHECK(CGSOrderSurface(cid, wid, sid + 100, 1, 0) != kCGErrorSuccess);
    CHECK(CGSOrderSurface(cid, wid + 100, sid, 1, 0) != kCGErrorSuccess);

    CHECK(CGSRemoveSurface(cid, wid, sid) == kCGErrorSuccess);
    CHECK(CGSReleaseWindow(cid, wid) == kCGErrorSuccess);
    printf(failures ? "FAIL coregraphics-cgs-surface-order\n" : "PASS coregraphics-cgs-surface-order\n");
    return failures != 0;
#endif
}
