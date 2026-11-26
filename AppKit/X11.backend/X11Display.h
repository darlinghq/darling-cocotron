//
//  X11Display.h
//  AppKit
//
//  Created by Johannes Fortmann on 13.10.08.
//  Copyright 2008 -. All rights reserved.
//

#import "../private-include/AppKit/DarlingDisplay.h"
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

#ifdef DARLING
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#endif

#import <CoreGraphics/CGSNativeConnection.h>

@class X11Cursor, X11AppMenu, X11Window;

@interface X11Display : DarlingDisplay <CGSNativeConnectionObserver> {
    Display *_display;
    NSMutableDictionary *_windowsByID;
    // Shows the main menu outside the windows (see X11AppMenu), nil until the
    // application has one or when the menu is drawn inside the windows.
    X11AppMenu *_appMenu;
    BOOL _desktopMenuProbed, _desktopMenuPresent;

    id lastFocusedWindow;
    X11Cursor *_blankCursor, *_defaultCursor;
    // ConfinePointerToFullscreenWindows (org.darlinghq.AppKit): keep the
    // pointer inside the focused fullscreen window, through a pointer grab on
    // _confinedWindow while one is held.
    BOOL _confinesPointer;
    // ControlKeyActsAsCommand (org.darlinghq.AppKit): Control+C, V and X
    // arrive as their Command shortcuts.
    BOOL _controlActsAsCommand;
    Window _confinedWindow;
    // The menu and pop-up windows that are on the screen, oldest first, while
    // the pointer is held for them (see -menuWindowMapped:).
    NSMutableArray *_openMenuWindows;
    // Xwayland forwards a pointer warp to the compositor only while the X
    // cursor is hidden, so warps are not honoured with a visible cursor there.
    BOOL _isXwayland;
    BOOL _cursorHidden;
    // See -primaryRootFrame. Device pixels, root coordinates.
    NSRect _primaryRootFrame;
    BOOL _primaryRootFrameValid;
    CGFloat _backingScale;
    // Root properties and the focused foreign window (_occlusionWatchWindow) are watched for changes
    // that can cover or uncover a window of ours (see X11Occlusion.h); the windows are judged once
    // per batch of events, when _occlusionDirty is set.
    BOOL _occlusionDirty;
    Window _occlusionWatchWindow;
    // What was last read from the server about the focused foreign window, kept until an event that
    // can change it: the window itself (_occlusionActive, from _NET_ACTIVE_WINDOW), its geometry and
    // state (the cover fields, root coordinates, device pixels) and the last ConfigureNotify geometry
    // seen on it, so that a notification repeating the same geometry changes nothing.
    BOOL _occlusionActiveKnown;
    Window _occlusionActive;
    BOOL _occlusionCoverValid;
    BOOL _occlusionCoverOK;
    BOOL _occlusionCoverFullscreen;
    BOOL _occlusionCoverOpaque;
    int _occlusionCoverX, _occlusionCoverY;
    unsigned int _occlusionCoverWidth, _occlusionCoverHeight;
    BOOL _occlusionWatchGeometryKnown;
    int _occlusionWatchX, _occlusionWatchY, _occlusionWatchWidth, _occlusionWatchHeight;

@public
    XIM _xim;
    // YES when a real input method (XMODIFIERS names one) does the composing; NO for Xlib's built-in one, which
    // only composes dead keys and Compose sequences, and which CoreGraphics replaces.
    BOOL _inputMethodComposes;
}

- (Display *) display;

// Keeps the unmanaged windows (see -[X11Window isUnmanaged]) and the managed
// ones in the order their levels give, after `anchor` was ordered to the
// front, mapped or given another level (see X11LevelStacking.h).
- (void) restackWindowsForLevelsAround: (X11Window *) anchor;

// The main monitor's rectangle in root coordinates. It is the origin of the
// global coordinate space; see X11Monitors.h.
- (NSRect) primaryRootFrame;
// The same rectangle as an X11Frame, in the unit of window frames (points).
- (X11Frame) primaryFrameInPoints;
// Device pixels per point: the Darling preference X11BackingScale of the
// org.darlinghq.AppKit domain, else GDK_SCALE, else 1.
- (CGFloat) backingScale;
// Converts a point in root coordinates to CoreGraphics' global space.
- (NSPoint) cgPointFromRoot: (NSPoint) root;
- (void) setWindow: (id) window forID: (XID) i;
// Menu and pop-up windows are not managed by the window manager and never
// take the keyboard focus, so a click outside them reaches other clients
// and not the application's tracking of its menu. While any is on the screen
// the pointer is grabbed for the application (owner_events set: its windows
// keep receiving their own events, those elsewhere are delivered as if made
// in the newest menu window), as menus do in other toolkits.
- (void) menuWindowMapped: (X11Window *) window;
- (void) menuWindowUnmapped: (X11Window *) window;
- (id) windowForID: (XID) i;
- (void) windowHoldsFocus: (X11Window *) window;
// The AppKit modifier flags for an X modifier state (the core protocol's state mask).
- (NSEventModifierFlags) modifierFlagsForState: (unsigned int) state;

// YES while a cursor hidden until the pointer moves waits for that motion. The server only reports
// a motion to a window that selected PointerMotionMask, which a window does for mouse-moved events,
// so every window selects it while this is YES.
- (BOOL) cursorAwaitsPointerMotion;

// Re-reads the backing scale and, when it changed, resizes the windows to the
// new scale and notifies them.
- (void) reevaluateBackingScale;

// The object that shows the main menu outside the windows, created on first
// use; nil if the menu is drawn inside the windows (DarlingInWindowMenuBar).
- (X11AppMenu *) appMenu;
#ifdef DARLING
- (void) processPendingEvents;
#endif

- (CGFloat) doubleClickInterval;
- (int) handleError: (XErrorEvent *) errorEvent;
@end
