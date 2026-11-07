// Host test for CGWarpMouseCursorPosition / CGDisplayMoveCursorToPoint on the X11 backend: the conversion from
// CoreGraphics' global space (origin at the main display's top-left, y down, points) to the pointer's device
// pixel and back to what CGEventGetLocation reports, using the same functions the backends use
// (CoreGraphics/CGDisplayGeometry.h, CoreGraphics/X11.backend/X11Monitors.h).
//
// Multi-monitor layouts are a pure-C model: Xvfb exposes one CRTC, so secondary monitors with negative or offset
// origins are synthetic arrays of root rectangles. The single-monitor case, the moved main CRTC and the clipping
// also run against a real pointer on Xvfb. Use tests/cg-warp-mouse.sh. Build: cc cg-warp-mouse.c -lX11 -lXrandr -lm
#include "../CoreGraphics/X11.backend/X11Monitors.h"
#include "../CoreGraphics/CGDisplayGeometry.h"
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

static bool near(double a, double b) {
    return fabs(a - b) < 1e-9;
}

typedef struct {
    X11Frame monitors[4]; /* root rectangles, device pixels */
    int count;
    int primary;
    double scale;
} Layout;

static X11Frame mainRoot(const Layout *l) {
    return l->monitors[l->primary];
}

/* CGDisplayBounds of monitor i: its root rectangle minus the main monitor's origin, in points. */
static CGDisplayGeometryRect bounds(const Layout *l, int i) {
    X11Frame p = mainRoot(l), m = l->monitors[i];
    CGDisplayGeometryRect r = {(m.x - p.x) / l->scale, (m.y - p.y) / l->scale, m.width / l->scale,
                               m.height / l->scale};
    return r;
}

static CGDisplayGeometryRect desktop(const Layout *l) {
    CGDisplayGeometryRect d = {0, 0, 0, 0};
    for (int i = 0; i < l->count; i++)
        d = CGDisplayGeometryUnion(d, bounds(l, i));
    return d;
}

/* CGWarpMouseCursorPosition on the X11 backend: clip, flip into Cocoa, -[X11Display warpMouse:] to a root pixel. */
static void warp(const Layout *l, CGDisplayGeometryPoint cg, long *rootX, long *rootY) {
    X11Frame p = mainRoot(l);
    CGDisplayGeometryPoint clipped = CGDisplayGeometryClamp(desktop(l), l->scale, cg);
    CGDisplayGeometryPoint cocoa = CGDisplayGeometryFlip(p.height / l->scale, clipped);
    X11Point root = X11PointToRoot(p, (X11Point){cocoa.x * l->scale, cocoa.y * l->scale});
    *rootX = lround(root.x);
    *rootY = lround(root.y);
}

/* CGEventGetLocation / CGSCurrentInputPointerPosition (CGSConnectionX11 -mouseLocation) for a root pixel. */
static CGDisplayGeometryPoint read(const Layout *l, long rootX, long rootY) {
    X11Point p = X11CGPointFromRoot(mainRoot(l), (X11Point){(double) rootX, (double) rootY});
    CGDisplayGeometryPoint cg = {p.x / l->scale, p.y / l->scale};
    return cg;
}

static void corners(const Layout *l, const char *name) {
    for (int i = 0; i < l->count; i++) {
        CGDisplayGeometryRect b = bounds(l, i);
        double pixel = 1.0 / l->scale;
        CGDisplayGeometryPoint pts[4] = {{b.x, b.y},
                                         {b.x + b.width - pixel, b.y},
                                         {b.x, b.y + b.height - pixel},
                                         {b.x + b.width - pixel, b.y + b.height - pixel}};
        X11Frame m = l->monitors[i];
        long expectX[4] = {(long) m.x, (long) (m.x + m.width - 1), (long) m.x, (long) (m.x + m.width - 1)};
        long expectY[4] = {(long) m.y, (long) m.y, (long) (m.y + m.height - 1), (long) (m.y + m.height - 1)};
        for (int c = 0; c < 4; c++) {
            long rx, ry;
            warp(l, pts[c], &rx, &ry);
            CHECK(rx == expectX[c] && ry == expectY[c], "%s: display %d corner %d warps to root %ld,%ld, expected %ld,%ld",
                  name, i, c, rx, ry, expectX[c], expectY[c]);
            CGDisplayGeometryPoint back = read(l, rx, ry);
            CHECK(near(back.x, pts[c].x) && near(back.y, pts[c].y),
                  "%s: display %d corner %d warp then read gives %g,%g, expected %g,%g", name, i, c, back.x, back.y,
                  pts[c].x, pts[c].y);
        }
    }
}

