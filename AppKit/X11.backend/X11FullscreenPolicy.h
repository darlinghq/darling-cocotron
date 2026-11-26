/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
/* When an X11 window is fullscreen: the part of the decision that depends on how the window is managed. The window
 * system's side (the monitor test, the EWMH request and the state read) is CoreGraphics' (X11Fullscreen.h there).
 * No Objective-C, no Xlib, so tests/x11-fullscreen.c can include it. */
#ifndef X11_FULLSCREEN_POLICY_H
#define X11_FULLSCREEN_POLICY_H

#include <stdbool.h>

#include "../DarlingFullscreenPolicy.h"

/* An application window asks for fullscreen when the application did (the fullscreen style bit), or when it is
 * a managed, untitled window that covers a monitor. Titled windows are never promoted: a maximized titled
 * window is not fullscreen. Unmanaged (override-redirect) windows are not the window manager's to place. */
static inline bool X11FullscreenWanted(bool overrideRedirect, bool styleFullScreen, bool titled, bool coversMonitor) {
    if (overrideRedirect)
        return false;
    return DarlingFullscreenWanted(styleFullScreen, titled, coversMonitor);
}

/* Whether a style change takes the window out of fullscreen whatever its frame: the application cleared the
 * fullscreen style bit (-toggleFullScreen:). The window still covers its monitor then, but only because it was
 * fullscreen, so the monitor test must not hold it there; the window manager restores the frame it had before. */
static inline bool X11FullscreenStyleLeft(bool wasStyleFullScreen, bool styleFullScreen) {
    return wasStyleFullScreen && !styleFullScreen;
}

/* Whether a window that is already fullscreen has to leave fullscreen before setFrame: moves it. It does when it
 * should no longer be fullscreen, and also when it moves to another place (another monitor): a window manager
 * ignores configure requests for a fullscreen window, so a move between two monitors that are each exactly
 * covered would otherwise leave the window on the first one. The caller asks for fullscreen again after the move. */
static inline bool X11FullscreenLeaveBeforeMove(bool wanted, bool requested, bool moved) {
    return requested && (!wanted || moved);
}

#endif
