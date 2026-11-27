/* CoreGraphics Wayland backend: the text input (the compositor's input method).

 Copyright (C) 2026 Lubos Dolezel

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

// The process' zwp_text_input_v3 on Wayland, which is the backend's part of the window system's input method (see
// CGSInputMethod.h). The compositor's input method sends the composition (preedit_string), the final text
// (commit_string) and deletions of the text around the caret between enter and leave, as one state that applies at
// done; they become toplevel events of the window whose surface the compositor entered. What the windows say of
// themselves (whether they take text, where the caret is, the text around it, the kind of text) is sent to the
// compositor as the protocol's enable/disable and state requests, each batch followed by commit, and only while a
// window has the text input focus.

#ifndef CGSWAYLANDINPUTMETHOD_H
#define CGSWAYLANDINPUTMETHOD_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class CGSWindow;
struct wl_proxy;

@interface CGSWaylandInputMethod : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the decoder
    struct wl_proxy *_manager, *_seat, *_textInput;
    uint32_t _managerName, _seatName;
    // The window whose surface the compositor entered (0: none), and what was sent to the compositor for it.
    uint32_t _entered;
    BOOL _sentEnabled, _sentSurroundingValid;
    CGRect _sentRect;
    NSString *_sentSurrounding;
    int _sentCursor, _sentAnchor;
    uint32_t _sentHint, _sentPurpose;
    // The state of the done in progress.
    NSString *_pendingPreedit, *_pendingCommit;
    int _pendingCursorBegin, _pendingCursorEnd;
    uint32_t _pendingDeleteBefore, _pendingDeleteAfter;
    // The composition the window was last told of.
    NSString *_preedit;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection;

// The compositor's text input manager and the seat, in whichever order they arrive; the text input is made from both.
- (void) managerBound: (struct wl_proxy *) manager name: (uint32_t) name seat: (struct wl_proxy *) seat;
- (void) seatBound: (struct wl_proxy *) seat name: (uint32_t) name;
- (void) managerRemoved;
- (void) seatRemoved;
// Whether the compositor has an input method protocol that a window can use.
- (BOOL) available;
- (uint32_t) managerName;
- (uint32_t) seatName;

// A window's input method state (enabled, cursor rectangle, surrounding text, content type) changed: it is sent when
// the window has the text input focus.
- (void) windowChanged: (CGSWindow *) window;
// The window's surface goes away (or the window is unmapped): a composition it showed is over.
- (void) windowGone: (CGSWindow *) window;
// One event of the zwp_text_input_v3.
- (void) textInputEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
// Destroys the text input.
- (void) stop;

@end

#endif
