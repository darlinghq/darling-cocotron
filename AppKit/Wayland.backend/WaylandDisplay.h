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
// EGL subwindows use synchronized subsurfaces. The clipboard and drag and drop are
// CoreGraphics'.

#import "../private-include/AppKit/DarlingDisplay.h"
#import <CoreGraphics/CGSNativeConnection.h>
#include <stdint.h>
#include <wayland-util.h>
#include "WaylandFullscreen.h"

struct wl_display;
struct wl_proxy;
struct xkb_context;
struct xkb_keymap;
struct xkb_state;

@class WaylandWindow, WaylandAppMenu, WaylandToplevelIcons, WaylandColorManager, WaylandRenderManager;

@protocol WaylandFractionalScaleOwner
- (void) preferredScaleChanged: (uint32_t) scale120;
@end

// Identifies the object a dispatched event belongs to.
typedef enum {
    WaylandObjectRegistry = 1,
    WaylandObjectWmBase,
    WaylandObjectSeat,
    WaylandObjectOutput,
    WaylandObjectSurface,
    WaylandObjectXdgSurface,
    WaylandObjectToplevel,
    WaylandObjectPopup,
    WaylandObjectDecoration,
    WaylandObjectFrameCallback,
    WaylandObjectBuffer,
    WaylandObjectFractionalScale,
    WaylandObjectLockedPointer,
    WaylandObjectRelativePointer,
    WaylandObjectLayerSurface,
    WaylandObjectIconManager,
    // The session protocol's objects. These are above the color manager's range so the two sets
    // can each be recognized with one comparison in the dispatcher.
    WaylandObjectSessionManager = 1100,
    WaylandObjectSession,
    WaylandObjectToplevelSession,
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

@interface WaylandDisplay : DarlingDisplay <CGSNativeConnectionObserver> {
@public
    struct wl_display *_wlDisplay;
    struct wl_proxy *_registry;
    struct wl_proxy *_compositor;
    struct wl_proxy *_viewporter, *_fractionalScaleManager;
    // Windows of an inactive application that were not mapped are being mapped for an activation.
    BOOL _mappingForActivation;
    uint32_t _viewporterName, _fractionalScaleManagerName;
    struct wl_proxy *_subcompositor;
    // KDE's plasma-shell protocol, when the compositor has it: a toplevel that is not an application
    // window asks it to keep the window out of task lists and switchers (xdg-shell has no way to).
    struct wl_proxy *_plasmaShell;
    uint32_t _plasmaShellName, _plasmaShellVersion;
    // xdg-toplevel-icon, when the compositor has it: the application icon for every toplevel.
    WaylandToplevelIcons *_toplevelIcons;
    // The exported main menu; nil while the menu is drawn inside the windows.
    WaylandAppMenu *_appMenu;
    BOOL _eglAvailable;
    struct wl_proxy *_shm;
    struct wl_proxy *_wmBase;
    struct wl_proxy *_decorationManager;
    // wlr-layer-shell, when the compositor has it: the menu bar is a layer surface.
    struct wl_proxy *_layerShell;
    uint32_t _layerShellName;
    uint32_t _compositorVersion;
    // xdg-session-management: one session for the application, started when AppKit reports why the
    // application launched. Toplevels join it before their first commit.
    struct wl_proxy *_sessionManager, *_session;
    uint32_t _sessionManagerName;
    NSString *_sessionIdentifier;
    NSUInteger _sessionReason;
    BOOL _sessionRequested;
    // xdg-dialog-v1: tells the compositor which toplevels are sheets or modal panels.
    struct wl_proxy *_dialogManager;
    uint32_t _dialogManagerName;
    // xdg-system-bell-v1: the compositor's bell, used by NSBeep().
    struct wl_proxy *_bell;
    uint32_t _bellName;
    // xdg-toplevel-tag-v1: stable window tags for compositor-side window rules.
    struct wl_proxy *_toplevelTagManager;
    uint32_t _toplevelTagManagerName;
    // idle-inhibit-unstable-v1: visible, unoccluded toplevels keep the display awake while the process holds a
    // power assertion that prevents display sleep.
    struct wl_proxy *_idleInhibitManager;
    uint32_t _idleInhibitManagerName;
    // wp_content_type_v1: the compositor is told whether a window shows a game or video.
    struct wl_proxy *_contentTypeManager;
    uint32_t _contentTypeManagerName;
    // keyboard-shortcuts-inhibit-unstable-v1: fullscreen windows take the compositor's shortcuts.
    struct wl_proxy *_shortcutsInhibitManager;
    uint32_t _shortcutsInhibitManagerName;

@protected
    struct wl_proxy *_seat;
    struct wl_proxy *_pointer;
    // The outputs and the rest of the connection are set up; changes of the outputs are passed on.
    BOOL _setupDone;
    // A change of the outputs waits for the end of the pass over the events.
    BOOL _outputsChangePending;
    NSMutableArray *_outputs;
    // WaylandWindows, not retained, most recently activated first.
    CFMutableArrayRef _windows;
    NSMutableArray *_afterDispatch;
    BOOL _afterDispatchRunQueued;

    WaylandWindow *_pointerWindow;
    CGPoint _pointerSurfacePoint;
    uint32_t _pointerEnterSerial;
    NSUInteger _pressedButtons;
    // The serial of the press that was the first of a group of buttons: its NSEvent is the one a drag starts from.
    uint32_t _firstPressSerial;
    uint32_t _inputSerial;
    NSEvent *_inputEvent;
    WaylandWindow *_inputWindow;
    NSEvent *_dragPressEvent;
    WaylandWindow *_dragPressWindow; // Nonretained; invalidated on unmap.
    uint32_t _dragPressSerial, _dragPressButton;

    // The window the keyboard focus last went to, as CoreGraphics reported it; not retained, cleared when
    // the window is unmapped.
    WaylandWindow *_keyboardFocusWindow;
    // The keyboard focus was in a window of the application that was unmapped; its leave event has not arrived.
    BOOL _keyboardWindowUnmapped;

    // The pointer is over a window decoration, where the arrow is shown whatever cursor the application selected.
    BOOL _cursorOverDecoration;
}

- (WaylandWindow *) windowForSurface: (struct wl_proxy *) surface;
- (WaylandWindow *) dragOriginForEvent: (NSEvent *) event;
- (uint32_t) dragSerialForEvent: (NSEvent *) event;
- (void) consumeDragPress;
- (void) flush;
// The shared color manager, or nil when the compositor offers neither protocol.
- (WaylandColorManager *) colorManager;
// The render-protocol manager used to attach buffers and queue frames: CoreGraphics' one, so that a
// surface has one set of syncobj and fifo objects whichever framework presents on it.
- (WaylandRenderManager *) renderManager;
// Called when one of the render globals arrives, so surfaces made earlier can observe it.
- (void) renderGlobalsAvailable;
// Start a window-system session before any restored window is mapped. These implement the
// NSDisplay (NSSessionRestoration) hooks declared in NSWindow-Private.h.
- (void) beginWindowSessionWithReason: (NSUInteger) reason identifier: (NSString *) identifier;
- (NSString *) windowSessionIdentifier;
- (BOOL) supportsWindowSessions;
// Called by a WaylandWindow before the first commit of a toplevel surface.
- (void) joinSessionForToplevel: (WaylandWindow *) window;
// Gives every window the current application icon (see WaylandToplevelIcon.h).
- (void) updateWindowIcons;
// Tells a window that the dialog manager arrived after it was mapped.
- (void) dialogManagerAvailable;
// Tells windows that the toplevel tag manager arrived after their toplevels were created.
- (void) toplevelTagManagerAvailable;
// Tells mapped windows to create an inhibitor when the idle inhibit manager arrives.
- (void) idleInhibitManagerAvailable;
- (void) processPendingEvents;
- (int32_t) scaleForOutput: (struct wl_proxy *) output;
- (uint32_t) refreshForOutput: (struct wl_proxy *) output; // millihertz, 0 if unknown
- (WaylandWindow *) popupParentForWindow: (WaylandWindow *) window;
- (WaylandWindow *) popupParentForGenericPopup: (WaylandWindow *) window;
- (NSArray *) levelParentCandidatesForWindow: (WaylandWindow *) window;
- (uint32_t) popupGrabSerialForParent: (WaylandWindow *) parent;
- (struct wl_proxy *) seat;
// Fills `result` and `proxies` with up to `max` outputs in -screens order (the order of the displays): their
// logical sizes and whether they are in `entered` (NSValue pointers, as
// WaylandWindow keeps its entered outputs). Returns 0 until an output has
// reported a mode.
- (size_t) fullscreenOutputs: (WaylandFullscreenOutput *) result
                     proxies: (struct wl_proxy **) proxies
                         max: (size_t) max
                     entered: (NSSet *) entered;
// The frame of the screen that a fullscreen window of this logical size fills: the output the window has entered
// whose size it is (the only output of that size when it has entered none). NO when there is no such screen.
- (BOOL) fullscreenScreenFrameForSize: (NSSize) size entered: (NSSet *) entered frame: (NSRect *) frame;
- (void) unmapPopupsForParent: (WaylandWindow *) parent;
- (void) mapPopupsWaitingForParent;
- (void) cancelPopupMenus;

// Runs a block after libwayland has returned from dispatching events. Event
// handlers queue application-facing calls this way, so application code never
// runs (and exceptions never unwind) inside native libwayland frames.
- (void) performAfterDispatch: (void (^)(void)) block;
// Runs a block at the end of the current pass of the main run loop, whether or not events are dispatched
// before then.
- (void) performAfterRunLoopPass: (void (^)(void)) block;

- (void) windowCreated: (WaylandWindow *) window;
- (void) windowActivated: (WaylandWindow *) window;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) applicationFocusMayHaveLeft;
- (BOOL) mappingForActivation;
- (void) mapDeferredWindows;
- (void) windowDestroyed: (WaylandWindow *) window;

// Where the main menu is exported on the session bus, for the appmenu objects
// of the toplevels; nil while it is not exported.
- (NSString *) applicationMenuServiceName;
- (NSString *) applicationMenuObjectPath;

- (struct wl_proxy *) newFractionalScaleForSurface: (struct wl_proxy *) surface owner: (id<WaylandFractionalScaleOwner>) owner;
- (void) contentTypeManagerAvailable;
- (void) shortcutsInhibitManagerAvailable;
@end
