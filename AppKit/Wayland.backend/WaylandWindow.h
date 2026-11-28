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

#import <CoreGraphics/CGWindowPrivate.h>
#import <IOSurface/IOSurfaceRef.h>
#import <Onyx2D/O2Geometry.h>
#include <wayland-util.h>

#import <CoreGraphics/CGSWindow.h>
#import "WaylandDisplay.h"
#import "WaylandFullscreen.h"

@class NSWindow, NSColorSpace, O2Context, WaylandSubWindow, NSCGSInputMethod;

struct WaylandBuffer {
    struct wl_proxy *buffer;
    void *data;         // wl_shm mapping; NULL for a dma-buf buffer
    size_t size;
    IOSurfaceRef surface; // retained while the buffer is attached
    int32_t width, height;
    uint32_t format;    // wl_shm format, used to reuse a matching buffer
    uint32_t drmFormat; // DRM format of a dma-buf attachment
    uint64_t modifier;
    BOOL busy; // attached and not yet released by the compositor
};

// The role (xdg-shell or layer-shell) a window's wl_surface was given.
typedef enum {
    WaylandSurfaceRoleNone,
    WaylandSurfaceRoleToplevel,
    WaylandSurfaceRolePopup,
    WaylandSurfaceRoleLayer,
} WaylandSurfaceRole;

// A top-level window: an xdg_toplevel whose content is Onyx2D's CPU rendering,
// copied into wl_shm buffers.
@interface WaylandWindow : CGWindow {
    NSWindow *_delegate;
    // The window system's window: it owns the wl_surface and the xdg-shell and layer-shell objects of the window (the
    // role), which it makes when the window is shown, and tells what the compositor says of them. _surface and the
    // other proxies below are its objects, which this window draws into and extends.
    CGSWindow *_cgsWindow;
    // The window's use of the window system's input method, which CoreGraphics runs (see NSCGSInputMethod).
    NSCGSInputMethod *_inputMethod;
    WaylandDisplay *_display;
    BOOL _invalidated;
    NSMutableArray *_subwindows; // nonretained pointers; children retain their parent
    int _level;
    NSUInteger _styleMask;
    CGSBackingStoreType _backingType; // stored, but ignored
    O2Context *_context;
    NSMutableDictionary *_deviceDictionary;
    // AppKit screen coordinates. The origin is only what AppKit asked for: the
    // compositor places the window and doesn't say where.
    O2Rect _frame;
    NSString *_title;
    CGPoint _lastMotionPos;
    BOOL _isOpaque;
    BOOL _hasShadow;

