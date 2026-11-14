/* Permission is hereby granted, free of charge, to any person obtaining a copy of
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

// Wayland display backend.
//
// Selection: see WaylandBackendSelected(): DARLING_APPKIT_BACKEND, then the DisplayBackend
// preference, then whether WAYLAND_DISPLAY is set. -init returns nil when the backend is not
// selected and (after logging why) when libwayland-client/libxkbcommon can't be loaded or the
// compositor can't be reached, which makes NSDisplay go on to the X11 backend.
//
// WaylandDisplay subclasses DarlingDisplay, which holds the parts shared with the
// X11 backend (system colours, fontconfig font enumeration, metrics, click counts).
//
// Toplevel origins remain virtual because Wayland controls global placement.
// Clipboard and incoming copy drops use wl_data_device; EGL subwindows use
// synchronized subsurfaces. Outgoing drags are a follow-on.

#import "../private-include/AppKit/DarlingDisplay.h"
#include <stdint.h>
#include <wayland-util.h>
#include "WaylandFullscreen.h"

struct wl_display;
struct wl_proxy;
struct wl_cursor_theme;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;

@class WaylandCursor, WaylandWindow, WaylandPasteboard, WaylandDraggingManager;

@protocol WaylandFractionalScaleOwner
- (void) preferredScaleChanged: (uint32_t) scale120;
@end

// Identifies the object a dispatched event belongs to.
typedef enum {
    WaylandObjectRegistry = 1,
    WaylandObjectWmBase,
    WaylandObjectSeat,
    WaylandObjectPointer,
    WaylandObjectKeyboard,
    WaylandObjectOutput,
    WaylandObjectSurface,
    WaylandObjectXdgSurface,
    WaylandObjectToplevel,
    WaylandObjectPopup,
    WaylandObjectDecoration,
    WaylandObjectFrameCallback,
    WaylandObjectBuffer,
    WaylandObjectKeyboardSync,
    WaylandObjectLogicalOutput,
    WaylandObjectPinchGesture,
    WaylandObjectDataDevice,
    WaylandObjectDataOffer,
    WaylandObjectDataSource,
    WaylandObjectFractionalScale,
    WaylandObjectLockedPointer,
    WaylandObjectRelativePointer,
} WaylandObjectKind;

// The dispatcher installed on every proxy (see WaylandLibrary.h for why listeners
// aren't used). The dispatcher data is the WaylandObjectKind, the user data the
// Objective-C object that handles the event.
int WaylandDispatch(const void *kind, void *proxy, uint32_t opcode,
                    const struct wl_message *message, union wl_argument *args);

// Sends a request that creates an object and installs the dispatcher on it
// (unless kind is 0). libwayland only fails here when it can't allocate the
// proxy, so that exits like a lost connection does.
struct wl_proxy *WaylandCreateObject(struct wl_proxy *proxy, uint32_t opcode,
                                     const struct wl_interface *interface,
                                     union wl_argument *args,
                                     WaylandObjectKind kind, id object);

@interface WaylandDisplay : DarlingDisplay {
@public
    struct wl_display *_wlDisplay;
    struct wl_proxy *_registry;
    struct wl_proxy *_compositor;
    struct wl_proxy *_viewporter, *_fractionalScaleManager;
    uint32_t _viewporterName, _fractionalScaleManagerName;
    struct wl_proxy *_logicalOutputManager, *_legacyLogicalOutputManager;
    uint32_t _logicalOutputManagerName;
    struct wl_proxy *_subcompositor;
    BOOL _eglAvailable;
    struct wl_proxy *_shm;
    struct wl_proxy *_wmBase;
    struct wl_proxy *_decorationManager;
    struct wl_proxy *_dataDeviceManager;
    uint32_t _compositorVersion;

@protected
    struct wl_proxy *_seat;
    struct wl_proxy *_pointer;
    struct wl_proxy *_pointerGestures, *_pinchGesture;
    uint32_t _pointerGesturesName;
    WaylandWindow *_pinchWindow;
    struct wl_proxy *_pointerConstraints, *_relativePointerManager;
    uint32_t _pointerConstraintsName, _relativePointerManagerName;
    // CGAssociateMouseAndMouseCursorPosition(false) was asked for; the lock
    // objects exist only while a window can take them, and _pointerLocked is the
    // compositor's word that the lock is active.
    BOOL _pointerLockRequested, _pointerLocked;
    struct wl_proxy *_lockedPointer, *_relativePointer;
    WaylandWindow *_lockWindow; // Nonretained; cleared on unmap.
    CGFloat _pinchScale;
    struct wl_proxy *_keyboard;
    CFSocketRef _wlSocket;
    CFRunLoopSourceRef _wlSource;
    NSMutableArray *_outputs;
    NSArray *_screens;
    // WaylandWindows, not retained, most recently activated first.
    CFMutableArrayRef _windows;
    NSMutableArray *_afterDispatch;

    WaylandWindow *_pointerWindow;
    CGPoint _pointerSurfacePoint;
    NSPoint _lastMouseLocation;
    uint32_t _pointerEnterSerial;
    NSUInteger _pressedButtons;
    CGFloat _pendingScrollX, _pendingScrollY;
    WaylandWindow *_pendingScrollWindow;
    CGPoint _pendingScrollSurfacePoint;
    NSUInteger _pendingScrollModifiers;
    BOOL _pendingScrollActive;
    uint32_t _wlLastClickTime; // Compositor milliseconds, wraps modulo 2^32.
    uint32_t _wlLastClickButton;
    WaylandWindow *_wlLastClickWindow; // Nonretained; cleared on unmap/device loss.
    CGPoint _wlLastClickPoint;
    uint32_t _inputSerial;
    NSEvent *_inputEvent;
    WaylandWindow *_inputWindow;
    NSEvent *_dragPressEvent;
    WaylandWindow *_dragPressWindow; // Nonretained; invalidated on unmap.
    uint32_t _dragPressSerial, _dragPressButton;
    WaylandDraggingManager *_draggingManager;

    struct xkb_context *_xkbContext;
    struct xkb_keymap *_xkbKeymap;
    struct xkb_state *_xkbState;
    WaylandWindow *_keyboardWindow;
    BOOL _syncModifierFlags;
    BOOL _classifyHeldKeys;
    // Raw XKB keycode -> identity at press time; -1 denotes a non-modifier.
    NSMutableDictionary *_heldKeyIdentities;
    struct wl_proxy *_modifierSync;
    BOOL _hasModifierKeycode;
    unsigned short _modifierKeycode;
    int32_t _repeatRate;
    int32_t _repeatDelay;
    uint32_t _repeatKeycode;
    CFRunLoopTimerRef _repeatTimer;

    struct wl_cursor_theme *_cursorTheme;
    uint32_t _cursorThemeScale120;
    struct wl_proxy *_cursorSurface, *_cursorFractionalScale, *_cursorViewport;
    uint32_t _cursorPreferredScale120;
    struct wl_proxy *_imageCursorBuffer;
    uint32_t _imageCursorBufferScale120;
    WaylandCursor *_cursor;
    BOOL _applyingCursor, _cursorApplyPending, _cursorApplyQueued;
    WaylandPasteboard *_generalPasteboard;
    NSMutableDictionary *_namedPasteboards;
}

- (WaylandWindow *) windowForSurface: (struct wl_proxy *) surface;
// Caller owns the returned native immutable buffer.
- (struct wl_proxy *) newARGBBuffer: (NSData *) pixels pixelSize: (NSSize) size;
- (struct wl_proxy *) dragDataDevice;
- (WaylandWindow *) dragOriginForEvent: (NSEvent *) event;
- (uint32_t) dragSerialForEvent: (NSEvent *) event;
- (void) consumeDragPress;
- (void) flush;
- (void) processPendingEvents;
- (uint32_t) clipboardSerial;
- (int32_t) scaleForOutput: (struct wl_proxy *) output;
- (uint32_t) refreshForOutput: (struct wl_proxy *) output; // millihertz, 0 if unknown
- (void) preferredScaleChanged: (uint32_t) scale120;
- (void) windowScaleChanged: (WaylandWindow *) window;
- (WaylandWindow *) popupParentForWindow: (WaylandWindow *) window;
- (uint32_t) popupGrabSerialForParent: (WaylandWindow *) parent;
- (struct wl_proxy *) seat;
// Fills `result` and `proxies` with up to `max` outputs in -screens order: their
// logical sizes and whether they are in `entered` (NSValue pointers, as
// WaylandWindow keeps its entered outputs). Returns 0 until an output has
// reported a mode.
- (size_t) fullscreenOutputs: (WaylandFullscreenOutput *) result
                     proxies: (struct wl_proxy **) proxies
                         max: (size_t) max
                     entered: (NSSet *) entered;
- (void) unmapPopupsForParent: (WaylandWindow *) parent;
- (void) cancelPopupMenus;
- (void) updatePointerLock;
- (void) releasePointerLock;
- (void) pointerRelativeMotionByX: (CGFloat) dx y: (CGFloat) dy;

// Runs a block after libwayland has returned from dispatching events. Event
// handlers queue application-facing calls this way, so application code never
// runs (and exceptions never unwind) inside native libwayland frames.
- (void) performAfterDispatch: (void (^)(void)) block;

- (void) windowCreated: (WaylandWindow *) window;
- (void) windowActivated: (WaylandWindow *) window;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) windowDestroyed: (WaylandWindow *) window;

- (struct wl_proxy *) newFractionalScaleForSurface: (struct wl_proxy *) surface owner: (id<WaylandFractionalScaleOwner>) owner;
@end
