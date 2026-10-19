/* Monitor list and primary-monitor selection for the X11 backend.
 *
 * macOS lists the main display first ([NSScreen screens][0], CGMainDisplayID) and puts the global coordinate
 * origin at it; the other displays sit at offsets from it, possibly negative. X11 numbers outputs in server
 * order and positions CRTCs relative to the top-left of the root window. This header reads the RandR outputs and
 * decides which one plays the main display: the RandR primary if it is active, otherwise the first active
 * output.
 *
 * Only Xlib and RandR, so tests/x11-monitors.c can drive it against Xvfb. */
#ifndef X11_MONITORS_H
#define X11_MONITORS_H

#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <stdbool.h>
#include <stdlib.h>

typedef struct {
    RROutput output;
    bool active;  /* the output has a CRTC with a mode */
    int x, y;     /* root coordinates, device pixels; 0 when inactive */
    unsigned int width, height;
} X11Monitor;

/* Index of the monitor that is the main display, or -1 when none is active. primaryOutput is what
 * XRRGetOutputPrimary reported (None when the desktop has not chosen one). */
static inline int X11MonitorsPickPrimary(const X11Monitor *monitors, int count, RROutput primaryOutput) {
    int first = -1;
    for (int i = 0; i < count; i++) {
        if (!monitors[i].active)
            continue;
        if (primaryOutput != None && monitors[i].output == primaryOutput)
            return i;
        if (first < 0)
            first = i;
    }
    return first;
}

/* Fills order with indexes into monitors: the primary first, then the other active monitors in server order, then
 * the inactive outputs. order has room for count entries. */
static inline void X11MonitorsOrder(const X11Monitor *monitors, int count, int primary, int *order) {
    int next = 0;
    if (primary >= 0 && primary < count)
        order[next++] = primary;
    for (int i = 0; i < count; i++)
        if (i != primary && monitors[i].active)
            order[next++] = i;
    for (int i = 0; i < count; i++)
        if (i != primary && !monitors[i].active)
            order[next++] = i;
}

/* Reads the outputs in server order into a malloc'ed array of *count entries (free it), and sets *primary to
 * X11MonitorsPickPrimary's choice. Returns NULL when the server has no RandR or the query failed; *count is 0. */
static inline X11Monitor *X11MonitorsCopy(Display *display, int *count, int *primary) {
    *count = 0;
    *primary = -1;
    int eventBase, errorBase;
    if (!XRRQueryExtension(display, &eventBase, &errorBase))
        return NULL;
    Window root = DefaultRootWindow(display);
    XRRScreenResources *resources = XRRGetScreenResources(display, root);
    if (resources == NULL)
        return NULL;
    X11Monitor *monitors = calloc(resources->noutput > 0 ? (size_t) resources->noutput : 1, sizeof *monitors);
    if (monitors == NULL) {
        XRRFreeScreenResources(resources);
        return NULL;
    }
    for (int i = 0; i < resources->noutput; i++) {
        monitors[i].output = resources->outputs[i];
        XRROutputInfo *output = XRRGetOutputInfo(display, resources, resources->outputs[i]);
        if (output == NULL)
            continue;
        if (output->crtc != None) {
            XRRCrtcInfo *crtc = XRRGetCrtcInfo(display, resources, output->crtc);
            if (crtc != NULL) {
                if (crtc->mode != None && crtc->width > 0 && crtc->height > 0) {
                    monitors[i].active = true;
                    monitors[i].x = crtc->x;
                    monitors[i].y = crtc->y;
                    monitors[i].width = crtc->width;
                    monitors[i].height = crtc->height;
                }
                XRRFreeCrtcInfo(crtc);
            }
        }
        XRRFreeOutputInfo(output);
    }
    *count = resources->noutput;
    XRRFreeScreenResources(resources);
    *primary = X11MonitorsPickPrimary(monitors, *count, XRRGetOutputPrimary(display, root));
    return monitors;
}

/* Rectangles in one unit (device pixels or logical points, as long as the caller is consistent). */
typedef struct {
    double x, y, width, height;
} X11Frame;

/* Converts a frame in Cocoa's global space (origin at the bottom-left corner of the main monitor, y up) to a
 * rectangle in root coordinates (origin at the top-left of the root window, y down). primaryRoot is the main
 * monitor's rectangle in root coordinates. With the main monitor covering the whole root this is the plain
 * flip against the root's height. */
static inline X11Frame X11FrameToRoot(X11Frame primaryRoot, X11Frame frame) {
    X11Frame root = {frame.x + primaryRoot.x, (primaryRoot.y + primaryRoot.height) - frame.y - frame.height,
                     frame.width, frame.height};
    return root;
}

/* The inverse of X11FrameToRoot. */
static inline X11Frame X11FrameFromRoot(X11Frame primaryRoot, X11Frame root) {
    X11Frame frame = {root.x - primaryRoot.x, (primaryRoot.y + primaryRoot.height) - root.y - root.height,
                      root.width, root.height};
    return frame;
}

/* A display's CGDirectDisplayID is tied to the RandR output it drives (output index + 1), not to its place in the
 * listing: the mode functions address the output by that index, and the listing starts with the main monitor. */
static inline unsigned int X11MonitorDisplayID(int outputIndex) {
    return (unsigned int) outputIndex + 1;
}

#endif
