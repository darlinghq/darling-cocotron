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
@class WaylandRenderManager;

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
    CGSWaylandObjectHoldGesture,
    CGSWaylandObjectInputTimestamp,
    CGSWaylandObjectTouch,
    CGSWaylandObjectTabletSeat,
    CGSWaylandObjectTablet,
    CGSWaylandObjectTabletTool,
    CGSWaylandObjectTabletPad,
    CGSWaylandObjectLockedPointer,
    CGSWaylandObjectRelativePointer,
    CGSWaylandObjectWarpLock,
    CGSWaylandObjectBuffer,
    CGSWaylandObjectLayerSurface,
    CGSWaylandObjectPopup,
    CGSWaylandObjectDataDevice,
    CGSWaylandObjectDataOffer,
    CGSWaylandObjectDataSource,
    CGSWaylandObjectCursorScale,
    CGSWaylandObjectDecoration,
    CGSWaylandObjectTextInput,
    CGSWaylandObjectActivationToken,
    CGSWaylandObjectDragSource,
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
    struct wl_proxy *_subcompositor; // wl_subcompositor, for the surfaces that draw GL next to a window's contents
    struct wl_proxy *_shm; // wl_shm, for the pixels of the windows that are drawn into
    struct wl_proxy *_wmBase;
    // What places and frames the windows beyond xdg-shell, NULL when the compositor offers none:
    // wlr-layer-shell (a surface along an edge of the output: the menu bar), the KDE plasma shell
    // (a position for a toplevel), xdg-decoration (the frame is the compositor's).
    struct wl_proxy *_layerShell, *_plasmaShell, *_decorationManager;
    uint32_t _plasmaShellVersion;
    // KDE's appmenu protocol, when the compositor has it: a window tells where its application menu is (see
    // -[CGSWindow setToplevelApplicationMenuServiceName:objectPath:]).
    struct wl_proxy *_appMenuManager;
    uint32_t _appMenuManagerName, _appMenuManagerVersion;
    // alpha-modifier-v1, when the compositor offers it: the opacity of a window's surface (-[CGSWindow setToplevelAlpha:]).
    struct wl_proxy *_alphaModifierManager;
    uint32_t _alphaModifierManagerName;
    // xdg-activation-v1, when the compositor offers it: asks the compositor to focus a window of the process (see
    // -requestActivationOfWindow:from:).
    struct wl_proxy *_activation;
    uint32_t _activationName;

