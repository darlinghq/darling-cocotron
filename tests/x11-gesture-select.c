// Host test for AppKit/X11.backend/X11InputMask.h against a real X server: the server negotiates XInput 2.4, a
// mask with touch and pinch events together is accepted, and it is the only mask the client has, because each
// XISelectEvents request replaces the one before. Selecting the pinch events without all three is refused with
// BadValue, as the XI2 protocol says. A server cannot be made to send a pinch without a touchpad, so the delivery
// of events is covered by tests/appkit-x11-pinch-gesture-dispatch.m. Use tests/x11-gesture-select.sh, which runs it
// on its own Xvfb.
// Build: cc x11-gesture-select.c -lX11 -lXi
#include "../AppKit/X11.backend/X11InputMask.h"
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <stdio.h>

#ifndef X11_XI_GESTURES
int main(void) {
    printf("SKIP: the XInput headers are older than 2.4\n");
    return 0;
}
#else
static int failures, checks, lastError;

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

static int onError(Display *display, XErrorEvent *error) {
    (void) display;
    lastError = error->error_code;
    return 0;
}

/* Selects the mask on the window for all master devices; the error the server answered, 0 for none. */
static int selectMask(Display *display, Window window, unsigned char *bits) {
    XIEventMask mask = {.deviceid = XIAllMasterDevices, .mask_len = X11InputMaskLength, .mask = bits};
    lastError = 0;
    XISelectEvents(display, window, &mask, 1);
    XSync(display, False);
    return lastError;
}

/* Which of the events the window has selected for all master devices, as a bit mask. */
static bool selected(Display *display, Window window, int event) {
    int count = 0;
    bool found = false;
    XIEventMask *masks = XIGetSelectedEvents(display, window, &count);
    for (int i = 0; i < count; i++)
        if (masks[i].deviceid == XIAllMasterDevices && event / 8 < masks[i].mask_len && XIMaskIsSet(masks[i].mask, event))
            found = true;
    if (masks)
        XFree(masks);
    return found;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-gesture-select.sh\n");
        return 2;
    }
    XSetErrorHandler(onError);

    unsigned char bits[X11InputMaskLength];
    X11InputEventMask(bits, false, false);
    CHECK(!XIMaskIsSet(bits, XI_TouchBegin) && !XIMaskIsSet(bits, XI_GesturePinchBegin), "an empty mask selects nothing");
    X11InputEventMask(bits, true, false);
    CHECK(XIMaskIsSet(bits, XI_TouchBegin) && XIMaskIsSet(bits, XI_TouchUpdate) && XIMaskIsSet(bits, XI_TouchEnd) &&
                  !XIMaskIsSet(bits, XI_GesturePinchBegin),
          "touch alone selects the three touch events");
    X11InputEventMask(bits, true, true);
    CHECK(XIMaskIsSet(bits, XI_TouchEnd) && XIMaskIsSet(bits, XI_GesturePinchBegin) && XIMaskIsSet(bits, XI_GesturePinchUpdate) &&
                  XIMaskIsSet(bits, XI_GesturePinchEnd) && !XIMaskIsSet(bits, XI_GestureSwipeBegin),
          "touch and pinch select all six, and no swipe");

    int major = 2, minor = 4;
    CHECK(XIQueryVersion(display, &major, &minor) == Success && major == 2 && minor >= 4,
          "the server speaks XInput 2.4, it answered %d.%d", major, minor);

    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 100, 100, 0, 0, 0);
    CHECK(selectMask(display, window, bits) == 0, "the combined mask is accepted");
    CHECK(selected(display, window, XI_TouchBegin) && selected(display, window, XI_GesturePinchBegin) &&
                  selected(display, window, XI_GesturePinchUpdate) && selected(display, window, XI_GesturePinchEnd),
          "the server holds touch and pinch events together");

    unsigned char touchOnly[X11InputMaskLength];
    X11InputEventMask(touchOnly, true, false);
    CHECK(selectMask(display, window, touchOnly) == 0 && selected(display, window, XI_TouchBegin) &&
                  !selected(display, window, XI_GesturePinchBegin),
          "a second request replaces the first, so the pinch events must be in every mask");

    unsigned char partial[X11InputMaskLength];
    X11InputEventMask(partial, false, false);
    XISetMask(partial, XI_GesturePinchUpdate);
    CHECK(selectMask(display, window, partial) == BadValue, "pinch events cannot be selected without all three (error %d)",
          lastError);

    printf("RESULT checks=%d failures=%d\n", checks, failures);
    XCloseDisplay(display);
    return failures ? 1 : 0;
}
#endif
