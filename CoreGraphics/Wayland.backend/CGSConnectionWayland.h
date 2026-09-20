/* CoreGraphics Wayland backend: the window-server connection.

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

// The CoreGraphics counterpart of AppKit's Wayland backend. CGS.m picks a
// backend by sorting the bundles in Resources/Backends by NSPriority and taking
// the first whose principal class answers +isAvailable; there is no environment
// variable in that path. This bundle's NSPriority is above X11's, and
// +isAvailable requires DARLING_APPKIT_BACKEND=wayland, so a process that did
// not opt in keeps getting the X11 backend exactly as before.
//
// This connection is independent of the one AppKit's Wayland backend opens,
// the same way the CoreGraphics X11 backend calls XOpenDisplay() independently
// of AppKit's X11Display. Windows created here are not AppKit windows.
//
// Native libwayland is reached through AppKit/Wayland.backend/WaylandLibrary.m,
// which is compiled into this bundle as well: it is plain C over Foundation and
// elfcalls with no AppKit dependency, and duplicating its dlopen shim and
// opcode table would be worse than sharing the file.

#ifndef CGSCONNECTIONWAYLAND_H
#define CGSCONNECTIONWAYLAND_H

#import <CoreGraphics/CGSConnection.h>
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#include <stdint.h>
#include <wayland-util.h>

struct wl_display;
struct wl_proxy;

@class CGSWindowWayland;

// Identifies the object a dispatched event belongs to, the way AppKit's backend
// does: libwayland listener structs are unusable across the Darwin/Linux
// variadic ABI split, so every proxy gets a dispatcher instead.
typedef enum {
    CGSWaylandObjectNone = 0, // Install no dispatcher.
    CGSWaylandObjectRegistry,
    CGSWaylandObjectOutput,
    CGSWaylandObjectWmBase,
    CGSWaylandObjectXdgSurface,
    CGSWaylandObjectToplevel,
} CGSWaylandObjectKind;

// -createKeyboardLayout and -setMode:forScreen: are deliberately not overridden,
// so they raise through NSInvalidAbstractInvocation(). Wayland only hands a
// client the keymap over wl_keyboard once one of its surfaces has focus, and
// mode setting is the compositor's alone; nothing in tree calls either.
@interface CGSConnectionWayland : CGSConnection {
@public
    struct wl_display *_wlDisplay;
    struct wl_proxy *_compositor;
    struct wl_proxy *_wmBase;

@protected
    struct wl_proxy *_registry;
    // A Unix domain socket, not a Mach port, so CFRunLoop is used directly.
    CFSocketRef _cfSocket;
    CFRunLoopSourceRef _source;
    NSMutableArray *_outputs;
    NSArray<CGSScreen *> *_screens; // Rebuilt when an output changes.
}

- (void) flush;

// Sends a request that creates an object and installs the dispatcher on it.
- (struct wl_proxy *) createObject: (struct wl_proxy *) proxy
                            opcode: (uint32_t) opcode
                         interface: (const struct wl_interface *) interface
                         arguments: (union wl_argument *) args
                              kind: (CGSWaylandObjectKind) kind
                            object: (id) object;

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
              object: (id) object
           arguments: (union wl_argument *) args;

@end

#endif
