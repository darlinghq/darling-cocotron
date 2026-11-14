// Copyright (C) 2026 Lubos Dolezel
// Host test for the global key grabs of the X11 backend (CoreGraphics/X11.backend/X11HotKey.h): the modifier
// mapping, an exclusive grab (a second client is refused), delivery of the presses and releases with the lock
// modifiers in any state, no delivery for other modifiers or after the key is ungrabbed. Keys are generated
// with xdotool (XTEST), which activates passive grabs like a keyboard does. Use tests/x11-hotkey-grab.sh.
// Build: cc x11-hotkey-grab.c -lX11 -lpthread
#include "../CoreGraphics/X11.backend/X11HotKey.h"
#include <X11/keysym.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

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

static void keys(const char* command) {
    char line[256];
    snprintf(line, sizeof line, "xdotool %s", command);
    if (system(line) != 0) {
        printf("FAIL: %s\n", line);
        failures++;
    }
}

// Collects the key events that arrive within the time limit (first event 1 s, then 150 ms of quiet)
typedef struct { int presses, releases; unsigned lastState; } Seen;

static Seen collect(Display* display, int keycode, unsigned hotKeyModifiers) {
    Seen seen = {0, 0, 0};
    int fd = ConnectionNumber(display);
    long wait = 1000;

    for (;;) {
        while (XPending(display)) {
            XEvent event;
            XNextEvent(display, &event);
            // A release is counted whatever the modifiers: they may have been let go first, which is why
            // the backend reports a release for the hot keys whose press it reported.
            if (event.type == KeyPress && (int) event.xkey.keycode == keycode &&
                X11HotKeyMatches(event.xkey.state, hotKeyModifiers)) {
                seen.presses++;
                seen.lastState = event.xkey.state;
            } else if (event.type == KeyRelease && (int) event.xkey.keycode == keycode)
                seen.releases++;
            wait = 150;
        }
        fd_set set;
        FD_ZERO(&set);
        FD_SET(fd, &set);
        struct timeval timeout = { wait / 1000, (wait % 1000) * 1000 };
        if (select(fd + 1, &set, NULL, NULL, &timeout) <= 0)
            break;
    }
    return seen;
}

int main(void) {
    if (system("xdotool version >/dev/null 2>&1") != 0) {
        printf("SKIP: xdotool is not installed\n");
        return 0;
    }
    Display* d1 = XOpenDisplay(NULL);
    Display* d2 = XOpenDisplay(NULL);
    if (!d1 || !d2) {
        printf("SKIP: no X display\n");
        return 0;
    }
    int a = XKeysymToKeycode(d1, XK_a);
    unsigned ctrlShift = X11HotKeyModifiers(true, true, false, false);

    CHECK(X11HotKeyModifiers(false, false, false, false) == 0, "no modifiers");
    CHECK(X11HotKeyModifiers(true, false, false, false) == ShiftMask, "shift");
    CHECK(X11HotKeyModifiers(false, true, false, false) == ControlMask, "control");
    CHECK(X11HotKeyModifiers(false, false, true, false) == Mod1Mask, "option is Mod1");
    CHECK(X11HotKeyModifiers(false, false, false, true) == Mod4Mask, "command is Mod4");
    CHECK(X11HotKeyMatches(ControlMask | ShiftMask | LockMask | Mod2Mask, ctrlShift), "lock modifiers are ignored");
    CHECK(!X11HotKeyMatches(ControlMask, ctrlShift), "a missing modifier does not match");
    CHECK(!X11HotKeyMatches(ControlMask | ShiftMask | Mod1Mask, ctrlShift), "an extra modifier does not match");

    CHECK(X11HotKeyGrab(d1, a, ctrlShift) == X11HotKeyGrabbed, "first client grabs");
    CHECK(X11HotKeyGrab(d2, a, ctrlShift) == X11HotKeyGrabBusy, "second client for the same combination is refused");
    CHECK(X11HotKeyGrab(d2, a, ControlMask) == X11HotKeyGrabbed, "another combination of the same key is free");
    X11HotKeyUngrab(d2, a, ControlMask);
    XSync(d1, False);
    while (XPending(d1)) { XEvent e; XNextEvent(d1, &e); }

    keys("key ctrl+shift+a");
    Seen seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 1 && seen.releases == 1, "press and release delivered (%d, %d)", seen.presses, seen.releases);

    keys("key Caps_Lock");
    keys("key ctrl+shift+a");
    seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 1 && seen.releases == 1, "delivered with Caps Lock on (%d, %d, state %#x)", seen.presses, seen.releases, seen.lastState);
    CHECK(seen.lastState & LockMask, "the event shows Caps Lock");
    keys("key Caps_Lock");

    keys("key Num_Lock");
    keys("key ctrl+shift+a");
    seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 1 && seen.releases == 1, "delivered with Num Lock toggled (%d, %d, state %#x)", seen.presses, seen.releases, seen.lastState);
    keys("key Num_Lock");

    keys("key ctrl+a");
    seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 0 && seen.releases == 0, "other modifiers are not delivered (%d, %d)", seen.presses, seen.releases);

    // The modifiers let go before the key: the key release still arrives
    keys("keydown ctrl keydown shift keydown a keyup ctrl keyup shift keyup a");
    seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 1 && seen.releases == 1, "release arrives although the modifiers were released first (%d, %d)", seen.presses, seen.releases);

    X11HotKeyUngrab(d1, a, ctrlShift);
    keys("key ctrl+shift+a");
    seen = collect(d1, a, ctrlShift);
    CHECK(seen.presses == 0 && seen.releases == 0, "nothing after ungrab (%d, %d)", seen.presses, seen.releases);
    CHECK(X11HotKeyGrab(d2, a, ctrlShift) == X11HotKeyGrabbed, "the combination is free after ungrab");
    X11HotKeyUngrab(d2, a, ctrlShift);

    XCloseDisplay(d1);
    XCloseDisplay(d2);
    printf("%s: %d checks, %d failures\n", failures ? "FAIL" : "PASS", checks, failures);
    return failures != 0;
}
