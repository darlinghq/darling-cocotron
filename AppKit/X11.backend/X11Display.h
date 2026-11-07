//
//  X11Display.h
//  AppKit
//
//  Created by Johannes Fortmann on 13.10.08.
//  Copyright 2008 -. All rights reserved.
//

#import <AppKit/NSDisplay.h>
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import "X11RelativeMouseGrab.h"
#import <X11/Xlib.h>
#import <X11/Xresource.h>
#import <X11/Xlocale.h>

#ifdef DARLING
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#endif

@class X11Cursor;

@interface X11Display : NSDisplay {
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

    id lastFocusedWindow;
    // Clicks are grouped per button and per window, so state for the left
    // button cannot make the next middle-button click look like a double click.
    NSMutableDictionary *_buttonClickCounts;
    NSInteger _clickCount;
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

@public
    XIM _xim;
}

- (Display *) display;

// The main monitor's rectangle in root coordinates. It is the origin of the
// global coordinate space; see X11Monitors.h.
- (NSRect) primaryRootFrame;
// The same rectangle as an X11Frame, in the unit of window frames.
- (X11Frame) primaryFrameInPoints;
// Converts a point in root coordinates to CoreGraphics' global space.
- (NSPoint) cgPointFromRoot: (NSPoint) root;
- (void) setWindow: (id) window forID: (XID) i;
- (id) windowForID: (XID) i;
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
