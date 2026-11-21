// Host test for AppKit/X11.backend/X11DockSupport.h: the decision on a list of supported atoms, and the
// read of _NET_SUPPORTED from a real root window. Needs an X server; use tests/x11-dock-support.sh, which runs
// it on its own Xvfb. Build: cc x11-dock-support.c -lX11
#include "../AppKit/X11.backend/X11DockSupport.h"
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

static void setSupported(Display *display, const char *const *names, int count) {
    Atom atoms[64];
    for (int i = 0; i < count; i++)
        atoms[i] = XInternAtom(display, names[i], False);
    XChangeProperty(display, DefaultRootWindow(display), XInternAtom(display, "_NET_SUPPORTED", False), XA_ATOM, 32,
                    PropModeReplace, (unsigned char *) atoms, count);
    XSync(display, False);
}

// The atoms Hyprland lists for its X11 clients: states and a few requests, no window types and no struts.
static const char *const hyprland[] = {"_NET_WM_STATE", "_NET_ACTIVE_WINDOW", "_NET_WM_MOVERESIZE",
                                       "_NET_WM_STATE_FOCUSED", "_NET_WM_STATE_MODAL", "_NET_WM_STATE_FULLSCREEN",
                                       "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ",
                                       "_NET_WM_STATE_HIDDEN", "_NET_CLIENT_LIST", "_NET_CLIENT_LIST_STACKING",
                                       "_NET_WORKAREA", "_NET_WM_STATE_DEMANDS_ATTENTION"};

static void atomTable(void) {
    const Atom dock = 100, strutPartial = 101, strut = 102, other = 103;
    Atom none[] = {other};
    Atom withDock[] = {other, dock};
    Atom withStrutPartial[] = {strutPartial, other};
    Atom withStrut[] = {other, strut};
    Atom all[] = {dock, strutPartial, strut};
    CHECK(!X11SupportedAtomsPlaceDocks(none, 0, dock, strutPartial, strut), "an empty list does not place docks");
    CHECK(!X11SupportedAtomsPlaceDocks(none, 1, dock, strutPartial, strut),
          "a list without the dock hints does not place docks");
    CHECK(X11SupportedAtomsPlaceDocks(withDock, 2, dock, strutPartial, strut), "the dock window type is enough");
    CHECK(X11SupportedAtomsPlaceDocks(withStrutPartial, 2, dock, strutPartial, strut), "the partial strut is enough");
    CHECK(X11SupportedAtomsPlaceDocks(withStrut, 2, dock, strutPartial, strut), "the plain strut is enough");
    CHECK(X11SupportedAtomsPlaceDocks(all, 3, dock, strutPartial, strut), "all hints");
}

static void rootTest(Display *display) {
    Window root = DefaultRootWindow(display);
    Atom supported = XInternAtom(display, "_NET_SUPPORTED", False);

    XDeleteProperty(display, root, supported);
    XSync(display, False);
    CHECK(X11WindowManagerPlacesDocks(display), "no EWMH window manager: windows stay where they ask, so docks are placed");

    setSupported(display, hyprland, (int) (sizeof(hyprland) / sizeof(hyprland[0])));
    CHECK(!X11WindowManagerPlacesDocks(display), "a manager listing neither the dock type nor the strut");

    const char *const withDock[] = {"_NET_WM_STATE", "_NET_WM_WINDOW_TYPE_DOCK"};
    setSupported(display, withDock, 2);
    CHECK(X11WindowManagerPlacesDocks(display), "a manager listing the dock window type");

    const char *const withStrut[] = {"_NET_WM_STATE", "_NET_WM_STRUT_PARTIAL"};
    setSupported(display, withStrut, 2);
    CHECK(X11WindowManagerPlacesDocks(display), "a manager listing the partial strut");

    const char *const withPlainStrut[] = {"_NET_WM_STATE", "_NET_WM_STRUT"};
    setSupported(display, withPlainStrut, 2);
    CHECK(X11WindowManagerPlacesDocks(display), "a manager listing the plain strut");

    long notAtoms[] = {1, 2, 3};
    XChangeProperty(display, root, supported, XA_CARDINAL, 32, PropModeReplace, (unsigned char *) notAtoms, 3);
    XSync(display, False);
    CHECK(X11WindowManagerPlacesDocks(display), "a property that is not a list of atoms is not an EWMH manager");

    XDeleteProperty(display, root, supported);
    XSync(display, False);
}

int main(void) {
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        printf("no X display: run through tests/x11-dock-support.sh\n");
        return 2;
    }
    atomTable();
    rootTest(display);
    XCloseDisplay(display);
    if (failures) {
        printf("%d of %d checks FAILED\n", failures, checks);
        return 1;
    }
    printf("PASS: %d checks\n", checks);
    return 0;
}
