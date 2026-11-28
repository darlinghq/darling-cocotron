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

@class X11AppMenu, X11Window;

@interface X11Display : DarlingDisplay <CGSNativeConnectionObserver> {
    Display *_display;
    NSMutableDictionary *_windowsByID;
    // Shows the main menu outside the windows (see X11AppMenu), nil until the
    // application has one or when the menu is drawn inside the windows.
    X11AppMenu *_appMenu;

    id lastFocusedWindow;
    // ConfinePointerToFullscreenWindows (org.darlinghq.AppKit): keep the
    // pointer inside the focused fullscreen window, through a pointer grab on
    // _confinedWindow while one is held.
    BOOL _confinesPointer;
    // ControlKeyActsAsCommand (org.darlinghq.AppKit): Control+C, V and X
    // arrive as their Command shortcuts.
    BOOL _controlActsAsCommand;
    Window _confinedWindow;
    // Xwayland forwards a pointer warp to the compositor only while the X
    // cursor is hidden, so warps are not honoured with a visible cursor there.
    BOOL _isXwayland;
    // See -primaryRootFrame. Device pixels, root coordinates.
    NSRect _primaryRootFrame;
    BOOL _primaryRootFrameValid;
    CGFloat _backingScale;
}

- (Display *) display;

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
- (id) windowForID: (XID) i;
- (void) windowHoldsFocus: (X11Window *) window;
// The window system's keyboard focus came to the window or left it.
- (void) window: (X11Window *) window focusChanged: (BOOL) gained;
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