    struct wl_proxy *_surface;
    // The role of _surface (see -prepareSurfaceForRole:): a wl_surface keeps its role for life.
    WaylandSurfaceRole _surfaceRole;
    struct wl_proxy *_xdgSurface;
    struct wl_proxy *_toplevel;
    // The menu bar, when the compositor has wlr-layer-shell: it has this role instead of the xdg ones.
    struct wl_proxy *_layerSurface;
    // org_kde_plasma_surface of the toplevel while it is not an application window (see
    // -updateTaskbarPresence).
    struct wl_proxy *_plasmaSurface;
    struct wl_proxy *_popup;
    WaylandWindow *_popupParent;
    uint32_t _popupGrabSerial;
    uint32_t _repositionToken;
    int32_t _pendingPopupX, _pendingPopupY;
    struct wl_proxy *_frameCallback;
    // Per-surface color objects and the compositor session this toplevel belongs to.
    struct wl_proxy *_colorSurface, *_representationSurface, *_surfaceFeedback, *_toplevelSession;
    // The compositor's preferred content description, when the application has not chosen one.
    NSColorSpace *_preferredColorSpace;
    // xdg-dialog-v1: the dialog role of a sheet or modal panel, and its current modal hint.
    struct wl_proxy *_dialog;
    BOOL _dialogModal;
    // idle-inhibit-unstable-v1: held while this toplevel is mapped and visible.
    struct wl_proxy *_idleInhibitor;
    // wp_content_type_v1: fullscreen windows are games, a visible window while the process holds a
    // display sleep assertion is showing video, and every other window says none.
    struct wl_proxy *_contentType;
    uint32_t _contentTypeValue;
    // keyboard-shortcuts-inhibit-unstable-v1: fullscreen windows take the compositor's shortcuts.
    struct wl_proxy *_shortcutsInhibitor;
    NSString *_sessionName;
    BOOL _restoringSessionToplevel;
    // Once a surface has committed, a saved session state can no longer be restored on it.
    BOOL _surfaceCommitted;
    struct WaylandBuffer _buffers[2];
    int32_t _pendingWidth, _pendingHeight;
    BOOL _pendingActivated;
    BOOL _mapped;
    // The window has been ordered in, whether or not it is mapped (a window with alpha 0 is not).
    BOOL _shouldBeMapped;
    BOOL _fullyTransparent;
    // Ordered in by an application that may not take the input focus, so not mapped yet (see
    // -mapWouldTakeFocusFromOthers).
    BOOL _mapDeferred;
    // The window was ordered out and is still mapped: the unmap waits for the end of the run loop pass, in
    // case the window is ordered in again within it (see -hideWindow).
    BOOL _unmapPending;
    // A menu is ordered in but waits for its parent window's first configure: a popup cannot be
    // created for a surface that has no role and configuration yet, and as a toplevel the
    // compositor would place and size it.
    BOOL _popupWaitingForParent;
    BOOL _genericPopup; // an xdg_popup for a pop-up window that is not a menu or tool tip (see DarlingWindowPresentation.h)
    // -makeKey was called and the activation it asks for has not arrived yet.
    BOOL _keyRequested;
    // The activation is being reported to the NSWindow; its -becomeKeyWindow asks -makeKey, which is no new request.
    BOOL _reportingActivation;
    BOOL _configured;
    BOOL _toplevelIconSet; // the compositor was given an icon for the toplevel
    BOOL _needsPresent;
    BOOL _activated;
    NSMutableSet *_surfaceOutputs;
    int32_t _bufferScale; // Integer output fallback, not fractional wire scale.
    uint32_t _preferredScale120, _renderScale120;
    struct wl_proxy *_fractionalScale, *_viewport;
    BOOL _scaleUpdatePending, _subwindowRedrawPending, _subwindowRedrawNeeded;
    BOOL _clientDecorated, _pendingClientDecorated, _decorationForcedClient;
    int _titlebarKind; // the CGSToplevelTitlebarKind NSWindow asked for
    BOOL _maximized, _pendingMaximized;
    // What the configure being applied said of fullscreen, what the last one applied said (told to the delegate), and the
    // size to go back to. Asking the compositor for fullscreen, the wait for its answer and the state the compositor holds
    // are the window system window's (see -[CGSWindow setToplevelFullscreen:force:]).
    BOOL _pendingFullscreen, _fullscreenRecheckPending;
    BOOL _fullscreenReported;
    WaylandFullscreenTracker _fullscreenTracker;
    BOOL _configureUpdatePending;
    NSUInteger _surfaceGeneration;
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;

- (O2Rect) frame;
- (O2Context *) cgContext;
- (struct wl_proxy *) surface;
- (struct wl_proxy *) toplevel;
- (struct wl_proxy *) ensureSurface;
- (WaylandDisplay *) waylandDisplay;
- (void) addSubwindow: (WaylandSubWindow *) child;
- (void) removeSubwindow: (WaylandSubWindow *) child;
- (void) updateSubwindows;
- (void) scheduleSubwindowRedraw;
- (void) stackSubwindows;
- (BOOL) isInvalidated;
- (BOOL) isMapped;
- (BOOL) isFullyTransparent;
// Tells the window system window whether the window is ordered in without being mapped (see -isOrderedIn).
- (void) syncHeldBack;
- (void) activatedInWindowSystem;
- (BOOL) isOrderedIn;
- (void) keyboardFocusLeft;
- (BOOL) isActivatedByCompositor;
- (BOOL) isMapDeferred;
- (BOOL) takeKeyRequest;
- (void) reportActivationDisplayingIfNeeded: (BOOL) displayIfNeeded;
- (int32_t) bufferScale;
- (uint32_t) renderScale120;
- (uint32_t) refreshMillihertz;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (void) outputRemoved: (struct wl_proxy *) output;
- (void) scheduleScaleUpdate;
// An output was added, removed or changed mode: re-decide fullscreen once the
// events of the batch (including a configure for the new size) are in.
- (void) outputsChanged;
- (BOOL) isPopup;
- (struct wl_proxy *) layerSurface;
- (BOOL) isPopupWaitingForParent;
- (void) ensureMapped;
// A tool tip window: placed as an ungrabbed popup next to the pointer.
- (BOOL) isTooltip;
// A pop-up window of the application (a drop-down a toolkit draws, a custom tool tip), shown as an
// ungrabbed popup of its parent window; it is not part of menu tracking.
- (BOOL) isGenericPopup;
- (WaylandWindow *) popupParent;
- (void) updateLevelParent;
- (uint32_t) popupGrabSerial;
- (struct wl_proxy *) xdgSurface;
- (void) unmap;
// Tells the compositor where the application's main menu is (KDE's appmenu
// protocol), or takes the address back when there is no menu or no toplevel.
- (void) updateApplicationMenu;
- (NSPoint) contentOffset;
// The first responder or the caret changed: the input method is told whether the window takes text and where.
- (void) updateInputMethodSpot;
- (BOOL) isDecorationPoint: (CGPoint) point;
// Tells the window system's window where the client-side frame's edges, title bar and buttons are.
- (void) updateClientDecorationLayout;

// Converts a surface-local point (origin top left) to window coordinates.
- (NSPoint) transformPoint: (CGPoint) surfacePoint;
- (void) setLastKnownCursorPosition: (CGPoint) point;

// What the window system window says of the window (see CGSToplevelEvent).
- (void) toplevelEvent: (const CGSToplevelEvent *) event;
- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;

// Gives the toplevel the application icon (xdg-toplevel-icon), when the compositor has the protocol.
- (void) updateToplevelIcon;

// The color space of the window's content, or sRGB when neither the window nor a screen reports one.
- (NSColorSpace *) contentColorSpace;
// Describes the surface's content color to the compositor, when it supports color management.
- (void) updateSurfaceColor;
// Creates the color objects once a surface exists and the manager has been bound.
- (void) updateSurfaceColorIfNeeded;
// Adds the toplevel to the compositor session, or restores its saved state. Must run before the
// surface's first commit. Does nothing without a session.
- (void) joinSessionBeforeCommit;
// Callbacks from the display when the color manager or session manager arrives later than the window.
- (void) colorManagerAvailable;
- (void) preferredColorInfoChanged;
// Routes a preferred-description change to a subwindow or one of its Metal surfaces.
- (BOOL) preferredSubwindowColorInfoChangedForFeedback: (struct wl_proxy *) feedback;
// A dma-buf, syncobj or fifo global arrived after this surface was made.
- (void) renderGlobalsAvailable;
- (void) sessionManagerAvailable;
// Called when the dialog manager arrives later than the window.
- (void) dialogManagerAvailable;
// Sends the toplevel's stable tag and localized description when xdg-toplevel-tag-v1 is available.
- (void) updateToplevelTags;
// Creates or destroys the idle inhibitor as this toplevel becomes visible or occluded.
- (void) updateIdleInhibitor;
// Tells the compositor what the surface shows when wp_content_type_v1 is available.
- (void) updateContentType;
// Takes or drops the compositor's keyboard shortcuts when the toplevel is fullscreen.
- (void) updateShortcutsInhibitor;

// Overrides of CGWindow's window-system session hooks (see CGWindowPrivate.h).
- (NSString *) ensureSessionToplevelName;
- (void) setSessionToplevelName: (NSString *) name restoring: (BOOL) restoring;
- (BOOL) isRestoringSessionToplevel;
- (BOOL) hasCommittedSurface;
// Commits the surface and records that a session restore request is now too late.
- (void) commitSurface;
- (struct wl_proxy *) surfaceFeedback;
- (struct wl_proxy *) toplevelSession;
- (void) setToplevelSession: (struct wl_proxy *) proxy;

@end
