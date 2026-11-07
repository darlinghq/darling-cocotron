// SPDX-License-Identifier: GPL-3.0-only
// Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
// Host test for CoreGraphics/X11.backend/X11Monitors.h: which monitor is the main display, in which order the monitors
// are listed, and the conversion between Cocoa's global space (origin at the main monitor) and root coordinates.
// The RandR part runs on a real X server; use tests/x11-monitors.sh, which starts its own Xvfb.
// Build: cc x11-monitors.c -lX11 -lXrandr
#include "../CoreGraphics/X11.backend/X11Monitors.h"
#include "../CoreGraphics/CGDisplayGeometry.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures, checks;

#define CHECK(condition, ...)                                                                               \
    do {                                                                                                    \
        checks++;                                                                                           \
        if (!(condition)) {                                                                                 \
            failures++;                                                                                     \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                     \
            printf(__VA_ARGS__);                                                                            \
            printf("\n");                                                                                   \
        }                                                                                                   \
    } while (0)

static X11Monitor active(RROutput output, int x, int y, unsigned w, unsigned h) {
    return (X11Monitor){output, true, x, y, w, h};
}

static X11Monitor inactive(RROutput output) {
    return (X11Monitor){output, false, 0, 0, 0, 0};
}

static void pickPrimary(void) {
    X11Monitor two[] = {active(10, 0, 0, 1920, 1080), active(11, 1920, 0, 2560, 1440)};
    CHECK(X11MonitorsPickPrimary(two, 2, 11) == 1, "the RandR primary wins over server order");
    CHECK(X11MonitorsPickPrimary(two, 2, None) == 0, "no RandR primary: the first active output");
    CHECK(X11MonitorsPickPrimary(two, 2, 99) == 0, "an unknown primary id: the first active output");

    X11Monitor primaryOff[] = {active(10, 0, 0, 1920, 1080), inactive(11)};
    CHECK(X11MonitorsPickPrimary(primaryOff, 2, 11) == 0, "an inactive primary falls back to the first active output");

    X11Monitor leadingOff[] = {inactive(10), active(11, 0, 0, 800, 600)};
    CHECK(X11MonitorsPickPrimary(leadingOff, 2, None) == 1, "inactive outputs are skipped");

    X11Monitor none[] = {inactive(10), inactive(11)};
    CHECK(X11MonitorsPickPrimary(none, 2, 10) == -1, "no active output, no main display");
    CHECK(X11MonitorsPickPrimary(none, 0, None) == -1, "no outputs");
}

static void order(void) {
    int out[4];
    X11Monitor mixed[] = {inactive(10), active(11, 0, 0, 1, 1), active(12, 1, 0, 1, 1), inactive(13)};
    X11MonitorsOrder(mixed, 4, 2, out);
    CHECK(out[0] == 2 && out[1] == 1 && out[2] == 0 && out[3] == 3,
          "primary, other active, inactive: got %d %d %d %d", out[0], out[1], out[2], out[3]);

    X11MonitorsOrder(mixed, 4, 1, out);
    CHECK(out[0] == 1 && out[1] == 2 && out[2] == 0 && out[3] == 3,
          "server order is kept among the rest: got %d %d %d %d", out[0], out[1], out[2], out[3]);

    int wide[5];
    X11Monitor many[] = {active(10, 0, 0, 1, 1), inactive(11), active(12, 1, 0, 1, 1), active(13, 2, 0, 1, 1), active(14, 3, 0, 1, 1)};
    X11MonitorsOrder(many, 5, 3, wide);
    CHECK(wide[0] == 3 && wide[1] == 0 && wide[2] == 2 && wide[3] == 4 && wide[4] == 1,
          "a non-first primary, three other active monitors keep server order, inactive last: got %d %d %d %d %d",
          wide[0], wide[1], wide[2], wide[3], wide[4]);
    X11MonitorsOrder(many, 5, 0, wide);
    CHECK(wide[0] == 0 && wide[1] == 2 && wide[2] == 3 && wide[3] == 4 && wide[4] == 1,
          "primary already first: got %d %d %d %d %d", wide[0], wide[1], wide[2], wide[3], wide[4]);

    X11Monitor off[] = {inactive(10), inactive(11)};
    X11MonitorsOrder(off, 2, -1, out);
    CHECK(out[0] == 0 && out[1] == 1, "nothing active keeps server order");
}

