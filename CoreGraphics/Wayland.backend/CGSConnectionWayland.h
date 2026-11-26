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
// the first whose principal class answers +isAvailable. This bundle's NSPriority is
// above X11's, and +isAvailable asks WaylandBackendSelected(): the environment variable
// DARLING_APPKIT_BACKEND, then the DisplayBackend preference, then whether a compositor
// is advertised, the same decision AppKit's Wayland backend makes.
//
// This connection is independent of the one AppKit's Wayland backend opens,
// the same way the CoreGraphics X11 backend calls XOpenDisplay() independently
// of AppKit's X11Display. Windows created here are not AppKit windows.
//
// Native libwayland is reached through WaylandSupport/WaylandLibrary.m, which is
// compiled into this bundle and into AppKit's Wayland backend: it is plain C over
// Foundation and elfcalls, and duplicating its dlopen shim and opcode table would be
// worse than sharing the file.

#ifndef CGSCONNECTIONWAYLAND_H
#define CGSCONNECTIONWAYLAND_H

#import <CoreGraphics/CGSConnection.h>
#import <CoreFoundation/CFRunLoop.h>
#import <CoreFoundation/CFSocket.h>
#import <Foundation/Foundation.h>
#include <stdint.h>
#include <wayland-util.h>

struct wl_display;
struct wl_proxy;

@class CGSWindowWayland;
@class WaylandColorManager;

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
    CGSWaylandObjectLogicalOutput,
    CGSWaylandObjectOutputManager,
    CGSWaylandObjectOutputHead,
    CGSWaylandObjectOutputHeadMode,
    CGSWaylandObjectOutputConfiguration,
    CGSWaylandObjectSeat,
    CGSWaylandObjectKeyboard,
    CGSWaylandObjectKeyboardSync,
    CGSWaylandObjectPointer,
    CGSWaylandObjectPinchGesture,
    CGSWaylandObjectLockedPointer,
    CGSWaylandObjectRelativePointer,
    CGSWaylandObjectWarpLock,
    CGSWaylandObjectIdleNotification,
} CGSWaylandObjectKind;

// Displays: the connection describes them from wl_output, xdg-output (the compositor's logical
// layout) and, where the compositor offers it, wlr-output-management, which also lets
// -setMode:forScreen: change a mode. The keyboard layout is made from the keymap the compositor sends
// to this connection's wl_keyboard (see CGSWaylandKeymap), which also decodes the key events into CGEvents
// (see CGSWaylandKeyboard).
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
    // Color management and representation, when the compositor offers them (WaylandColorManager).
    id _color;
    struct wl_proxy *_logicalOutputManager, *_legacyLogicalOutputManager;
    uint32_t _logicalOutputManagerName;
    id _outputManager;
    uint32_t _outputManagerName;
    // The seat and its keyboard, the process' only wl_keyboard: it provides the keymap (the keyboard
    // layout is the connection's, see -createKeyboardLayout) and the key events.
    struct wl_proxy *_seat, *_keyboard;
    id _keymap;
    // Decodes the keyboard into CGEvents (CGSWaylandKeyboard).
    id _keyboardDecoder;
    // The seat's pointer, which decodes the pointer into CGEvents (CGSWaylandPointer), and the pinch
    // gesture factory it makes the pinch object from.
    id _pointerDecoder;
    struct wl_proxy *_pointerGestures;
    uint32_t _pointerGesturesName;
    // The globals the pointer lock (relative mouse mode, warps) is made of; NULL when the compositor offers
    // none.
    struct wl_proxy *_pointerConstraints, *_relativePointerManager;
    uint32_t _pointerConstraintsName, _relativePointerManagerName;
    // pointer-warp-v1, when the compositor offers it: CGWarpMouseCursorPosition() sends a warp request
    // instead of asking for a short pointer lock.
    struct wl_proxy *_pointerWarp;
    uint32_t _pointerWarpName;
    // ext-idle-notify-v1: the compositor's idle state, used for CGDisplayIsAsleep().
    struct wl_proxy *_idleNotifier, *_idleNotification;
    uint32_t _idleNotifierName, _idleNotifierVersion, _seatName;
    BOOL _displayIdle;
    // The registered global hot keys (CGSWaylandHotKeyEntry), guarded by @synchronized(self).
    NSMutableArray *_hotKeys;
    // Set when the setup roundtrips are over; an output that is described before that is
    // part of the displays the first look finds, not a change.
    BOOL _setupDone;
    // The displays changed in this pass over the events; the observer is told when it is over.
    BOOL _layoutChangedForObserver;
    // libnotify registration for requests to activate this process' windows.
    BOOL _activationRegistered;
    int _activationNotifyToken;
}

- (void) flush;
// The shared color manager, or nil when the compositor offers neither color protocol.
- (WaylandColorManager *) colorManager;
// Tells the windows that a color global arrived after they were created.
- (void) notifyWindowsColorManagerAvailable;

// The pointer gestures global, NULL when the compositor offers none.
- (struct wl_proxy *) pointerGestures;
// The pointer constraints and the relative pointer manager, NULL when the compositor offers none.
- (struct wl_proxy *) pointerConstraints;
- (struct wl_proxy *) relativePointerManager;
// The pointer warp global, NULL when the compositor offers none.
- (struct wl_proxy *) pointerWarp;
// YES after ext-idle-notification's idled event and until resumed. The compositor decides what
// inactivity means and when the display actually blanks; this is the closest core graphics has.
- (BOOL) displayIdle;
// Creates or drops the notification as the manager and wl_seat become available.
- (void) updateIdleNotification;
- (void) idleNotificationEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
// The point of one of this connection's windows' surfaces at a global location (the inverse of
// -globalLocation:ofSurface:point:); NO when the surface is not one of its windows.
- (BOOL) surfacePoint: (CGPoint *) point forGlobalLocation: (CGPoint) location ofSurface: (struct wl_proxy *) surface;
// Posts what the pointer decoder holds back until the compositor ends it (a scroll frame).
- (void) flushPendingPointerEvents;
// The window of this connection whose toplevel surface is the wl_surface, 0 when none is.
- (uint32_t) windowIDForSurface: (struct wl_proxy *) surface;
// Where a point of the surface is in global coordinates, when it is a surface of this connection's windows.
- (BOOL) globalLocation: (CGPoint *) location ofSurface: (struct wl_proxy *) surface point: (CGPoint) point;
// The uids of the active hot keys that a press of the virtual key keyCode, with the given modifier flags
// in effect, selects: a hot key matches when its key code is the key's and its Shift, Control, Option and
// Command flags are exactly those of the flags (other bits, such as Caps Lock, do not count). Empty while hot
// keys are switched off (the global operating mode is not 0). The keyboard calls this for every key that is
// not a modifier.
- (NSArray *) activeHotKeyUIDsForKeyCode: (CGKeyCode) keyCode flags: (uint64_t) flags;

// Sends a request that creates an object and installs the dispatcher on it.
- (struct wl_proxy *) createObject: (struct wl_proxy *) proxy
                            opcode: (uint32_t) opcode
                         interface: (const struct wl_interface *) interface
                         arguments: (union wl_argument *) args
                              kind: (CGSWaylandObjectKind) kind
                            object: (id) object;

// Installs the connection's dispatcher on a proxy the compositor created with an event.
- (void) attachDispatcherTo: (struct wl_proxy *) proxy
                       kind: (CGSWaylandObjectKind) kind
                     object: (id) object;

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
              object: (id) object
           arguments: (union wl_argument *) args;

@end

#endif
