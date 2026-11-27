/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

// The xdg-desktop-portal GlobalShortcuts client of the CoreGraphics Wayland backend. A session
// offers the connection's registered hot keys to the desktop; the desktop asks the user to confirm
// them and reports presses and releases as Activated and Deactivated signals, which are posted into
// the same CGS event stream as the keys of the local wl_keyboard.
//
// The portal is optional: when no session bus, portal or backend is available, registration still
// succeeds and the hot keys keep working while the process has the keyboard focus.

#ifndef CGSWAYLANDPORTALSHORTCUTS_H
#define CGSWAYLANDPORTALSHORTCUTS_H

#import <CoreFoundation/CFSocket.h>
#import <Foundation/NSObject.h>
#include <dbus/dbus.h>

@class CGSConnectionWayland;
@class NSMutableSet;
@class NSNumber;
@class NSString;

@interface CGSWaylandPortalShortcuts : NSObject {
    // The connection owns this object.
    CGSConnectionWayland *_connection;
    DBusConnection *_bus;
    CFSocketRef _socket;
    CFRunLoopSourceRef _source;
    NSString *_portalOwner;
    NSString *_sessionPath;
    NSString *_requestPath;
    // What _requestPath answers: 1 CreateSession, 2 BindShortcuts.
    int _requestKind;
    // A hot key set changed while a request was in flight; rebuild the session after it answers.
    BOOL _restartRequested;
    unsigned long long _counter;
    // The uids the desktop has bound, and the uids whose press has not yet had a release.
    NSMutableSet *_boundUIDs;
    NSMutableSet *_pressedUIDs;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection;
- (void) invalidate;
// The registered hot keys changed: offer the current set in a new session.
- (void) hotKeysDidChange;
// Whether the desktop bound this uid; the local keyboard must not report it a second time.
- (BOOL) isUIDBound: (int) uid;

@end

#endif