static bool near(double a, double b) {
    return fabs(a - b) < 1e-9;
}

static void frames(void) {
    /* One monitor covering the root: the plain flip against the root height, as before. */
    X11Frame single = {0, 0, 1920, 1080};
    X11Frame r = X11FrameToRoot(single, (X11Frame){10, 20, 100, 50});
    CHECK(near(r.x, 10) && near(r.y, 1010) && near(r.width, 100) && near(r.height, 50),
          "single monitor: %g,%g %gx%g", r.x, r.y, r.width, r.height);

    /* The main monitor is the right one of two side by side; the left one starts at root x 0. */
    X11Frame right = {1920, 0, 2560, 1440};
    r = X11FrameToRoot(right, (X11Frame){-1820, 1140, 300, 300});
    CHECK(near(r.x, 100) && near(r.y, 0), "a window at the top of the left monitor lands at root 100,0: %g,%g", r.x, r.y);
    X11Frame g = X11FrameFromRoot(right, (X11Frame){100, 0, 300, 300});
    CHECK(near(g.x, -1820) && near(g.y, 1140), "and converts back: %g,%g", g.x, g.y);
    r = X11FrameToRoot(right, (X11Frame){0, 0, 2560, 1440});
    CHECK(near(r.x, 1920) && near(r.y, 0), "the main monitor's own frame maps onto its root rectangle");

    /* The main monitor lower than its neighbour: root y does not start at the top. */
    X11Frame lower = {0, 360, 1920, 1080};
    r = X11FrameToRoot(lower, (X11Frame){0, 0, 1920, 1080});
    CHECK(near(r.x, 0) && near(r.y, 360), "bottom-left of the main monitor is its bottom edge: %g,%g", r.x, r.y);

    /* A taller monitor on the left of the main one: its Cocoa frame starts below the main monitor's bottom edge. */
    X11Frame beside = {1920, 200, 1920, 1080};
    r = X11FrameToRoot(beside, (X11Frame){-1920, -160, 1920, 1440});
    CHECK(near(r.x, 0) && near(r.y, 0) && near(r.width, 1920) && near(r.height, 1440),
          "taller left monitor maps onto root 0,0 1920x1440: %g,%g %gx%g", r.x, r.y, r.width, r.height);
    g = X11FrameFromRoot(beside, (X11Frame){0, 0, 1920, 1440});
    CHECK(near(g.x, -1920) && near(g.y, -160), "and converts back: %g,%g", g.x, g.y);

    /* A main monitor with a negative root origin (XRandR allows it) keeps its own rectangle. */
    X11Frame negative = {-100, 50, 640, 480};
    r = X11FrameToRoot(negative, (X11Frame){0, 0, 640, 480});
    CHECK(near(r.x, -100) && near(r.y, 50), "negative-origin main monitor: %g,%g", r.x, r.y);

    /* Round trip over a grid of layouts and frames. */
    X11Frame primaries[] = {single, right, lower, {-100, 50, 640, 480}};
    int bad = 0;
    for (int p = 0; p < 4; p++)
        for (int x = -2000; x <= 2000; x += 250)
            for (int y = -1500; y <= 1500; y += 250) {
                X11Frame f = {x, y, 123, 77};
                X11Frame back = X11FrameFromRoot(primaries[p], X11FrameToRoot(primaries[p], f));
                if (!near(back.x, f.x) || !near(back.y, f.y) || !near(back.width, f.width) ||
                    !near(back.height, f.height))
                    bad++;
            }
    CHECK(bad == 0, "round trip failed %d times", bad);
}

