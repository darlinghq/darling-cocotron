// Copyright (C) 2026 Lubos Dolezel
// Host test for AppKit/X11.backend/X11LevelStacking.h: the level rule and the restacking against real X stacking
// order. Needs an X server; run on its own Xvfb (tests/x11-level-stacking.sh).
// Build: cc x11-level-stacking.c -lX11
#include "../AppKit/X11.backend/X11LevelStacking.h"
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void levelRule(void) {
    // unmanagedIsAnchor, unmanagedLevel, managedLevel
    CHECK(X11UnmanagedBelowManaged(false, 0, 0), "managed window ordered in last goes above an unmanaged one of its level");
    CHECK(X11UnmanagedBelowManaged(false, 0, 8), "managed window of a higher level goes above");
    CHECK(!X11UnmanagedBelowManaged(false, 8, 0), "unmanaged window of a higher level stays above a managed one");
    CHECK(!X11UnmanagedBelowManaged(true, 0, 0), "unmanaged window ordered in last goes above a managed one of its level");
    CHECK(X11UnmanagedBelowManaged(true, 0, 8), "managed window of a higher level stays above the raised unmanaged one");
    CHECK(!X11UnmanagedBelowManaged(true, 8, 0), "raised unmanaged window of a higher level stays above");
}

static void unmanagedPairRule(void) {
    // anchorLevel, otherLevel
    CHECK(X11UnmanagedBelowUnmanaged(24, 1000), "the menu bar ordered in last stays below a full screen window");
    CHECK(!X11UnmanagedBelowUnmanaged(1000, 24), "a full screen window ordered in last goes above the menu bar");
    CHECK(!X11UnmanagedBelowUnmanaged(0, 0), "equal levels: the window ordered in last is in front");
}

static Window make(Display *display, Window parent, bool overrideRedirect) {
    XSetWindowAttributes attributes = {0};
    attributes.override_redirect = overrideRedirect;
    return XCreateWindow(display, parent, 0, 0, 100, 100, 0, CopyFromParent, InputOutput, CopyFromParent,
                         CWOverrideRedirect, &attributes);
}

static void restacking(Display *display) {
    Window root = DefaultRootWindow(display);
    Window lower = make(display, root, true), upper = make(display, root, false);
    XMapWindow(display, upper);
    XMapWindow(display, lower);
    XRaiseWindow(display, lower); // on top
    XSync(display, False);
    CHECK(X11StackIndex(display, lower) > X11StackIndex(display, upper), "setup: lower starts above upper");
    CHECK(X11StackBelowIfAbove(display, lower, upper), "restacked a window that was above");
    XSync(display, False);
    CHECK(X11StackIndex(display, lower) == X11StackIndex(display, upper) - 1, "lower is directly below upper: %d vs %d",
          X11StackIndex(display, lower), X11StackIndex(display, upper));
    CHECK(!X11StackBelowIfAbove(display, lower, upper), "nothing to do when it is already below");
    CHECK(!X11StackBelowIfAbove(display, lower, 0x7ffffff), "a window that is gone is left alone");

    // Without a reparenting window manager the top-level window is its own root child; inside a frame it is the frame.
    CHECK(X11TopLevelAncestor(display, upper) == upper, "a root child is its own top-level ancestor");
    Window frame = make(display, root, false), client = make(display, frame, false);
    CHECK(X11TopLevelAncestor(display, client) == frame, "a framed window resolves to its frame");
    XDestroyWindow(display, lower);
    XDestroyWindow(display, upper);
    XDestroyWindow(display, frame);
    XSync(display, False);
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X server\n");
        return 2;
    }
    levelRule();
    unmanagedPairRule();
    restacking(display);
    XCloseDisplay(display);
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
