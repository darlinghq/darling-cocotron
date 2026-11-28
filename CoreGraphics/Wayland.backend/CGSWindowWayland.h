/* CoreGraphics Wayland backend: a window-server window.

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

// A window on its own wl_surface. What role the surface gets follows what the window is, which
// the window level and the style bits say (the same reduction AppKit's Wayland backend makes of
// NSWindow levels, see AppKit/DarlingWindowLevelPolicy.h):
//  - a window at the main menu level (the menu bar) is a layer-shell surface along the top of the
//    output that keeps that strip free, when the compositor has wlr-layer-shell;
//  - a window above the main menu level (menus, pop-up windows) is an xdg_popup of the menu bar
//    when that is shown, else of the window the user works in, placed at the position it asked for;
//  - every other window is an xdg_toplevel; one above the normal level or with the floating style
//    (floating palettes, utility and modal windows) is made a child of the window the user works
//    in, which keeps it in front of that window, and is where the window asked to be when the
//    compositor lets a client say so (KDE's plasma shell). The compositor frames the windows
//    that have a frame (xdg-decoration).
// The role of a surface cannot change, so it is made when the window is first used (shown or given
// a surface), from the level and the style set by then.
//
// An xdg_toplevel on its own wl_surface. The window carries no pixels itself:
// content arrives through its CGSSurface, which wraps the same wl_surface in a
// wl_egl_window so that CGL can render and swap into it. A Wayland toplevel is
// mapped by its first committed buffer, so the window becomes visible when the
// first swap happens, not when it is created or ordered in.

#ifndef CGSWINDOWWAYLAND_H
#define CGSWINDOWWAYLAND_H

#import <CoreGraphics/CGSWindow.h>
#import "CGSConnectionWayland.h"

@class CGSSurfaceWayland, WaylandColorManager;

typedef enum {
    CGSWaylandRoleNone = 0, // not made yet
    CGSWaylandRoleToplevel,
    CGSWaylandRoleLayer,
    CGSWaylandRolePopup,
} CGSWaylandRole;

@interface CGSWindowWayland : CGSWindow {
@public
    CGSConnectionWayland *_waylandConnection; // Not retained; it owns us.
    struct wl_proxy *_surface;

@protected
    struct wl_proxy *_xdgSurface;
    struct wl_proxy *_toplevel;
    struct wl_proxy *_layerSurface;
    struct wl_proxy *_popup;
    struct wl_proxy *_decoration;
    struct wl_proxy *_plasmaSurface;
    CGSWaylandRole _role;
    // The window a popup belongs to (retained: the compositor needs it to outlive the popup).
    CGSWindowWayland *_popupParent;
    // The window a floating window is a child of (not retained, see -updateLevelParent).
    CGSWindowWayland *_levelParent;
    BOOL _shown; // ordered in and not ordered out since
    // While the window is being unmapped the configures that arrive include ones the compositor sent
    // before it saw the unmapping, and acknowledging those is a protocol error: only the last one, the
    // answer to the empty commit, is acknowledged, when the unmapping is over.
    BOOL _unmapping;
    // The toplevel was unmapped by ordering it out; the compositor forgets its title, size limits and parent then.
    BOOL _unmappedToplevel;
    BOOL _hasPendingConfigure;
    uint32_t _pendingConfigureSerial;
    // Per-surface color objects, when the compositor offers the protocols.
    struct wl_proxy *_colorSurface, *_representationSurface;
    // The rect the caller asked for. Wayland never reports where the compositor
    // put a toplevel, so the origin stays the requested one; the size follows
    // the compositor's configure once it sends a non-zero one.
    CGRect _frame;
    NSString *_title;
    CGSSurfaceWayland *_surfaceObject; // Not retained; held by _surfaces.
    BOOL _activated;
    BOOL _usesContents; // a program draws into the window with -drawImage:atPoint: (it set a style)
    BOOL _displayOverlay; // -becomeDisplayOverlay: made this window the cover of a display

    // A toplevel window of the UI layer (see CGSWindow.h, -[CGSConnection newToplevelWindowWithAttributes:]): the
    // UI layer says what the window is and when it is shown, the window system's objects follow. The role is made
    // when the window is shown, from the hints, and is destroyed when the window is hidden.
    BOOL _ui;
    CGRect _uiFrame; // in the space of -setToplevelFrame:
    CGSToplevelHints _uiHints;
    CGSize _uiMinimumSize, _uiMaximumSize;
    BOOL _uiLimitsSet;
    // Who draws the window's frame, as asked: 0 not asked, 1 the compositor, 2 the client, 3 asked to leave it open.
    int _uiDecorationRequest;
    // What the compositor said about the frame, once it said.
    BOOL _uiDecorationReported, _uiClientDecorated;
    // The window's frame drawn by the UI layer inside the surface: where the content starts, in points from the top left
    // corner of the surface.
    CGPoint _uiContentOffset;
    // The address of the window's application menu (see -setToplevelApplicationMenuServiceName:objectPath:) and the
    // org_kde_kwin_appmenu object that tells the compositor, while the window is a toplevel and there is a manager.
    NSString *_uiMenuService, *_uiMenuPath;
    struct wl_proxy *_uiAppMenu;
    // What the window shows of a title bar and who draws the frame (see -setToplevelTitlebarKind:), and the frame the
    // UI layer draws inside the surface (see -setToplevelClientDecorationLayout:).
    CGSToplevelTitlebarKind _uiTitlebarKind;
    BOOL _uiPrefersClientDecoration;
    BOOL _uiHasDecorationLayout;
    CGSToplevelDecorationLayout _uiDecorationLayout;
    uint32_t _uiPopupGrabSerial;
    uint32_t _uiRepositionToken;
    // What the events of the configure sequence in progress said.
    CGSToplevelConfigure _uiPending;
    BOOL _uiMinimizeAdvertised;
    BOOL _uiIgnoresMouse;
    // The compositor's first configure of the role was acknowledged: content may be attached.
    BOOL _uiConfigured;
    // alpha-modifier-v1's object for the surface, and the opacity the UI layer asked for.
    struct wl_proxy *_alphaModifier;
    CGFloat _uiAlpha;
    BOOL _uiAlphaSet;

    // Relation, order, focus, minimizing and fullscreen of the window (see CGSWindow.h). What the compositor said of the
    // window is kept as of the configure that said it; what the UI layer asked for is kept as asked.
    int _uiLevel;
    BOOL _uiStacksByLevel;
    // Ordered in by the UI layer but kept from the compositor (see -setToplevelHeldBack:).
    BOOL _uiHeldBack;
    // The order the process knows of its windows: the window activated or ordered to the front last comes first, the
    // others follow in the order they were made (see -[CGSConnectionWayland orderedToplevelWindowIDs]).
    uint64_t _orderStamp, _creationStamp;
    BOOL _uiActivated, _uiSuspended;
    BOOL _uiMinimized;
    // Fullscreen: what was asked for, what the compositor said, and whether a change waits for its answer.
    BOOL _uiFullscreenRequested, _uiFullscreen, _uiFullscreenSettling;
    NSUInteger _uiSettleToken;
}

- (instancetype) initToplevelWithAttributes: (const CGSToplevelAttributes *) attributes
                                 connection: (CGSConnection *) connection
                                   windowID: (CGSWindowID) windowID;

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
           arguments: (union wl_argument *) args;

// The order of the window among the process' windows (see the connection's -orderedToplevelWindowIDs): larger is further
// in front. A window that was never ordered or activated is behind those that were, the older window in front.
- (uint64_t) orderRank;
// Whether the UI layer ordered the window in: shown, or held back from the compositor.
- (BOOL) isOrderedIn;
// Whether the window is a toplevel window of the UI layer (see CGSWindow.h).
- (BOOL) isUIToplevel;
// The window was asked to be activated through xdg-activation and the compositor did not minimize it any more (see
// -[CGSConnectionWayland requestActivationOfWindow:from:]).
- (BOOL) isMinimizedByRequest;
// Whether the compositor minimizes toplevels when asked (see -miniaturizeToplevel).
- (BOOL) compositorMinimizes;
// A toplevel of this connection was hidden: windows that were related to it lose the relation, as the compositor
// drops it.
- (void) relatedToplevelHidden: (CGSWindowWayland *) hidden;
// Asks the compositor to fullscreen the window on an output (a wl_output, NULL: its choice) or to leave fullscreen. The
// UI layer chooses the output, as it knows what the window's surface entered (see -setToplevelFullscreen:force:, which lets
// the compositor choose).
- (CGError) setToplevelFullscreen: (BOOL) fullscreen onOutput: (struct wl_proxy *) output force: (BOOL) force;

// The role the window has, CGSWaylandRoleNone before it is first used.
- (CGSWaylandRole) role;
- (BOOL) isShown;
- (BOOL) isActivated;
// Whether the window is a display overlay (see -becomeDisplayOverlay:). Its input is the process' own but
// belongs to no window of the application: its events name no window.
- (BOOL) isDisplayOverlay;
// Whether the window is one that other windows stay in front of: not floating, not a popup.
- (BOOL) isDocumentLike;
// Makes a floating window a child of the current document window when it has none.
- (void) updateLevelParent;
- (void) mapFloatingWindowsAgain: (NSArray *) windows;
- (void) restoreToplevelState;

- (void) surfaceDestroyed: (CGSSurfaceWayland *) surface;
// A wl_buffer of the window's contents was released (or not used any more) by the compositor.
- (void) bufferReleased: (struct wl_proxy *) buffer opcode: (uint32_t) opcode;
// A color global arrived after the window was made: create its per-surface objects now.
- (void) colorManagerAvailable;
- (void) renderManagerAvailable;
// Where the window is, as far as the connection knows (the rect that was asked for).
- (CGPoint) frameOrigin;
// Where the window's content starts in the surface, when the UI layer draws the window's frame inside it (see
// -setToplevelContentOffset:).
- (CGPoint) toplevelContentOffset;
// Whether the point of the surface (in points from its top left corner) is in the window's content and not in the frame
// the UI layer draws around it.
- (BOOL) toplevelContentContainsSurfacePoint: (CGPoint) point;

// The window's objects of the window system, for the UI layer that owns the window's content and what the protocol
// has beyond CGSWindow.h (the toplevel's fullscreen, parent and move requests, the objects that must be made
// before the first commit); NULL while the window is not shown or has not that role. They are valid until the window is
// ordered out, and are the UI layer's to use, not to destroy.
- (struct wl_proxy *) xdgSurfaceProxy;
- (struct wl_proxy *) toplevelProxy;
- (struct wl_proxy *) popupProxy;
- (struct wl_proxy *) layerSurfaceProxy;
// The pop-up grab: the serial of the input event that entitles the pop-up to a grab, set before the window is shown (0:
// no grab).
- (void) setToplevelPopupGrabSerial: (uint32_t) serial;
// Where the window's content starts inside its surface when the UI layer draws a frame of its own, in points from the
// top left corner: pop-ups of the window are placed relative to the content.
- (void) setToplevelContentOffset: (CGPoint) offset;
// Tells the compositor where the window's application menu is, or that there is none (the appmenu manager came or went).
- (void) applyApplicationMenu;
// Replaces CGSWindow's -setToplevelFrame: for a frame the window system itself reported (the UI layer's window
// follows it): remembers it without asking the window system for it.
- (void) noteToplevelFrame: (CGRect) frame;
// Tells the window system that the frame is not decided by the UI layer (the compositor's choice: used when the
// window has no title bar).
- (void) unsetToplevelDecoration;
// A pointer button was pressed or released over the window's surface at a point of it (points from its top left corner):
// whether it is the frame's (see -setToplevelClientDecorationLayout:), which then acts on a press of the left button with
// the compositor's serial (resize, move, close, miniaturize, zoom) and takes the button.
- (BOOL) handleToplevelDecorationButton: (uint32_t) button pressed: (BOOL) pressed serial: (uint32_t) serial atPoint: (CGPoint) point;
// The alpha-modifier global arrived after the window was made: the window's opacity is told now.
- (void) alphaModifierAvailable;
// The opacity the window lists in CGWindowListCopyWindowInfo().
- (CGFloat) listedAlpha;

@end

#endif
