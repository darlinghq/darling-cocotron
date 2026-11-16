/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
/* Window levels for the X11 backend: where an unmanaged (override-redirect) window sits relative to the managed
 * windows of a window manager.
 *
 * AppKit orders windows by level: a window ordered to the front goes in front of every window of the same or a
 * lower level and stays behind the windows of a higher level (documented under NSWindow level and
 * NSWindowLevel). The window manager stacks only the windows it manages, and an override-redirect window is
 * outside its control: it stays wherever the X server put it, which is above the frames of windows mapped
 * before it was raised, and a window manager that raises a frame does not place it above such a window. A
 * borderless window that cannot become key (a game's full screen window) is override-redirect, so a dialog
 * of a higher level, or a managed window ordered to the front later, stayed hidden behind it.
 *
 * Only Xlib, no Objective-C, so tests/x11-level-stacking.c can drive it against Xvfb. */
#ifndef X11_LEVEL_STACKING_H
#define X11_LEVEL_STACKING_H

#include <X11/Xlib.h>
#include <stdbool.h>
#include <stdlib.h>

/* Whether an unmanaged window has to be stacked below a managed window, after one of the two was ordered
 * to the front (`unmanagedIsAnchor` tells which). A managed window that was just ordered in front goes above the
 * unmanaged windows of its own or a lower level. An unmanaged window that was just ordered in front goes above
 * the managed windows of its own or a lower level, which leaves the managed windows of a higher level above it. */
static inline bool X11UnmanagedBelowManaged(bool unmanagedIsAnchor, int unmanagedLevel, int managedLevel) {
    if (unmanagedIsAnchor)
        return managedLevel > unmanagedLevel;
    return unmanagedLevel <= managedLevel;
}

/* Whether an unmanaged window has to be stacked above a managed window that was just ordered to the front (or got
 * a new level): a managed window is put in front of everything by the window manager, including an unmanaged
 * window of a higher level (the borderless full screen window of a game at the screen saver level, with a
 * titled window of the normal level ordered in later), so the unmanaged window has to be raised above its frame. */
static inline bool X11UnmanagedAboveManaged(int unmanagedLevel, int managedLevel) {
    return unmanagedLevel > managedLevel;
}

/* Whether `anchor`, an unmanaged window that was just ordered to the front or got a new level, has to be
 * stacked below `other`, another unmanaged window: the window of the higher level is in front, and windows of
 * one level keep the order in which they were ordered to the front. The menu bar (level 24) and the
 * borderless full screen window of a game (a higher level) are two such windows: the server stacks both by
 * the time they were raised, and the bar is raised after the game's window, when the application becomes
 * active. */
static inline bool X11UnmanagedBelowUnmanaged(int anchorLevel, int otherLevel) {
    return otherLevel > anchorLevel;
}

/* The child of the root window that contains `window`: the window itself without a reparenting window manager,
 * its frame with one. Returns None when `window` is gone. */
static inline Window X11TopLevelAncestor(Display *display, Window window) {
    Window root = DefaultRootWindow(display);
    for (;;) {
        Window rootReturn, parent, *children = NULL;
        unsigned int count;
        if (!XQueryTree(display, window, &rootReturn, &parent, &children, &count))
            return None;
        if (children)
            XFree(children);
        if (parent == root || parent == None)
            return window;
        window = parent;
    }
}

/* The position of a root child in the stacking order, 0 for the bottom, or -1 when it is not a child of the root. */
static inline int X11StackIndex(Display *display, Window rootChild) {
    Window rootReturn, parent, *children = NULL;
    unsigned int count = 0;
    int index = -1;
    if (!XQueryTree(display, DefaultRootWindow(display), &rootReturn, &parent, &children, &count))
        return -1;
    for (unsigned int i = 0; i < count; i++) {
        if (children[i] == rootChild) {
            index = (int) i;
            break;
        }
    }
    if (children)
        XFree(children);
    return index;
}

/* Puts the root child `lower` directly below the root child `upper`, unless it already is below it. Both are
 * root children (see X11TopLevelAncestor). `lower` must not be managed by a window manager, which would take the
 * request over; an override-redirect window is restacked by the server itself. Returns whether it restacked. */
static inline bool X11StackBelowIfAbove(Display *display, Window lower, Window upper) {
    int lowerIndex = X11StackIndex(display, lower);
    int upperIndex = X11StackIndex(display, upper);
    if (lowerIndex < 0 || upperIndex < 0 || lowerIndex < upperIndex)
        return false;
    Window pair[2] = {upper, lower};
    XRestackWindows(display, pair, 2);
    return true;
}

/* Puts the unmanaged root child `upper` directly above the root child `lower` (typically a window manager's frame),
 * unless it already is above it. `upper` must not be managed by a window manager. Returns whether it restacked. */
static inline bool X11StackAboveIfBelow(Display *display, Window upper, Window lower) {
    int upperIndex = X11StackIndex(display, upper);
    int lowerIndex = X11StackIndex(display, lower);
    if (upperIndex < 0 || lowerIndex < 0 || upperIndex > lowerIndex)
        return false;
    XWindowChanges changes;
    changes.sibling = lower;
    changes.stack_mode = Above;
    XConfigureWindow(display, upper, CWSibling | CWStackMode, &changes);
    return true;
}

#endif
