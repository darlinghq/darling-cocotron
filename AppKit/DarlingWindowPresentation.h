/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// What a window is to the window system, decided from AppKit's own concepts and independent of
// the window system (plain C, no dependencies, so host tests can include it).
//
// On macOS no window has an entry of its own in a task bar: the application has one Dock icon,
// its main windows are what the user switches between, and the other windows (panels, child
// windows, pop-ups, tool tips) belong to a main window or float on their own. A window system
// that lists every top-level window, centres every window the client did not place and gives the
// keyboard focus to every new window needs to be told which windows are which:
//  - an application window is a window that macOS includes in the application's window list in the
//    Dock, Mission Control and the window cycling (Cmd-`). A window that is attached to another as a
//    child, a panel, a modal panel or sheet, a window above the normal level, and a window whose
//    collection behaviour says it is transient, stationary or ignores the cycle is left out there;
//    every other window is included, whether it has a title bar or not (a borderless window that
//    draws its own chrome is a normal window) and whatever the application's activation policy:
//    an accessory application has no Dock icon of its own, but its windows are on screen and in
//    Mission Control, and a task bar is the only way to reach them. Application windows are listed,
//    placed where AppKit asks and activated when shown;
//  - a pop-up is a window without a title bar that cannot become the main window and either is
//    attached to a parent, sits at the main menu level or above, or ignores the mouse (a pop-up
//    menu drawn by a toolkit, a drop-down, a tool tip), and the window system's own menus and
//    tool tips: it belongs to a window, is not listed, and does not take the focus unless the
//    application makes it the key window;
//  - every other window (a panel, a modal panel or sheet, a window that cannot become main, a
//    child window with a title bar) is auxiliary: not listed, and related to its parent window or
//    to the application's main window.
// AppKit always gives a window an explicit frame, so the window system is told that every window
// positions itself.
#ifndef DARLING_WINDOW_PRESENTATION_H
#define DARLING_WINDOW_PRESENTATION_H

#include <stdbool.h>

#include "DarlingWindowLevelPolicy.h"

typedef struct {
    bool hasTitlebar;    // the window system's frame with a title bar (not a borderless window)
    bool leavesWindowCycle;   // collection behaviour Transient, Stationary or IgnoresCycle
    bool canBecomeMain;
    bool canBecomeKey;
    bool hasParent;      // attached to another window with -addChildWindow:ordered:
    bool isPanel;
    bool isMenu;         // a menu or pop-up button's window
    bool isTooltip;
    bool isModal;        // a modal panel or a sheet
    bool ignoresMouse;
    int level;           // as CGWindowLevelForKey returns it
} DarlingWindowTraits;

typedef enum {
    DarlingWindowPresentationApplication,
    DarlingWindowPresentationAuxiliary,
    DarlingWindowPresentationPopup,
} DarlingWindowPresentation;

static inline DarlingWindowPresentation DarlingWindowPresentationFor(const DarlingWindowTraits *window) {
    if (window->isMenu || window->isTooltip)
        return DarlingWindowPresentationPopup;
    if (!window->isPanel && !window->isModal) {
        if (!window->hasTitlebar && !window->canBecomeMain &&
            (window->hasParent || window->level >= DarlingWindowLevelMainMenu || window->ignoresMouse))
            return DarlingWindowPresentationPopup;
        if (!window->hasParent && !window->leavesWindowCycle &&
            window->level <= DarlingWindowLevelNormal)
            return DarlingWindowPresentationApplication;
    }
    return DarlingWindowPresentationAuxiliary;
}

#endif
