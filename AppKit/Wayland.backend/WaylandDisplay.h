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
// Selection: the backend is opt-in. Its NSPriority is above X11's, but -init
// returns nil unless DARLING_APPKIT_BACKEND=wayland, so NSDisplay goes on to
// the X11 backend as before. It also returns nil (after logging why) when
// libwayland-client/libxkbcommon can't be loaded or the compositor named by
// WAYLAND_DISPLAY can't be reached, which falls back to X11 the same way.
//
// WaylandDisplay subclasses X11Display to share its backend-independent parts
// (system colours, fontconfig font enumeration, metrics) without copying them.
// It never opens an X connection and overrides every method that uses one.
//
// Toplevel origins remain virtual because Wayland controls global placement.
// Clipboard and incoming copy drops use wl_data_device; outgoing drags and
// OpenGL subwindows are follow-ons.

#import "X11Display.h"
#include <stdint.h>
#include <wayland-util.h>

struct wl_display;
struct wl_proxy;
struct wl_cursor_theme;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;

@class WaylandCursor, WaylandWindow, WaylandPasteboard, WaylandDraggingManager;

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

@interface WaylandDisplay : X11Display {
@public
    struct wl_display *_wlDisplay;
    struct wl_proxy *_registry;
    struct wl_proxy *_compositor;
    struct wl_proxy *_logicalOutputManager, *_legacyLogicalOutputManager;
    uint32_t _logicalOutputManagerName;
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
    int32_t _cursorThemeScale;
    struct wl_proxy *_cursorSurface;
    struct wl_proxy *_imageCursorBuffer;
    int32_t _imageCursorBufferScale;
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
- (void) windowScaleChanged: (WaylandWindow *) window;
- (WaylandWindow *) popupParentForWindow: (WaylandWindow *) window;
- (uint32_t) popupGrabSerialForParent: (WaylandWindow *) parent;
- (struct wl_proxy *) seat;
- (void) unmapPopupsForParent: (WaylandWindow *) parent;
- (void) cancelPopupMenus;

// Runs a block after libwayland has returned from dispatching events. Event
// handlers queue application-facing calls this way, so application code never
// runs (and exceptions never unwind) inside native libwayland frames.
- (void) performAfterDispatch: (void (^)(void)) block;

- (void) windowCreated: (WaylandWindow *) window;
- (void) windowActivated: (WaylandWindow *) window;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) windowDestroyed: (WaylandWindow *) window;

@end