@protected
    // The request for activation that waits for its token, and the window it is for (retained).
    struct wl_proxy *_activationToken;
    CGSWindowWayland *_activationWindow;
    struct wl_proxy *_registry;
    // A Unix domain socket, not a Mach port, so CFRunLoop is used directly.
    CFSocketRef _cfSocket;
    CFRunLoopSourceRef _source;
    NSMutableArray *_outputs;
    // Color management and representation, when the compositor offers them (WaylandColorManager).
    id _color;
    // dma-buf, explicit synchronization and fifo, when the compositor offers them (WaylandRenderManager).
    id _render;
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
    // The seat's touch screen, which decodes the fingers into CGEvents (CGSWaylandTouch).
    id _touchDecoder;
    // The tablet manager's tablet seats, which decode stylus tools into tablet CGEvents (CGSWaylandTablet).
    id _tabletDecoder;
    // The seat's text input, the compositor's input method for the windows (CGSWaylandInputMethod).
    id _inputMethodDecoder;
    struct wl_proxy *_pointerGestures;
    uint32_t _pointerGesturesName;
    // input-timestamps-unstable-v1: one timestamp object per device, handing high-resolution times
    // to the device's decoder before the input event they describe.
    struct wl_proxy *_inputTimestampsManager;
    uint32_t _inputTimestampsName;
    struct wl_proxy *_pointerTimestamps, *_keyboardTimestamps, *_touchTimestamps;
    // The globals the pointer lock (relative mouse mode, warps) is made of; NULL when the compositor offers
    // none.
    struct wl_proxy *_pointerConstraints, *_relativePointerManager;
    uint32_t _pointerConstraintsName, _relativePointerManagerName;
    // The clipboard (CGSWaylandClipboard), made from the data device manager and the seat; nil when the compositor
    // has no data device manager.
    struct wl_proxy *_dataDeviceManager;
    id _clipboard;
    // The drag and drop of the data device (CGSWaylandDrag), made with the clipboard, whose device it shares.
    id _drag;
    // The latest input event of the seat that entitles a client to set the clipboard (a key or button press), and
    // when it was.
    uint32_t _inputSerial;
    CFAbsoluteTime _inputSerialTime;
    // Blocks to run once the events read are dispatched (see -performAfterDispatch:).
    NSMutableArray *_afterDispatch;
    BOOL _afterDispatchRunQueued, _dispatching;
    // pointer-warp-v1, when the compositor offers it: CGWarpMouseCursorPosition() sends a warp request
    // instead of asking for a short pointer lock.
    struct wl_proxy *_pointerWarp;
    uint32_t _pointerWarpName;
    // The globals the pointer's cursor is made with (see CGSWaylandCursor): cursor-shape-v1 (the compositor draws
    // a named cursor) and fractional-scale-v1 (the scale of the cursor surface); NULL when the compositor offers
    // none.
    struct wl_proxy *_cursorShapeManager, *_fractionalScaleManager;
    uint32_t _cursorShapeManagerName, _fractionalScaleManagerName;
    // IOPM assertions: the queue that asks IOKit about them, the notify(3) token of their change
    // notification, and whether this process holds one that keeps the display awake.
    dispatch_queue_t _assertionsQueue;
    int _assertionsNotifyToken;
    BOOL _assertionsNotifyRegistered, _displaySleepPrevented;
    // The registered global hot keys (CGSWaylandHotKeyEntry), guarded by @synchronized(self).
    NSMutableArray *_hotKeys;
    // The xdg-desktop-portal GlobalShortcuts client, created when a hot key is first registered.
    id _portalShortcuts;
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
- (id) waylandColorManager;
- (id) waylandRenderManager;
- (BOOL) extendedDynamicRangeAvailable;
// The shared render-protocol manager, used by this connection's windows.
- (WaylandRenderManager *) renderManager;
// Tells the windows that a color global arrived after they were created.
- (void) notifyWindowsColorManagerAvailable;
// Tells the windows that a render global arrived after they were created.
- (void) notifyWindowsRenderManagerAvailable;

// Runs the block after the events the connection has read are dispatched: not inside a listener of the
// compositor's events, where a request that waits for the compositor would nest in the dispatch. Blocks queued by
// those blocks wait for the next pass. Main thread.
- (void) performAfterDispatch: (void (^)(void)) block;
// A key or a button of the seat was pressed with the serial the compositor gave it: the clipboard can be set
// with it, and what the process has to publish is published.
- (void) inputPressedWithSerial: (uint32_t) serial;
// The serial a request to set the clipboard needs: that of the latest press while a surface of the process has
// the keyboard focus, and for a short time after the focus went (as when the virtual keyboard that made the key is
// removed a few milliseconds after it), 0 otherwise.
- (uint32_t) clipboardSerial;
// The serial of the button press that a drag started now is tied to, 0 when no button is down; a drag that is
// started takes it (see CGSWaylandDrag).
- (uint32_t) dragSerial;
- (struct wl_proxy *) dataDeviceManager;
- (void) consumeDragSerial;

// The seat, NULL until the compositor has described it.
- (struct wl_proxy *) seat;
// The pointer gestures global, NULL when the compositor offers none.
- (struct wl_proxy *) pointerGestures;
// Creates or drops the input timestamp objects to match the seat's devices.
- (void) updateInputTimestamps;
// The pointer constraints and the relative pointer manager, NULL when the compositor offers none.
- (struct wl_proxy *) pointerConstraints;
- (struct wl_proxy *) relativePointerManager;
// The pointer warp global, NULL when the compositor offers none.
- (struct wl_proxy *) pointerWarp;
// The cursor shape and fractional scale globals, NULL when the compositor offers none.
- (struct wl_proxy *) cursorShapeManager;
- (struct wl_proxy *) fractionalScaleManager;
// The largest scale (in 1/120) of the outputs, 120 at least.
- (uint32_t) maximumOutputScale120;
// YES while this process holds a power assertion that keeps the display awake. It is learned from
// IOKit (IOPMCopyAssertionsByProcess), as the compositor cannot be asked for it.
- (BOOL) displaySleepPrevented;
- (void) observeDisplaySleepAssertions;
- (void) refreshDisplaySleepPrevented;
- (void) setDisplaySleepPrevented: (BOOL) prevented;
// The point of one of this connection's windows' surfaces at a global location (the inverse of
// -globalLocation:ofSurface:point:); NO when the surface is not one of its windows.
- (BOOL) surfacePoint: (CGPoint *) point forGlobalLocation: (CGPoint) location ofSurface: (struct wl_proxy *) surface;
// Posts what the pointer decoder holds back until the compositor ends it (a scroll frame).
- (void) flushPendingPointerEvents;
// Posts the modifier key change the keyboard decoder holds back until the compositor confirms it.
- (void) flushPendingKeyboardEvents;

