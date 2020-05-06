//
//  X11Display.h
//  AppKit
//
//  Created by Johannes Fortmann on 13.10.08.
//  Copyright 2008 -. All rights reserved.
//

#import <AppKit/NSDisplay.h>
#import <X11/Xlib.h>

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
    BOOL _cursorGrabbed;
}

- (Display *) display;

- (void) setWindow: (id) window forID: (XID) i;

- (CGFloat) doubleClickInterval;
- (int) handleError: (XErrorEvent *) errorEvent;
@end
