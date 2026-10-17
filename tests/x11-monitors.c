// Host test for AppKit/X11.backend/X11Monitors.h: which monitor is the main display and in which order the
// monitors are listed.
// The RandR part runs on a real X server; use tests/x11-monitors.sh, which starts its own Xvfb.
// Build: cc x11-monitors.c -lX11 -lXrandr
#include "../AppKit/X11.backend/X11Monitors.h"
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

    X11Monitor off[] = {inactive(10), inactive(11)};
    X11MonitorsOrder(off, 2, -1, out);
    CHECK(out[0] == 0 && out[1] == 1, "nothing active keeps server order");
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