static void displayIDs(void) {
    /* Output 3 (index 2) is the main monitor; output 2 is off. */
    X11Monitor layout[] = {active(10, 1920, 0, 2560, 1440), inactive(11), active(12, 0, 0, 1920, 1080)};
    int primary = X11MonitorsPickPrimary(layout, 3, 12);
    int out[3];
    X11MonitorsOrder(layout, 3, primary, out);
    /* The listing is main, other active, inactive; each entry keeps the ID of its own output. */
    unsigned int expected[] = {3, 1, 2};
    for (int n = 0; n < 3; n++)
        CHECK(X11MonitorDisplayID(out[n]) == expected[n], "listing position %d has display ID %u, expected %u", n,
              X11MonitorDisplayID(out[n]), expected[n]);
    /* CGMainDisplayID is the ID of the first listed monitor with a frame. */
    CHECK(X11MonitorDisplayID(out[0]) == 3 && layout[out[0]].width == 1920, "the main display is ID 3, 1920 wide");
    /* An ID is the output index plus one, so ID 0 (kCGNullDirectDisplay) never names an output. */
    CHECK(X11MonitorDisplayID(0) == 1, "output 0 is display 1");
    for (int i = 0; i < 3; i++)
        CHECK(X11MonitorDisplayID(i) != 0, "no output has the null display ID");
}

/* The three global spaces (Cocoa y up, CoreGraphics y down, root) must agree with each other for every monitor of a
 * layout: NSScreen.frame, CGDisplayBounds and the pointer are derived from the same root rectangles. */
static void conventionFor(X11Frame primary, X11Frame monitor, const char *name) {
    /* NSScreen.frame: Cocoa, y up from the main monitor's bottom-left corner. */
    X11Frame cocoa = X11FrameFromRoot(primary, monitor);
    /* CGDisplayBounds: the same frame flipped against the main monitor's height (CGDirectDisplay.m). */
    CGDisplayGeometryPoint flippedOrigin =
            CGDisplayGeometryFlip(primary.height, (CGDisplayGeometryPoint){cocoa.x, cocoa.y + cocoa.height});
    X11Point cgOrigin = {flippedOrigin.x, flippedOrigin.y};
    CHECK(near(cgOrigin.x, monitor.x - primary.x) && near(cgOrigin.y, monitor.y - primary.y),
          "%s: CG bounds origin %g,%g is not the root corner minus the main monitor's origin", name, cgOrigin.x,
          cgOrigin.y);

    /* The pointer on the monitor's top-left pixel. */
    X11Point root = {monitor.x, monitor.y};
    X11Point cocoaPointer = X11PointFromRoot(primary, root);
    X11Point cgPointer = X11CGPointFromRoot(primary, root);
    CHECK(near(cgPointer.x, cgOrigin.x) && near(cgPointer.y, cgOrigin.y),
          "%s: CGEventGetLocation %g,%g differs from CGDisplayBounds origin %g,%g", name, cgPointer.x, cgPointer.y,
          cgOrigin.x, cgOrigin.y);
    CHECK(near(cocoaPointer.x, cocoa.x) && near(cocoaPointer.y, cocoa.y + cocoa.height),
          "%s: +[NSEvent mouseLocation] %g,%g is not the top-left of NSScreen.frame", name, cocoaPointer.x,
          cocoaPointer.y);
    CGDisplayGeometryPoint flipped = CGDisplayGeometryFlip(primary.height, (CGDisplayGeometryPoint){cocoaPointer.x, cocoaPointer.y});
    CHECK(near(flipped.x, cgPointer.x) && near(flipped.y, cgPointer.y), "%s: Cocoa and CG pointers are one flip apart",
          name);

    /* Round trips: warping to the pointer you read lands on the same root pixel in both spaces. */
    X11Point back = X11CGPointToRoot(primary, cgPointer);
    CHECK(near(back.x, root.x) && near(back.y, root.y), "%s: CGWarpMouseCursorPosition(CGEventGetLocation) round trip",
          name);
    back = X11PointToRoot(primary, cocoaPointer);
    CHECK(near(back.x, root.x) && near(back.y, root.y), "%s: Cocoa pointer round trip", name);
    CGDisplayGeometryPoint viaCG = CGDisplayGeometryFlip(primary.height, (CGDisplayGeometryPoint){cocoaPointer.x, cocoaPointer.y});
    back = X11CGPointToRoot(primary, (X11Point){viaCG.x, viaCG.y});
    CHECK(near(back.x, root.x) && near(back.y, root.y), "%s: warp to the Cocoa pointer through the CG flip", name);
}

