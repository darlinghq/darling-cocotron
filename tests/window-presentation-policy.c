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
    // A titled window that can become main is an application window.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .canBecomeKey = true})
          == DarlingWindowPresentationApplication);
    // So is a borderless window that draws its own chrome and can become main.
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .canBecomeKey = true})
          == DarlingWindowPresentationApplication);
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
    // A titled window that cannot become main is auxiliary.
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeKey = true})
          == DarlingWindowPresentationAuxiliary);
    // A borderless window that cannot become main is a pop-up when it has a parent, sits at the main
    // menu level or above, or ignores the mouse ...
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .hasParent = true}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = DarlingWindowLevelMainMenu})
          == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = 101}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.ignoresMouse = true}) == DarlingWindowPresentationPopup);
    // ... and auxiliary otherwise (an overlay or splash window with nothing to belong to).
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true}) == DarlingWindowPresentationAuxiliary);
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .level = 3}) == DarlingWindowPresentationAuxiliary);
    // A borderless pop-up that can become main is not a pop-up.
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .hasParent = true}) == DarlingWindowPresentationAuxiliary);
    // Menus and tool tips are pop-ups whatever else they are (they are panels or have titles).
    CHECK(of((DarlingWindowTraits){.isMenu = true, .isPanel = true, .hasTitlebar = true}) == DarlingWindowPresentationPopup);
    CHECK(of((DarlingWindowTraits){.isTooltip = true}) == DarlingWindowPresentationPopup);
    // A panel at a high level is not a pop-up: it has a title bar of its own.
    CHECK(of((DarlingWindowTraits){.isPanel = true, .hasTitlebar = true, .level = 101}) == DarlingWindowPresentationAuxiliary);
    // A window of one pixel is never an application window, even one that answers YES for main and key.
    CHECK(of((DarlingWindowTraits){.canBecomeMain = true, .canBecomeKey = true, .isTiny = true})
          == DarlingWindowPresentationAuxiliary);
    CHECK(of((DarlingWindowTraits){.hasTitlebar = true, .canBecomeMain = true, .canBecomeKey = true, .isTiny = true})
          == DarlingWindowPresentationAuxiliary);
    // ... but a tiny pop-up stays a pop-up.
    CHECK(of((DarlingWindowTraits){.canBecomeKey = true, .hasParent = true, .isTiny = true}) == DarlingWindowPresentationPopup);

    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