static void roundTrips(const Layout *l, const char *name) {
    /* Warp to what was read changes nothing (idempotent after the first rounding), for points on and between pixels. */
    double offsets[] = {0, 0.1, 0.3, 0.5, 0.74, 3.25, 10.3};
    CGDisplayGeometryRect d = desktop(l);
    int bad = 0;
    for (size_t a = 0; a < sizeof offsets / sizeof *offsets; a++)
        for (size_t b = 0; b < sizeof offsets / sizeof *offsets; b++) {
            CGDisplayGeometryPoint p = {d.x + 20 + offsets[a], d.y + 30 + offsets[b]};
            long rx, ry, rx2, ry2;
            warp(l, p, &rx, &ry);
            CGDisplayGeometryPoint back = read(l, rx, ry);
            warp(l, back, &rx2, &ry2);
            /* read(warp(p)) is p rounded to the nearest device pixel of the root window (ties away from zero in
             * root coordinates, where the pixel exists), then read back in points */
            X11Frame m = mainRoot(l);
            double ex = (double) lround(p.x * l->scale + m.x) - m.x, ey = (double) lround(p.y * l->scale + m.y) - m.y;
            ex /= l->scale;
            ey /= l->scale;
            if (rx2 != rx || ry2 != ry || !near(back.x, ex) || !near(back.y, ey))
                bad++;
        }
    CHECK(bad == 0, "%s: %d warp/read round trips differ from the rounding rule", name, bad);
}

static void clipping(const Layout *l, const char *name) {
    CGDisplayGeometryRect d = desktop(l);
    double pixel = 1.0 / l->scale;
    long rx, ry;
    warp(l, (CGDisplayGeometryPoint){-1e6, -1e6}, &rx, &ry);
    CGDisplayGeometryPoint back = read(l, rx, ry);
    CHECK(near(back.x, d.x) && near(back.y, d.y), "%s: far top-left clips to the desktop corner %g,%g, got %g,%g", name,
          d.x, d.y, back.x, back.y);
    warp(l, (CGDisplayGeometryPoint){1e6, 1e6}, &rx, &ry);
    back = read(l, rx, ry);
    CHECK(near(back.x, d.x + d.width - pixel) && near(back.y, d.y + d.height - pixel),
          "%s: far bottom-right clips one pixel inside the desktop, got %g,%g", name, back.x, back.y);
    warp(l, (CGDisplayGeometryPoint){d.x + d.width, d.y + d.height}, &rx, &ry);
    back = read(l, rx, ry);
    CHECK(near(back.x, d.x + d.width - pixel) && near(back.y, d.y + d.height - pixel),
          "%s: the exclusive far edge is moved one pixel in", name);
}

static void displayRelative(const Layout *l, const char *name) {
    /* CGDisplayMoveCursorToPoint(display, p): p is relative to that display's upper-left corner. */
    for (int i = 0; i < l->count; i++) {
        CGDisplayGeometryRect b = bounds(l, i);
        CGDisplayGeometryPoint rel = {10, 20};
        CGDisplayGeometryPoint global = CGDisplayGeometryDisplayToGlobal(b, rel);
        long rx, ry;
        warp(l, global, &rx, &ry);
        X11Frame m = l->monitors[i];
        CHECK(rx == (long) (m.x + 10 * l->scale) && ry == (long) (m.y + 20 * l->scale),
              "%s: display %d point 10,20 lands at root %ld,%ld, expected %g,%g", name, i, rx, ry, m.x + 10 * l->scale,
              m.y + 20 * l->scale);
        CGDisplayGeometryPoint back = read(l, rx, ry);
        CHECK(near(back.x, global.x) && near(back.y, global.y), "%s: display %d read gives the global point", name, i);
    }
}