static void convention(void) {
    X11Frame single = {0, 0, 1920, 1080};
    conventionFor(single, single, "single monitor");

    /* Two side by side, the right one main. */
    X11Frame left = {0, 0, 1920, 1080}, right = {1920, 0, 2560, 1440};
    conventionFor(right, right, "side by side, main");
    conventionFor(right, left, "side by side, other");
    X11Frame leftFrame = X11FrameFromRoot(right, left);
    CHECK(near(leftFrame.x, -1920) && near(leftFrame.y, 360), "the left monitor starts at x -1920 and its bottom is 360 above the main's: %g,%g",
          leftFrame.x, leftFrame.y);

    /* Stacked, the lower one main: a monitor above the main one has a negative CG y and a Cocoa y above its top. */
    X11Frame top = {0, 0, 1920, 1080}, lower = {0, 1080, 1920, 1080};
    conventionFor(lower, lower, "stacked, main");
    conventionFor(lower, top, "stacked, other");
    X11Frame topFrame = X11FrameFromRoot(lower, top);
    CHECK(near(topFrame.y, 1080), "the monitor above the main one starts at Cocoa y 1080: %g", topFrame.y);
    X11Point topCG = X11CGPointFromRoot(lower, (X11Point){0, 0});
    CHECK(near(topCG.y, -1080), "and at CG y -1080: %g", topCG.y);

    /* The main monitor is not at the root origin. */
    X11Frame inset = {100, 50, 640, 480};
    conventionFor(inset, inset, "inset main");
    X11Point corner = X11CGPointFromRoot(inset, (X11Point){100, 50});
    CHECK(near(corner.x, 0) && near(corner.y, 0), "the main monitor's top-left pixel is CG 0,0");
    X11Point cocoaCorner = X11PointFromRoot(inset, (X11Point){100, 50});
    CHECK(near(cocoaCorner.x, 0) && near(cocoaCorner.y, 480), "and Cocoa 0,height");

    /* HiDPI: the same conversions in points, with the root rectangle and the pointer divided by the scale. */
    X11Frame hidpi = {0, 0, 1920 / 2.0, 1080 / 2.0};
    X11Point pointer = X11CGPointFromRoot(hidpi, (X11Point){1000 / 2.0, 400 / 2.0});
    CHECK(near(pointer.x, 500) && near(pointer.y, 200), "points at 2x");
}

static void setCrtc(Display *display, int x, int y, unsigned width, unsigned height, bool enable) {
    Window root = DefaultRootWindow(display);
    XRRScreenResources *resources = XRRGetScreenResources(display, root);
    RRMode mode = None;
    if (enable) {
        XRRModeInfo info;
        memset(&info, 0, sizeof info);
        char name[32];
        snprintf(name, sizeof name, "%ux%ux", width, height);
        info.width = width;
        info.height = height;
        info.dotClock = (unsigned long) (width + 160) * (height + 45) * 60;
        info.hTotal = width + 160;
        info.vTotal = height + 45;
        info.hSyncStart = width + 16;
        info.hSyncEnd = width + 112;
        info.vSyncStart = height + 10;
        info.vSyncEnd = height + 12;
        info.name = name;
        info.nameLength = (unsigned) strlen(name);
        mode = XRRCreateMode(display, root, &info);
        XRRAddOutputMode(display, resources->outputs[0], mode);
    }
    Status status = XRRSetCrtcConfig(display, resources, resources->crtcs[0], CurrentTime, x, y, mode, RR_Rotate_0,
                                     enable ? resources->outputs : NULL, enable ? 1 : 0);
    XSync(display, False);
    CHECK(status == RRSetConfigSuccess, "XRRSetCrtcConfig failed: %d", status);
    XRRFreeScreenResources(resources);
}

