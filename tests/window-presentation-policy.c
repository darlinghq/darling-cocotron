/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Host test (no display server, no Darling): the X11 and Wayland backends decide what a window is to
// the window system through the one rule in DarlingWindowPresentation.h, so for the same window they
// agree. Build and run from the repository root:
//   cc -o window-presentation-policy tests/window-presentation-policy.c && ./window-presentation-policy
#include "../AppKit/DarlingWindowPresentation.h"
#include <stdio.h>

static int failures;
#define CHECK(x) do { if (!(x)) { failures++; fprintf(stderr, "line %d: %s\n", __LINE__, #x); } } while (0)

static DarlingWindowPresentation of(DarlingWindowTraits t) { return DarlingWindowPresentationFor(&t); }

int main(void) {
    // A window is an application window, titled or not, whatever it answers to
    // canBecomeMain and whatever its size: the Dock lists the application's windows, not only the titled ones.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .canBecomeKey = true})
          == DarlingWindowPresentationApplication);
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .canBecomeKey = true}) == DarlingWindowPresentationApplication);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true}) == DarlingWindowPresentationApplication);
    // The application's activation policy does not matter: an accessory application's windows are on screen and in
    // Mission Control, and a task bar is the only way to reach them (no trait for it exists).
    // A window that is transient, stationary or ignores the window cycle (collection behaviour) is left out of
    // the window list and the cycle, whatever else it is.
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .canBecomeKey = true, .leavesWindowCycle = true})
          == DarlingWindowPresentationAuxiliary);
    // So is a window above the normal level.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .level = 3}) == DarlingWindowPresentationAuxiliary);
    // A window attached to another as a child is not, whatever else it can do.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .canBecomeKey = true, .hasParent = true})
          == DarlingWindowPresentationAuxiliary);
    // Panels and sheets are not.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeKey = true, .isPanel = true})
          == DarlingWindowPresentationAuxiliary);
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .isPanel = true})
          == DarlingWindowPresentationAuxiliary);
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .isModal = true})
          == DarlingWindowPresentationAuxiliary);
    // A borderless window that cannot become main is a pop-up when it has a parent, sits at the main
    // menu level or above, or ignores the mouse ...
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .hasParent = true}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = DarlingWindowLevelMainMenu})
          == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = 101}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.ignoresMouse = true}) == DarlingWindowPresentationPopup);
    // ... and an application window otherwise at the normal level, auxiliary above it.
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = 3}) == DarlingWindowPresentationAuxiliary);
    // A borderless pop-up that can become main is not a pop-up.
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .hasParent = true}) == DarlingWindowPresentationAuxiliary);
    // Menus and tool tips are pop-ups whatever else they are (they are panels or have titles).
    CHECK(of((DarlingWindowTraits){.isMenu = true, .isPanel = true, .hasTitlebar = true}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.isTooltip = true}) == DarlingWindowPresentationPopup);
    // A panel at a high level is not a pop-up: it has a title bar of its own.
    CHECK(of((DarlingWindowTraits){.isPanel = true, .hasTitlebar = true, .level = 101}) == DarlingWindowPresentationAuxiliary);

    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
