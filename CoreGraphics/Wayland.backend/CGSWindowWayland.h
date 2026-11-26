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
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
           arguments: (union wl_argument *) args;

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

- (void) surfaceDestroyed: (CGSSurfaceWayland *) surface;
// A wl_buffer of the window's contents was released (or not used any more) by the compositor.
- (void) bufferReleased: (struct wl_proxy *) buffer opcode: (uint32_t) opcode;
// A color global arrived after the window was made: create its per-surface objects now.
- (void) colorManagerAvailable;
// Where the window is, as far as the connection knows (the rect that was asked for).
- (CGPoint) frameOrigin;

@end

#endif