// The windows' input method (see CGSInputMethod.h): the text input of the seat.
- (void) inputMethodWindowChanged: (CGSWindow *) window;
- (void) inputMethodWindowUnmapped: (CGSWindow *) window;
- (void) inputMethodWindowDestroyed: (uint32_t) windowID;
// Asks the compositor, through xdg-activation, to focus a window of this process. The compositor decides: it may only mark
// the window as wanting attention. The token carries the serial of the last key or button press when there is one,
// because compositors refuse requests that cannot be tied to user input. The requester is the window the token names as the
// one that asks (xdg-activation set_surface), nil for none: GUESS: the protocol allows no surface, and some compositors refuse
// that. The variant without a requester picks one: a shown window other than the one to activate. Returns whether a
// request was made; one is not while another waits for its token, and then nothing was asked.
- (BOOL) requestActivationOfWindow: (CGSWindowWayland *) window from: (CGSWindowWayland *) requester;
- (BOOL) requestActivationOfWindow: (CGSWindowWayland *) window;
- (void) cancelActivationRequest;
- (void) activationTokenDone: (const char *) token;
// The window an activation request from another process is for: the one activated last that is shown as a toplevel.
- (CGSWindowWayland *) windowForActivation;
// The window of this connection whose toplevel surface is the wl_surface, 0 when none is.
- (uint32_t) windowIDForSurface: (struct wl_proxy *) surface;
// The serial of the left pointer button press that is held down on a surface of this connection, 0 when the button is not
// down or the pointer is not in that surface.
- (uint32_t) heldLeftPressSerialForSurface: (struct wl_proxy *) surface;
// The window of a surface of this connection, nil for none.
- (CGSWindowWayland *) toplevelForSurface: (struct wl_proxy *) surface;
// Whether the surface is that of a display overlay (a window made with -becomeDisplayOverlay:), and the
// surface of the display overlay shown last, NULL when there is none. The input of an overlay belongs to no
// window of the application.
- (BOOL) isDisplayOverlaySurface: (struct wl_proxy *) surface;
- (struct wl_proxy *) displayOverlaySurface;
// Where a point of the surface is in global coordinates, when it is a surface of this connection's windows.
- (BOOL) globalLocation: (CGPoint *) location ofSurface: (struct wl_proxy *) surface point: (CGPoint) point;
// The uids of the active hot keys that a press of the virtual key keyCode, with the given modifier flags
// in effect, selects: a hot key matches when its key code is the key's and its Shift, Control, Option and
// Command flags are exactly those of the flags (other bits, such as Caps Lock, do not count). Empty while hot
// keys are switched off (the global operating mode is not 0). The keyboard calls this for every key that is
// not a modifier. Hot keys the portal has bound are left out: they are delivered to this process by the portal
// even when none of its surfaces has the focus, so reporting them here as well would post each event twice.
- (NSArray *) activeHotKeyUIDsForKeyCode: (CGKeyCode) keyCode flags: (uint64_t) flags;

// A snapshot of the enabled registered hot keys for the portal: dictionaries with an NSNumber uid,
// an NSNumber virtualKey and an NSNumber flags. Called on the main thread.
- (NSArray *) enabledHotKeysForPortal;
// Whether the xdg-desktop-portal GlobalShortcuts session has bound this uid. Bound uids are not also
// matched against the keys the compositor sends to the process' own wl_keyboard.
- (BOOL) isHotKeyBoundToPortalWithUID: (int) uid;
// The portal reported a press or a release of a bound shortcut. Uses the same CGS event path as the
// key events of the local wl_keyboard. Called on the main thread.
- (void) postPortalHotKeyEventForUID: (int) uid pressed: (BOOL) pressed;
// An XDG shortcut preferred trigger for a virtual key code and modifier flags, from the keymap the
// compositor sent this connection; nil when the key has no keysym name.
- (NSString *) portalTriggerForKeyCode: (CGKeyCode) keyCode flags: (CGEventFlags) flags;

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
