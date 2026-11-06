/* RandR event handling for the X11 backend.
 *
 * RandR events are ordinary extension events: the X event type is the extension's event base plus
 * RRScreenChangeNotify (0) or RRNotify (1, carrying a CRTC, output or property subtype). They are not Generic
 * Extension events, so xgeneric.evtype plays no part.
 *
 * Xlib caches the screen size that DisplayWidth and DisplayHeight return and refreshes it only when the client
 * passes the RRScreenChangeNotify to XRRUpdateConfiguration. Code that flips a window's y coordinate against
 * DisplayHeight places windows against the old size until that happens.
 *
 * Only Xlib and RandR, so tests/x11-randr-events.c can drive it against Xvfb. */
#ifndef X11_RANDR_H
#define X11_RANDR_H

#include <X11/Xlib.h>
#include <X11/extensions/Xrandr.h>
#include <stdbool.h>

/* Output properties (the EDID among them) are not part of the layout. The X server rewrites them whenever it
 * polls the outputs, so a client that re-read the layout on every property event could keep the server busy. */
#define X11_RANDR_EVENT_MASK (RRScreenChangeNotifyMask | RRCrtcChangeNotifyMask | RROutputChangeNotifyMask)

/* Whether event reports a change of the screen or monitor layout: RRScreenChangeNotify, or an RRNotify for a
 * CRTC or output change. eventBase is 0 when the server has no RandR. */
static inline bool X11RandRIsLayoutChange(const XEvent *event, int eventBase) {
    if (eventBase == 0)
        return false;
    if (event->type == eventBase + RRScreenChangeNotify)
        return true;
    if (event->type != eventBase + RRNotify)
        return false;
    int subtype = ((const XRRNotifyEvent *) event)->subtype;
    return subtype == RRNotify_CrtcChange || subtype == RRNotify_OutputChange;
}

/* Applies a layout-change event to Xlib's cached screen size. Returns whether event was one. */
static inline bool X11RandRHandleLayoutChange(XEvent *event, int eventBase) {
    if (!X11RandRIsLayoutChange(event, eventBase))
        return false;
    if (event->type == eventBase + RRScreenChangeNotify)
        XRRUpdateConfiguration(event);
    return true;
}

#endif
