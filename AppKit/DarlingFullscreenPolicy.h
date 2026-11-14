/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The part of the fullscreen decision that does not depend on the window system, shared by
// the backends (X11Fullscreen.h, WaylandFullscreen.h). Plain C, no dependencies, so host
// tests can include it.
#ifndef DARLING_FULLSCREEN_POLICY_H
#define DARLING_FULLSCREEN_POLICY_H

#include <stdbool.h>

// A window is fullscreen when the application asked for it (the fullscreen style bit), or when
// it is an untitled window that covers a whole monitor: a borderless window of the size of a
// monitor is how games and media players do borderless fullscreen on macOS, and a window
// system has to be told because it cannot tell. A titled window is never promoted, so a
// maximised titled window is not fullscreen. A backend that cannot place a window at all (an
// override-redirect X11 window, a popup) reports it as not promotable through `titled`.
static inline bool DarlingFullscreenWanted(bool styleFullScreen, bool titled, bool coversMonitor) {
    if (styleFullScreen)
        return true;
    if (titled)
        return false;
    return coversMonitor;
}

#endif
