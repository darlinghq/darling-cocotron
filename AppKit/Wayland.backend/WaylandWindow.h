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
#import <Onyx2D/O2Geometry.h>
#include <wayland-util.h>

#import "WaylandDisplay.h"
#import "WaylandFullscreen.h"

@class NSWindow, O2Context, WaylandSubWindow;

struct WaylandBuffer {
    struct wl_proxy *buffer;
    void *data;
    size_t size;
    int32_t width, height;
    uint32_t format;
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
    // org_kde_kwin_appmenu of the toplevel, while the main menu is exported.
    struct wl_proxy *_appMenu;
    // org_kde_plasma_surface of the toplevel while it is not an application window (see
    // -updateTaskbarPresence).
    struct wl_proxy *_plasmaSurface;
    struct wl_proxy *_popup;
    WaylandWindow *_popupParent;
    uint32_t _popupGrabSerial;
    uint32_t _repositionToken;
    int32_t _pendingPopupX, _pendingPopupY;
    struct wl_proxy *_decoration;
    struct wl_proxy *_frameCallback;
    struct WaylandBuffer _buffers[2];
    int32_t _pendingWidth, _pendingHeight;
    BOOL _pendingActivated;
    // The compositor's xdg_toplevel suspended state (version 6): the surface is not being repainted,
    // for instance because it is covered or its workspace is not shown.
    BOOL _pendingSuspended, _suspended;
    BOOL _mapped;
    // The window was sent -miniaturize (xdg_toplevel.set_minimized) and has not been shown again
    // since; xdg-shell cannot tell a client whether a toplevel is minimized (see -miniaturize).
    BOOL _minimized;
    // Whether the compositor advertised that it minimizes toplevels (xdg_toplevel wm_capabilities,
    // version 5): one that did not ignores set_minimized. The event applies with the configure that
    // follows it.
    BOOL _minimizeAdvertised, _pendingMinimizeAdvertised;
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
    BOOL _maximized, _pendingMaximized;
    // Whether the current xdg_toplevel was asked for fullscreen, what the last
    // configure said, and the size to go back to.
    BOOL _fullscreenRequested, _pendingFullscreen, _fullscreenRecheckPending;
    BOOL _fullscreenReported; // what the last configure said, told to the delegate
    BOOL _fullscreenSettling; // a fullscreen change was requested and not yet answered
    NSUInteger _fullscreenSettleToken;
    WaylandFullscreenTracker _fullscreenTracker;
    // The window this one is transient for because of its level, if any (not retained: the
    // display clears it when that window goes away).
    WaylandWindow *_levelParent;
    BOOL _configureUpdatePending;
    NSUInteger _surfaceGeneration;
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;

- (O2Rect) frame;
- (O2Context *) cgContext;
- (struct wl_proxy *) surface;
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
- (WaylandWindow *) levelParent;
- (void) updateLevelParent;
- (void) levelParentUnmapped;
- (uint32_t) popupGrabSerial;
- (struct wl_proxy *) xdgSurface;
- (void) unmap;
// Tells the compositor where the application's main menu is (KDE's appmenu
// protocol), or takes the address back when there is no menu or no toplevel.
- (void) updateApplicationMenu;
- (NSPoint) contentOffset;
- (BOOL) isDecorationPoint: (CGPoint) point;
- (BOOL) decorationButton: (uint32_t) button pressed: (BOOL) pressed
                   serial: (uint32_t) serial atPoint: (CGPoint) point;

// Converts a surface-local point (origin top left) to window coordinates.
- (NSPoint) transformPoint: (CGPoint) surfacePoint;
- (void) setLastKnownCursorPosition: (CGPoint) point;

- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;

// Gives the toplevel the application icon (xdg-toplevel-icon), when the compositor has the protocol.
- (void) updateToplevelIcon;

@end
