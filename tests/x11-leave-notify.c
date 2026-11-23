// Host test for AppKit/X11.backend/X11Crossing.h. The X server decides which LeaveNotify a window receives, so the
// test moves the pointer over windows of its own in the ways the header distinguishes and checks that the
// server sends the mode, detail and coordinates the header relies on:
//   - the pointer leaves a window for its parent: a LeaveNotify of mode Normal, the position outside the window,
//   - the pointer moves into a child window: detail Inferior, which does not leave the window,
//   - the pointer moves from a child window out of the parent: detail Virtual, which does,
//   - a pointer grab by another window activates: mode Grab, which does not,
//   - the pointer is warped out of a window that holds a grab and the grab ends: mode Ungrab, which does. The
//     grab's event mask here has no LeaveWindowMask, so the window gets no LeaveNotify until the grab ends.
// Use tests/x11-leave-notify.sh, which runs it on its own Xvfb.
// Build: cc x11-leave-notify.c -lX11
#include "../AppKit/X11.backend/X11Crossing.h"
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

static const int size = 100;

static void settle(Display *display) {
    XSync(display, False);
    usleep(100000);
}

static void drain(Display *display) {
    settle(display);
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
    }
}

// Warps the pointer to (x, y) in the window and returns the LeaveNotify the window got for it (type 0 if none).
static XCrossingEvent warpAndFindLeave(Display *display, Window window, Window target, int x, int y) {
    XCrossingEvent found = {0};
    XWarpPointer(display, None, target, 0, 0, 0, 0, x, y);
    settle(display);
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == LeaveNotify && event.xcrossing.window == window)
            found = event.xcrossing;
    }
    return found;
}

