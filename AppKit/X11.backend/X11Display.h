//
//  X11Display.h
//  AppKit
//
//  Created by Johannes Fortmann on 13.10.08.
//  Copyright 2008 -. All rights reserved.
//

#import "../private-include/AppKit/DarlingDisplay.h"
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import "X11RelativeMouseGrab.h"
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

#ifdef DARLING
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#endif

@class X11Cursor, X11AppMenu, X11Window;

@interface X11Display : DarlingDisplay {
    Display *_display;
    int _fileDescriptor;
#ifndef DARLING
    NSSelectInputSource *_inputSource;
#else
    // We use CFRunLoop directly, without going through any Foundation wrapper,
    // because Apple's Cocoa has none. Unlike Apple's Cocoa, we need to watch
    // over a Unix domain socket, not a Mach port.
    CFSocketRef _cfSocket;
    CFRunLoopSourceRef _source;
    CFRunLoopObserverRef _beforeWaitingObserver;
#endif
    NSMutableDictionary *_windowsByID;
    // Shows the main menu outside the windows (see X11AppMenu), nil until the
    // application has one or when the menu is drawn inside the windows.
    X11AppMenu *_appMenu;

    id lastFocusedWindow;
    // The click counts per button are in DarlingDisplay.
    Time _lastClickTime;       // X server milliseconds, wraps modulo 2^32.
    unsigned int _lastClickButton;
    XID _lastClickWindow;
    NSPoint _lastClickPoint;   // Logical points, so the radius is scale-independent.
    X11Cursor *_blankCursor, *_defaultCursor;
    // Relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)).
    // _relativeRequested stays set while the application wants it;
    // _relativeMouse.active only while the pointer grab on _relativeWindow is
    // held, which losing the focus releases and regaining it retakes.
    BOOL _relativeRequested;
    int _relativeRetriesLeft;
    // Where the frozen cursor was when the grab was released for a reason other
    // than the application asking (focus loss, reconfiguration), so the next
    // grab puts it back instead of restarting it at the pointer.
    BOOL _relativeResumeValid;
    double _relativeResumeX, _relativeResumeY;
    Window _relativeWindow;
    X11RelativeMouse _relativeMouse;
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
    // The pointer as the last MotionNotify reported it, root coordinates.
    // Valid until an event that may have moved the pointer without one
    // (crossing, button, key or focus events, a warp, a screen change).
    BOOL _pointerKnown;
    int _pointerRootX, _pointerRootY;
    unsigned int _pointerState;
    KeySym _lastKeySym;
    // The aggregate modifier mask as of the last key event, so a change that
    // no modifier key reported (a modifier released while another app had the
    // focus) is still noticed and corrected with a keycode-less flagsChanged.
    NSEventModifierFlags _modifierFlags;
    // The modifier keys currently held, one bit per X keycode. Both Shift keys
    // (or both Control keys) drive the same mask, so releasing one of them only
    // clears it if the other is up too.
    unsigned char _heldModifierKeys[32];
    int _rrEventBase;
    NSArray* _lastScreens;
    // See -primaryRootFrame. Device pixels, root coordinates.
    NSRect _primaryRootFrame;
    BOOL _primaryRootFrameValid;
    CGFloat _backingScale;

@public
    XIM _xim;
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
// Menu and pop-up windows are not managed by the window manager and never
// take the keyboard focus, so a click outside them reaches other clients
// and not the application's tracking of its menu. While any is on the screen
// the pointer is grabbed for the application (owner_events set: its windows
// keep receiving their own events, those elsewhere are delivered as if made
// in the newest menu window), as menus do in other toolkits.
- (void) menuWindowMapped: (X11Window *) window;
- (void) menuWindowUnmapped: (X11Window *) window;
- (id) windowForID: (XID) i;

// The object that shows the main menu outside the windows, created on first
// use; nil if the menu is drawn inside the windows (DarlingInWindowMenuBar).
- (X11AppMenu *) appMenu;
#ifdef DARLING
- (void) processPendingEvents;
#endif
// The pointer's position on the default root window and the button and
// modifier state, from the event stream when it is known, else from the
// server. Returns NO when the pointer is on another screen (the position is
// then on that screen's root window).
- (BOOL) queryPointerRootX: (int *) x y: (int *) y state: (unsigned int *) state;

- (CGFloat) doubleClickInterval;
- (int) handleError: (XErrorEvent *) errorEvent;
@end
