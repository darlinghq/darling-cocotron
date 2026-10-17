// Host test for AppKit/X11.backend/X11RandR.h against a real X server: RandR layout changes arrive as plain
// extension events (base + RRScreenChangeNotify, base + RRNotify), not as GenericEvent, and Xlib's cached screen
// size stays stale until the backend passes the screen-change event to XRRUpdateConfiguration. Use
// tests/x11-randr-events.sh, which runs it on its own Xvfb.
// Build: cc x11-randr-events.c -lX11 -lXrandr
#include "../AppKit/X11.backend/X11RandR.h"
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

int main(void) {
    Display *backend = XOpenDisplay(NULL), *other = XOpenDisplay(NULL);
    if (!backend || !other) {
        printf("no X display: run through tests/x11-randr-events.sh\n");
        return 2;
    }
    int eventBase, errorBase;
    if (!XRRQueryExtension(backend, &eventBase, &errorBase)) {
        printf("the X server has no RandR\n");
        return 2;
    }
    Window root = DefaultRootWindow(backend);
    XRRSelectInput(backend, root, X11_RANDR_EVENT_MASK);
    XSync(backend, False);

    int oldWidth = DisplayWidth(backend, 0), oldHeight = DisplayHeight(backend, 0);
    CHECK(!X11RandRIsLayoutChange(&(XEvent){.type = 0}, eventBase), "an unrelated event");
    CHECK(!X11RandRIsLayoutChange(&(XEvent){.type = eventBase + RRNotify}, 0), "no RandR, no layout change");

    /* Another client resizes the screen and re-creates the monitor, as a display settings tool would. */
    Window otherRoot = DefaultRootWindow(other);
    XRRScreenResources *resources = XRRGetScreenResources(other, otherRoot);
    XRRSetCrtcConfig(other, resources, resources->crtcs[0], CurrentTime, 0, 0, None, RR_Rotate_0, NULL, 0);
    XRRSetScreenSize(other, otherRoot, 1024, 600, 270, 160);
    XRRModeInfo info;
    memset(&info, 0, sizeof info);
    info.width = 1024;
    info.height = 600;
    info.dotClock = 60000000;
    info.hTotal = 1200;
    info.vTotal = 650;
    info.hSyncStart = 1050;
    info.hSyncEnd = 1100;
    info.vSyncStart = 610;
    info.vSyncEnd = 620;
    info.name = "1024x600x";
    info.nameLength = 9;
    RRMode mode = XRRCreateMode(other, otherRoot, &info);
    XRRAddOutputMode(other, resources->outputs[0], mode);
    XRRSetCrtcConfig(other, resources, resources->crtcs[0], CurrentTime, 0, 0, mode, RR_Rotate_0,
                     resources->outputs, 1);
    XSync(other, False);
    XSync(backend, False);

    int screenChanges = 0, notifies = 0, generic = 0, unhandled = 0, handled = 0;
    int widthBeforeUpdate = -1, heightBeforeUpdate = -1;
    while (XPending(backend) > 0) {
        XEvent event;
        XNextEvent(backend, &event);
        if (event.type == GenericEvent)
            generic++;
        if (event.type == eventBase + RRScreenChangeNotify) {
            if (screenChanges++ == 1) { /* the one that carries the new size */
                widthBeforeUpdate = DisplayWidth(backend, 0);
                heightBeforeUpdate = DisplayHeight(backend, 0);
            }
        }
        if (event.type == eventBase + RRNotify)
            notifies++;
        if (X11RandRHandleLayoutChange(&event, eventBase))
            handled++;
        else
            unhandled++;
    }

    CHECK(generic == 0, "RandR events are not GenericEvent (%d seen)", generic);
    CHECK(screenChanges > 0, "RRScreenChangeNotify events arrived");
    CHECK(notifies > 0, "RRNotify events arrived (CRTC and output changes)");
    CHECK(unhandled == 0, "every RandR event is recognised as a layout change (%d were not)", unhandled);
    CHECK(handled == screenChanges + notifies, "handled %d, expected %d", handled, screenChanges + notifies);
    CHECK(widthBeforeUpdate == oldWidth && heightBeforeUpdate == oldHeight,
          "Xlib's cached size is stale until XRRUpdateConfiguration (%dx%d vs old %dx%d)", widthBeforeUpdate,
          heightBeforeUpdate, oldWidth, oldHeight);
    CHECK(DisplayWidth(backend, 0) == 1024 && DisplayHeight(backend, 0) == 600,
          "after handling the events the cached size is the new one (%dx%d)", DisplayWidth(backend, 0),
          DisplayHeight(backend, 0));

    XCloseDisplay(other);
    XCloseDisplay(backend);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