static const char *detailName(int detail) {
    switch (detail) {
        case NotifyAncestor: return "Ancestor";
        case NotifyVirtual: return "Virtual";
        case NotifyInferior: return "Inferior";
        case NotifyNonlinear: return "Nonlinear";
        case NotifyNonlinearVirtual: return "NonlinearVirtual";
    }
    return "?";
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-leave-notify.sh\n");
        return 2;
    }
    Window root = DefaultRootWindow(display);
    const long mask = EnterWindowMask | LeaveWindowMask | PointerMotionMask | StructureNotifyMask;

    CHECK(!X11LeaveNotifyMeansPointerLeft(NotifyNormal, NotifyInferior), "a move into a child does not leave");
    CHECK(!X11LeaveNotifyMeansPointerLeft(NotifyGrab, NotifyNonlinear), "a grab activating does not leave");
    CHECK(X11LeaveNotifyMeansPointerLeft(NotifyNormal, NotifyAncestor), "a move to the parent leaves");
    CHECK(X11LeaveNotifyMeansPointerLeft(NotifyUngrab, NotifyNonlinear), "a grab ending over another window leaves");

    // window: 100 x 100 at (100, 100); child: 40 x 40 at (30, 30) inside it; other: 100 x 100 at (300, 100).
    Window window = XCreateSimpleWindow(display, root, 100, 100, size, size, 0, 0, 0);
    XCreateSimpleWindow(display, window, 30, 30, 40, 40, 0, 0, 0); // the child
    Window other = XCreateSimpleWindow(display, root, 300, 100, size, size, 0, 0, 0);
    XSelectInput(display, window, mask);
    XSelectInput(display, other, mask);
    XMapWindow(display, window);
    XMapSubwindows(display, window);
    XMapWindow(display, other);
    XSync(display, False);

    // A pointer that leaves the window for its parent: Normal, outside the window.
    XWarpPointer(display, None, window, 0, 0, 0, 0, 10, 10);
    drain(display);
    XCrossingEvent leave = warpAndFindLeave(display, window, root, 600, 500);
    CHECK(leave.type == LeaveNotify, "no LeaveNotify when the pointer left the window");
    CHECK(leave.mode == NotifyNormal, "leaving the window: mode %d, not Normal", leave.mode);
    CHECK(leave.detail == NotifyAncestor, "leaving for the parent: detail %s", detailName(leave.detail));
    CHECK(X11LeaveNotifyMeansPointerLeft(leave.mode, leave.detail), "leaving the window is not taken for a leave");
    CHECK(leave.x < 0 || leave.y < 0 || leave.x >= size || leave.y >= size,
          "the position (%d, %d) of the leave is inside the window", leave.x, leave.y);

    // A pointer that moves into a child window is still inside: Inferior.
    XWarpPointer(display, None, window, 0, 0, 0, 0, 10, 10);
    drain(display);
    leave = warpAndFindLeave(display, window, window, 50, 50);
    CHECK(leave.type == LeaveNotify, "no LeaveNotify when the pointer moved into the child");
    CHECK(leave.detail == NotifyInferior, "moving into the child: detail %s", detailName(leave.detail));
    CHECK(!X11LeaveNotifyMeansPointerLeft(leave.mode, leave.detail), "moving into the child is taken for a leave");

    // A pointer that moves from the child out of the window passes the window as a virtual window.
    drain(display);
    leave = warpAndFindLeave(display, window, root, 600, 500);
    CHECK(leave.type == LeaveNotify, "no LeaveNotify when the pointer moved from the child out of the window");
    CHECK(leave.detail == NotifyVirtual, "from the child out of the window: detail %s", detailName(leave.detail));
    CHECK(X11LeaveNotifyMeansPointerLeft(leave.mode, leave.detail), "leaving from a child is not taken for a leave");

    // A grab by another window while the pointer is over the window: Grab, and the pointer has not moved.
    XWarpPointer(display, None, window, 0, 0, 0, 0, 10, 10);
    drain(display);
    XGrabPointer(display, other, False, ButtonPressMask | PointerMotionMask, GrabModeAsync, GrabModeAsync, None,
                 None, CurrentTime);
    settle(display);
    leave = (XCrossingEvent) {0};
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == LeaveNotify && event.xcrossing.window == window)
            leave = event.xcrossing;
    }
    CHECK(leave.type == LeaveNotify, "no LeaveNotify when another window grabbed the pointer");
    CHECK(leave.mode == NotifyGrab, "another window's grab: mode %d, not Grab", leave.mode);
    CHECK(!X11LeaveNotifyMeansPointerLeft(leave.mode, leave.detail), "a grab is taken for a leave");
    XUngrabPointer(display, CurrentTime);
    drain(display);

    // A pointer warped out of a window that holds a grab whose event mask lacks LeaveWindowMask: no LeaveNotify
    // arrives until the grab ends, and then it has mode Ungrab.
    XWarpPointer(display, None, window, 0, 0, 0, 0, 10, 10);
    drain(display);
    XGrabPointer(display, window, False, ButtonPressMask | PointerMotionMask, GrabModeAsync, GrabModeAsync, None,
                 None, CurrentTime);
    drain(display);
    leave = warpAndFindLeave(display, window, root, 600, 500);
    CHECK(leave.type == 0, "a LeaveNotify arrived while the window held a grab without LeaveWindowMask");
    XUngrabPointer(display, CurrentTime);
    settle(display);
    leave = (XCrossingEvent) {0};
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == LeaveNotify && event.xcrossing.window == window)
            leave = event.xcrossing;
    }
    CHECK(leave.type == LeaveNotify, "no LeaveNotify when the grab ended with the pointer outside");
    CHECK(leave.mode == NotifyUngrab, "the grab ending: mode %d, not Ungrab", leave.mode);
    CHECK(X11LeaveNotifyMeansPointerLeft(leave.mode, leave.detail), "an ungrab outside is not taken for a leave");
    CHECK(leave.x < 0 || leave.y < 0 || leave.x >= size || leave.y >= size,
          "the position (%d, %d) of the ungrab leave is inside the window", leave.x, leave.y);

    printf("RESULT checks=%d failures=%d\n", checks, failures);
    XCloseDisplay(display);
    return failures ? 1 : 0;
}