static void randr(Display *display) {
    Window root = DefaultRootWindow(display);
    int count, primary;
    X11Monitor *monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors != NULL && count == 1, "one output on Xvfb (count %d)", count);
    if (!monitors)
        return;
    CHECK(primary == 0 && monitors[0].active, "the only output is active and is the main display");
    CHECK(monitors[0].x == 0 && monitors[0].y == 0 && (int) monitors[0].width == DisplayWidth(display, 0) &&
                  (int) monitors[0].height == DisplayHeight(display, 0),
          "it covers the root: %d,%d %ux%u", monitors[0].x, monitors[0].y, monitors[0].width, monitors[0].height);
    RROutput output = monitors[0].output;
    free(monitors);

    /* The main monitor is not at the root origin: its rectangle, not the root, is the reference. */
    setCrtc(display, 100, 50, 640, 480, true);
    monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors && primary == 0 && monitors[0].x == 100 && monitors[0].y == 50 && monitors[0].width == 640 &&
                  monitors[0].height == 480,
          "moved CRTC is reported at its root position");
    free(monitors);

    /* The conversions against a real pointer: warp to a root pixel inside the moved main monitor and read it back. */
    {
        X11Frame main = {100, 50, 640, 480};
        XWarpPointer(display, None, root, 0, 0, 0, 0, 110, 70);
        XSync(display, False);
        Window ignoredRoot, ignoredChild;
        int rootX, rootY, winX, winY;
        unsigned int mask;
        XQueryPointer(display, root, &ignoredRoot, &ignoredChild, &rootX, &rootY, &winX, &winY, &mask);
        CHECK(rootX == 110 && rootY == 70, "the pointer is at root 110,70: %d,%d", rootX, rootY);
        X11Point cg = X11CGPointFromRoot(main, (X11Point){rootX, rootY});
        X11Point cocoa = X11PointFromRoot(main, (X11Point){rootX, rootY});
        CHECK(near(cg.x, 10) && near(cg.y, 20), "CG pointer is 10,20 from the main monitor's top-left: %g,%g", cg.x,
              cg.y);
        CHECK(near(cocoa.x, 10) && near(cocoa.y, 460), "Cocoa pointer is 10,460 above its bottom-left: %g,%g", cocoa.x,
              cocoa.y);
        /* CGWarpMouseCursorPosition(CGEventGetLocation()) must not move the pointer. */
        X11Point target = X11CGPointToRoot(main, cg);
        XWarpPointer(display, None, root, 0, 0, 0, 0, (int) target.x, (int) target.y);
        XSync(display, False);
        XQueryPointer(display, root, &ignoredRoot, &ignoredChild, &rootX, &rootY, &winX, &winY, &mask);
        CHECK(rootX == 110 && rootY == 70, "warping to the CG pointer leaves it where it was: %d,%d", rootX, rootY);
    }

    /* The desktop chooses a primary; it must still be reported. */
    XRRSetOutputPrimary(display, root, output);
    XSync(display, False);
    CHECK(XRRGetOutputPrimary(display, root) == output, "RandR primary was set");
    monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors && primary == 0, "an active RandR primary is the main display");
    free(monitors);

    XRRSetOutputPrimary(display, root, None);
    XSync(display, False);
    monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors && primary == 0, "without a RandR primary the first active output is");
    free(monitors);

    /* Switched off: nothing active, and no main display, instead of a dereference of a missing CRTC. */
    setCrtc(display, 0, 0, 0, 0, false);
    monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors && count == 1 && !monitors[0].active && primary == -1, "a disabled output is inactive, no main display");
    if (monitors) {
        int order[1];
        X11MonitorsOrder(monitors, count, primary, order);
        CHECK(order[0] == 0, "inactive outputs are still listed");
    }
    free(monitors);
}

int main(void) {
    pickPrimary();
    order();
    frames();
    displayIDs();
    convention();
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-monitors.sh\n");
        return 2;
    }
    randr(display);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
