// Host test for AppKit/X11.backend/X11PointerMotion.h: a window hears the pointer move with no button down only
// when it selected PointerMotionMask. The X server decides what is delivered, so the test moves the pointer
// over a window with each mask the header chooses and counts the MotionNotify events. Use
// tests/x11-pointer-motion.sh, which runs it on its own Xvfb.
// Build: cc x11-pointer-motion.c -lX11
#include "../AppKit/X11.backend/X11PointerMotion.h"
#include <X11/Xlib.h>
#include <stdio.h>
#include <unistd.h>

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

/* Moves the pointer to (x, y) in the window and counts the MotionNotify events the window gets. */
static int motionsAfterMoveTo(Display *display, Window window, int x, int y) {
    int count = 0;
    XWarpPointer(display, None, window, 0, 0, 0, 0, x, y);
    XSync(display, False);
    usleep(100000);
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == MotionNotify && event.xmotion.window == window)
            count++;
    }
    return count;
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-pointer-motion.sh\n");
        return 2;
    }
    const long base = StructureNotifyMask | ButtonMotionMask | EnterWindowMask;
    Window window = XCreateSimpleWindow(display, DefaultRootWindow(display), 0, 0, 300, 300, 0, 0, 0);
    XMapWindow(display, window);

    CHECK(X11PointerMotionEventMask(false, false) == 0, "nothing asks for motion");
    CHECK(X11PointerMotionEventMask(true, false) == PointerMotionMask, "mouse-moved events ask for motion");
    CHECK(X11PointerMotionEventMask(false, true) == PointerMotionMask, "a pending hide-until-motion asks for motion");
    CHECK(X11PointerMotionEventMask(true, true) == PointerMotionMask, "both ask once");

    XSelectInput(display, window, base | X11PointerMotionEventMask(false, false));
    XSync(display, False);
    motionsAfterMoveTo(display, window, 20, 20);
    CHECK(motionsAfterMoveTo(display, window, 100, 100) == 0, "no motion is reported to a window that did not select it");

    XSelectInput(display, window, base | X11PointerMotionEventMask(false, true));
    XSync(display, False);
    CHECK(motionsAfterMoveTo(display, window, 150, 150) >= 1, "motion is reported once a hide-until-motion is pending");

    XSelectInput(display, window, base | X11PointerMotionEventMask(false, false));
    XSync(display, False);
    CHECK(motionsAfterMoveTo(display, window, 200, 200) == 0, "and stops when the wait is over");

    printf("RESULT checks=%d failures=%d\n", checks, failures);
    XCloseDisplay(display);
    return failures ? 1 : 0;
}
