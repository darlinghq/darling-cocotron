/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <CoreGraphics/CoreGraphics.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>

// CGSGetWindowBounds() and CGSGetSurfaceBounds() on a CGS window and surface.
// The calls are resolved through dlsym, so the same program runs on macOS.
// Needs a window system connection (X11 or Wayland).

typedef int ConnectionID;
typedef unsigned WindowID, SurfaceID;

static ConnectionID (*mainConnection)(void);
static CGError (*newRegionWithRect)(const CGRect *rect, CFTypeRef *region);
static CGError (*newWindow)(ConnectionID cid, int flags, float x, float y, CFTypeRef region, WindowID *wid);
static CGError (*releaseWindow)(ConnectionID cid, WindowID wid);
static CGError (*addSurface)(ConnectionID cid, WindowID wid, SurfaceID *sid);
static CGError (*setSurfaceBounds)(ConnectionID cid, WindowID wid, SurfaceID sid, CGRect bounds);
static CGError (*moveWindow)(ConnectionID cid, WindowID wid, const CGPoint *origin);

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: %s (line %d)\n", what, __LINE__);                    \
            failures++;                                                        \
        }                                                                      \
    } while (0)

static int isNull(CGRect r) {
    return isinf(r.origin.x) && isinf(r.origin.y) && r.size.width == 0 && r.size.height == 0;
}

int main(void) {
    CGError (*getWindowBounds)(ConnectionID, WindowID, CGRect *) = dlsym(RTLD_DEFAULT, "CGSGetWindowBounds");
    CGError (*getSurfaceBounds)(ConnectionID, WindowID, SurfaceID, CGRect *) = dlsym(RTLD_DEFAULT, "CGSGetSurfaceBounds");
    mainConnection = dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    newRegionWithRect = dlsym(RTLD_DEFAULT, "CGSNewRegionWithRect");
    newWindow = dlsym(RTLD_DEFAULT, "CGSNewWindow");
    releaseWindow = dlsym(RTLD_DEFAULT, "CGSReleaseWindow");
    addSurface = dlsym(RTLD_DEFAULT, "CGSAddSurface");
    setSurfaceBounds = dlsym(RTLD_DEFAULT, "CGSSetSurfaceBounds");
    moveWindow = dlsym(RTLD_DEFAULT, "CGSMoveWindow");
    if (!mainConnection || !newRegionWithRect || !newWindow || !releaseWindow || !addSurface || !setSurfaceBounds ||
        !moveWindow) {
        printf("FAIL: window server functions missing\n");
        return 1;
    }
    if (!getWindowBounds || !getSurfaceBounds) {
        printf("FAIL: CGSGetWindowBounds/CGSGetSurfaceBounds missing\n");
        return 1;
    }

    ConnectionID cid = mainConnection();
    CGRect frame = CGRectMake(100, 120, 200, 150);
    CFTypeRef region = NULL;
    WindowID wid = 0;
    CHECK(cid != 0, "main connection");
    CHECK(newRegionWithRect(&frame, &region) == kCGErrorSuccess && region, "region");
    CHECK(newWindow(cid, 2, 0, 0, region, &wid) == kCGErrorSuccess && wid != 0, "new window");
    if (failures)
        return 2;

    CGRect bounds = CGRectMake(-1, -2, -3, -4);
    CHECK(getWindowBounds(cid, wid, &bounds) == kCGErrorSuccess, "window bounds succeed");
    CHECK(bounds.size.width == 200 && bounds.size.height == 150, "window size is the region's");
    CHECK(bounds.origin.x == 100 && bounds.origin.y == 120, "window origin is the region's");

    CGPoint moved = CGPointMake(300, 310);
    moveWindow(cid, wid, &moved);
    CHECK(getWindowBounds(cid, wid, &bounds) == kCGErrorSuccess && bounds.size.width == 200 &&
                  bounds.size.height == 150,
          "window size survives a move");

    // test_quirk_missing_window_bounds: kCGErrorFailure and a null rectangle.
    bounds = CGRectMake(-1, -2, -3, -4);
    CHECK(getWindowBounds(cid, 0x7ffffff0, &bounds) == kCGErrorFailure, "missing window: failure");
    CHECK(isNull(bounds), "missing window: result is the null rectangle");

    SurfaceID sid = 0;
    CHECK(addSurface(cid, wid, &sid) == kCGErrorSuccess && sid != 0, "add surface");
    // test_quirk_surface_bounds_null: no bounds until they are set.
    bounds = CGRectMake(-1, -2, -3, -4);
    CHECK(getSurfaceBounds(cid, wid, sid, &bounds) == kCGErrorSuccess && isNull(bounds),
          "a surface starts with the null rectangle");
    CHECK(setSurfaceBounds(cid, wid, sid, CGRectMake(0, 0, 50, 40)) == kCGErrorSuccess, "set surface bounds");
    bounds = CGRectMake(-1, -2, -3, -4);
    CHECK(getSurfaceBounds(cid, wid, sid, &bounds) == kCGErrorSuccess, "surface bounds succeed");
    CHECK(bounds.origin.x == 0 && bounds.origin.y == 0 && bounds.size.width == 50 && bounds.size.height == 40,
          "surface bounds are the ones set");
    CHECK(getSurfaceBounds(cid, wid, sid + 1000, &bounds) == kCGErrorIllegalArgument, "missing surface");
    CHECK(getSurfaceBounds(cid, 0x7fff0000, sid, &bounds) == kCGErrorIllegalArgument, "missing window for a surface");
    CHECK(getSurfaceBounds(0x7fffff00, wid, sid, &bounds) != kCGErrorSuccess, "invalid connection fails for a surface");

    releaseWindow(cid, wid);
    CHECK(getWindowBounds(cid, wid, &bounds) == kCGErrorFailure, "released window");

    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures ? 1 : 0;
}
