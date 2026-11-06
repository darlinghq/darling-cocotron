//
//  X11Display.h
//  AppKit
//
//  Created by Johannes Fortmann on 13.10.08.
//  Copyright 2008 -. All rights reserved.
//

#import <AppKit/NSDisplay.h>
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
    // Clicks are grouped per button and per window, so state for the left
    // button cannot make the next middle-button click look like a double click.
    NSMutableDictionary *_buttonClickCounts;
    NSInteger _clickCount;
    Time _lastClickTime;       // X server milliseconds, wraps modulo 2^32.
    unsigned int _lastClickButton;
    XID _lastClickWindow;
    NSPoint _lastClickPoint;   // Logical points, so the radius is scale-independent.
    X11Cursor *_blankCursor, *_defaultCursor;
    BOOL _cursorGrabbed;
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

@public
    XIM _xim;
}

- (Display *) display;

- (void) setWindow: (id) window forID: (XID) i;
- (id) windowForID: (XID) i;
#ifdef DARLING
- (void) processPendingEvents;
#endif

- (CGFloat) doubleClickInterval;
- (int) handleError: (XErrorEvent *) errorEvent;
@end
