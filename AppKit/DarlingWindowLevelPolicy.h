/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// How a window level maps onto what a window system can express, independent of the
// window system (plain C, no dependencies, so host tests can include it).
//
// An NSWindow level orders windows in one stack across the whole session. A window system
// that lets a client only relate its windows (a transient parent) cannot place a window above
// arbitrary other windows, so the levels are reduced to what can be asked for:
//  - at or below the normal level: an ordinary window;
//  - above the normal level but below the main menu level (floating panels, torn-off menus,
//    modal panels, utility windows): a window that stays in front of the application's key
//    window, which a transient parent expresses;
//  - the main menu level and above (status items, pop-up menus, the screen saver): above
//    every window including other applications', which needs a window system extension for
//    layered surfaces; without one the window stays an ordinary window.
#ifndef DARLING_WINDOW_LEVEL_POLICY_H
#define DARLING_WINDOW_LEVEL_POLICY_H

#include <stdbool.h>

// kCGNormalWindowLevel and kCGMainMenuWindowLevel as CGWindowLevelForKey returns them.
enum {
    DarlingWindowLevelNormal = 0,
    DarlingWindowLevelMainMenu = 24,
};

typedef enum {
    DarlingWindowRoleOrdinary,
    DarlingWindowRoleTransient,
    DarlingWindowRoleNeedsLayering,
} DarlingWindowRole;

static inline DarlingWindowRole DarlingWindowRoleForLevel(int level) {
    if (level <= DarlingWindowLevelNormal)
        return DarlingWindowRoleOrdinary;
    if (level < DarlingWindowLevelMainMenu)
        return DarlingWindowRoleTransient;
    return DarlingWindowRoleNeedsLayering;
}

// Whether a window may name `parent` as its transient parent when `parent` already has
// `ancestors` (a chain of parents, nearest first, `count` long): a window must not be its
// own ancestor, as that is a protocol error.
static inline bool DarlingWindowParentAllowed(const void *window, const void *parent,
                                              const void *const *ancestors, int count)
{
    if (parent == NULL || parent == window)
        return false;
    for (int i = 0; i < count; i++)
        if (ancestors[i] == window)
            return false;
    return true;
}

#endif