static void model(void) {
    Layout single = {{{0, 0, 1920, 1080}}, 1, 0, 1};
    Layout sideBySide = {{{0, 0, 1920, 1080}, {1920, 0, 2560, 1440}}, 2, 1, 1}; /* main on the right */
    Layout stacked = {{{0, 0, 1920, 1080}, {0, 1080, 1920, 1080}}, 2, 1, 1};     /* main lower */
    Layout offset = {{{0, 200, 1280, 720}, {1280, 0, 1920, 1080}}, 2, 0, 1};      /* neighbour taller, main inset */
    Layout hidpi = {{{0, 0, 2560, 1440}, {2560, 0, 1920, 1080}}, 2, 0, 2};
    Layout fractional = {{{0, 0, 1920, 1080}}, 1, 0, 1.5};
    struct {
        const Layout *layout;
        const char *name;
    } all[] = {{&single, "single"},         {&sideBySide, "side by side"}, {&stacked, "stacked"},
               {&offset, "offset origin"},   {&hidpi, "2x"},                {&fractional, "1.5x"}};
    for (size_t i = 0; i < sizeof all / sizeof *all; i++) {
        corners(all[i].layout, all[i].name);
        roundTrips(all[i].layout, all[i].name);
        clipping(all[i].layout, all[i].name);
        displayRelative(all[i].layout, all[i].name);
    }

    /* The reported bug: the top-left point of a 1080-high display used to be treated as bottom-left, so y 100 landed
     * at 980. A point 100 down from the top is root y 100 on the main monitor. */
    long rx, ry;
    warp(&single, (CGDisplayGeometryPoint){50, 100}, &rx, &ry);
    CHECK(rx == 50 && ry == 100, "50,100 down from the top-left is root 50,100, got %ld,%ld", rx, ry);

    /* A display left of the main one has negative global x; one above it negative global y. */
    CGDisplayGeometryRect left = bounds(&sideBySide, 0), top = bounds(&stacked, 0);
    CHECK(near(left.x, -1920) && near(left.y, 0), "left display bounds %g,%g", left.x, left.y);
    CHECK(near(top.x, 0) && near(top.y, -1080), "top display bounds %g,%g", top.x, top.y);
    warp(&sideBySide, (CGDisplayGeometryPoint){-1900, 40}, &rx, &ry);
    CHECK(rx == 20 && ry == 40, "a point on the left display lands at its own root pixel, got %ld,%ld", rx, ry);
    /* The L-shaped dead zone of the offset layout is inside the desktop but on no display: left to the server. */
    CGDisplayGeometryRect deadZone = desktop(&offset);
    CHECK(near(deadZone.width, 3200) && near(deadZone.height, 1080), "desktop of the offset layout is the bounding box");
}

static void live(Display *display) {
    Window root = DefaultRootWindow(display);
    /* Same RandR emulation as the monitor series: shrink and move the only CRTC inside the root. */
    XRRScreenResources *resources = XRRGetScreenResources(display, root);
    XRRModeInfo info;
    memset(&info, 0, sizeof info);
    char name[48];
    snprintf(name, sizeof name, "%ux%ux-warp", 640u, 480u);
    info.width = 640;
    info.height = 480;
    info.dotClock = (unsigned long) (640 + 160) * (480 + 45) * 60;
    info.hTotal = 640 + 160;
    info.vTotal = 480 + 45;
    info.hSyncStart = 640 + 16;
    info.hSyncEnd = 640 + 112;
    info.vSyncStart = 480 + 10;
    info.vSyncEnd = 480 + 12;
    info.name = name;
    info.nameLength = (unsigned) strlen(name);
    RRMode mode = XRRCreateMode(display, root, &info);
    XRRAddOutputMode(display, resources->outputs[0], mode);
    XRRSetCrtcConfig(display, resources, resources->crtcs[0], CurrentTime, 100, 50, mode, RR_Rotate_0,
                     resources->outputs, 1);
    XSync(display, False);
    XRRFreeScreenResources(resources);

    int count, primary;
    X11Monitor *monitors = X11MonitorsCopy(display, &count, &primary);
    CHECK(monitors && count == 1 && primary == 0, "one monitor");
    if (!monitors)
        return;
    Layout l = {{{monitors[0].x, monitors[0].y, monitors[0].width, monitors[0].height}}, 1, 0, 1};
    free(monitors);
    CHECK(l.monitors[0].x == 100 && l.monitors[0].y == 50 && l.monitors[0].width == 640, "CRTC moved to 100,50");

    CGDisplayGeometryPoint pts[] = {{0, 0}, {639, 0}, {0, 479}, {639, 479}, {320, 240}, {-5, -5}, {10000, 10000}};
    CGDisplayGeometryPoint expect[] = {{0, 0}, {639, 0}, {0, 479}, {639, 479}, {320, 240}, {0, 0}, {639, 479}};
    for (size_t i = 0; i < sizeof pts / sizeof *pts; i++) {
        long rx, ry;
        warp(&l, pts[i], &rx, &ry);
        XWarpPointer(display, None, root, 0, 0, 0, 0, (int) rx, (int) ry);
        XSync(display, False);
        Window r, c;
        int px, py, wx, wy;
        unsigned int mask;
        XQueryPointer(display, root, &r, &c, &px, &py, &wx, &wy, &mask);
        CGDisplayGeometryPoint got = read(&l, px, py);
        CHECK(near(got.x, expect[i].x) && near(got.y, expect[i].y),
              "live pointer after warping to %g,%g reads %g,%g, expected %g,%g", pts[i].x, pts[i].y, got.x, got.y,
              expect[i].x, expect[i].y);
    }
}

int main(void) {
    model();
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/cg-warp-mouse.sh\n");
        return 2;
    }
    live(display);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
