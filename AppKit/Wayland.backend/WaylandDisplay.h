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
// Limitations of this first version: Wayland lets clients neither place
// toplevels nor read global coordinates, so each window keeps the origin
// AppKit gave it and the compositor chooses the real position; menus and
// pop-ups are separate toplevels (no xdg_popup yet); there is no clipboard or
// drag and drop, no OpenGL subwindow, no pointer warping or grabbing; buffers
// use scale 1 and HiDPI outputs are scaled by the compositor; windows have no
// title bar unless the compositor offers server-side decorations.

#import "X11Display.h"
#include <stdint.h>
#include <wayland-util.h>

struct wl_display;
struct wl_proxy;
struct wl_cursor_theme;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;

@class WaylandCursor, WaylandWindow;

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
    WaylandObjectDecoration,
    WaylandObjectFrameCallback,
    WaylandObjectBuffer,
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
    struct wl_proxy *_shm;
    struct wl_proxy *_wmBase;
    struct wl_proxy *_decorationManager;
    uint32_t _compositorVersion;

@protected
    struct wl_proxy *_seat;
    struct wl_proxy *_pointer;
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
    NSTimeInterval _lastClickTime;
    NSInteger _clickCount;

    struct xkb_context *_xkbContext;
    struct xkb_keymap *_xkbKeymap;
    struct xkb_state *_xkbState;
    WaylandWindow *_keyboardWindow;
    int32_t _repeatRate;
    int32_t _repeatDelay;
    uint32_t _repeatKeycode;
    CFRunLoopTimerRef _repeatTimer;

    struct wl_cursor_theme *_cursorTheme;
    struct wl_proxy *_cursorSurface;
    struct wl_proxy *_imageCursorBuffer;
    WaylandCursor *_cursor;
}

- (void) flush;

// Runs a block after libwayland has returned from dispatching events. Event
// handlers queue application-facing calls this way, so application code never
// runs (and exceptions never unwind) inside native libwayland frames.
- (void) performAfterDispatch: (void (^)(void)) block;

- (void) windowCreated: (WaylandWindow *) window;
- (void) windowActivated: (WaylandWindow *) window;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) windowDestroyed: (WaylandWindow *) window;

@end
