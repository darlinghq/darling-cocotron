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
#endif
    NSMutableDictionary *_windowsByID;

    id lastFocusedWindow;
    NSTimeInterval lastClickTimeStamp;
    int clickCount;
    X11Cursor *_blankCursor, *_defaultCursor;
    // Relative mouse mode (CGAssociateMouseAndMouseCursorPosition(false)).
    // _relativeRequested stays set while the application wants it;
    // _relativeMouse.active only while the pointer grab on _relativeWindow is
    // held, which losing the focus releases and regaining it retakes.
    BOOL _relativeRequested;
    Window _relativeWindow;
    X11RelativeMouse _relativeMouse;
    // Xwayland forwards a pointer warp to the compositor only while the X
    // cursor is hidden, so warps are not honoured with a visible cursor there.
    BOOL _isXwayland;
    BOOL _cursorHidden;
    KeySym _lastKeySym;
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

- (CGFloat) doubleClickInterval;
- (int) handleError: (XErrorEvent *) errorEvent;
@end
