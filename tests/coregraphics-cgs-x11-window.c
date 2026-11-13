/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// Window server SPI, declared the way applications declare it.
typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern void CGSRegionRelease(RegionRef region);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region,
                            CGSWindowID *windowID);
extern CGError CGSReleaseWindow(CGSConnectionID cid, CGSWindowID wid);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern CGError CGSMoveWindow(CGSConnectionID cid, CGSWindowID wid, const CGPoint *position);
extern CGError CGSSetWindowTitle(CGSConnectionID cid, CGSWindowID wid, CFStringRef title);
extern CGError CGSGetWindowProperty(CGSConnectionID cid, CGSWindowID wid, CFStringRef key, CFTypeRef *value);
extern CGError CGSAddSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID *sid);
extern CGError CGSRemoveSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid);
extern CGError CGSSetSurfaceBounds(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGRect rect);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeWindowForSurfaceID(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);
extern const CFStringRef kCGSWindowTitle;

enum { OrderBelow = -1, OrderOut = 0, OrderAbove = 1, OrderIn = 2 };

// A CGS window and surface on the window system backend: needs an X server.
int main(void) {
    CGSConnectionID cid = CGSMainConnectionID();
    if (cid == 0)
        return 10;
    if (_CGSNativeDisplay(cid) == NULL) {
        printf("no backend display\n");
        return 2;
    }

    CGRect frame = CGRectMake(100, 120, 200, 150);
    RegionRef region = NULL;
    if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || !region)
        return 11;

    CGSWindowID wid = 0;
    CGError error = CGSNewWindow(cid, 0, 0, 0, region, &wid);
    printf("window %u error %d\n", wid, (int) error);
    if (error != kCGErrorSuccess || wid == 0)
        return 20;

    // The window is a real drawable the OpenGL layer can attach to.
    if (_CGSNativeWindowForID(cid, wid) == NULL)
        return 21;

    // Showing, hiding and moving a window is accepted; "below" without a sibling is not available.
    if (CGSOrderWindow(cid, wid, OrderIn, 0) != kCGErrorSuccess)
        return 30;
    CGPoint position = CGPointMake(40, 50);
    if (CGSMoveWindow(cid, wid, &position) != kCGErrorSuccess)
        return 31;
    if (CGSMoveWindow(cid, wid, NULL) != kCGErrorIllegalArgument)
        return 32;
    if (CGSOrderWindow(cid, wid, OrderBelow, 0) != kCGErrorNotImplemented)
        return 33;
    if (CGSOrderWindow(cid, wid, OrderOut, 0) != kCGErrorSuccess)
        return 34;

    // The title round-trips; other property keys are refused.
    if (CGSSetWindowTitle(cid, wid, CFSTR("cgs window")) != kCGErrorSuccess)
        return 40;
    CFTypeRef title = NULL;
    if (CGSGetWindowProperty(cid, wid, kCGSWindowTitle, &title) != kCGErrorSuccess || !title)
        return 41;
    char text[32] = "";
    CFStringGetCString((CFStringRef) title, text, sizeof text, kCFStringEncodingUTF8);
    CFRelease(title);
    if (strcmp(text, "cgs window") != 0)
        return 42;
    CFTypeRef other = NULL;
    if (CGSGetWindowProperty(cid, wid, CFSTR("NoSuchProperty"), &other) != kCGErrorNotImplemented)
        return 43;

    // A surface is a child drawable of the window of its own.
    CGSSurfaceID sid = 0;
    if (CGSAddSurface(cid, wid, &sid) != kCGErrorSuccess || sid == 0)
        return 50;
    void *surfaceNative = _CGSNativeWindowForSurfaceID(cid, wid, sid);
    if (surfaceNative == NULL || surfaceNative == _CGSNativeWindowForID(cid, wid))
        return 51;
    if (CGSSetSurfaceBounds(cid, wid, sid, CGRectMake(10, 10, 100, 80)) != kCGErrorSuccess)
        return 52;
    if (CGSRemoveSurface(cid, wid, sid) != kCGErrorSuccess)
        return 53;

    // X11 refuses a window of no size; so does the backend, instead of creating one.
    CGRect empty = CGRectMake(0, 0, 0, 0);
    RegionRef emptyRegion = NULL;
    CGSNewRegionWithRect(&empty, &emptyRegion);
    CGSWindowID none = 0;
    if (emptyRegion != NULL) {
        if (CGSNewWindow(cid, 0, 0, 0, emptyRegion, &none) != kCGErrorIllegalArgument)
            return 60;
        CGSRegionRelease(emptyRegion);
    }

    if (CGSReleaseWindow(cid, wid) != kCGErrorSuccess)
        return 70;
    // Released: the id names nothing.
    if (CGSOrderWindow(cid, wid, OrderIn, 0) == kCGErrorSuccess)
        return 71;
    CGSRegionRelease(region);
    return 0;
}
