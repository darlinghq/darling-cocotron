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

#import "CGSWindowWayland.h"
#import "CGSSurfaceWayland.h"
#import "WaylandColor.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import "WaylandRender.h"
#import "WaylandToplevelRequests.h"

#import <CoreGraphics/CGSSurface.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#import <sys/mman.h>
#include <unistd.h>
#include <string.h>

static void destroyProxy(struct wl_proxy **proxy, uint32_t opcode);

// Numbers the windows' places in the order the process knows of them (see -orderRank).
static uint64_t sOrderCounter;

@implementation CGSWindowWayland

- (instancetype) initWithRegion: (CGSRegionRef) region
                     connection: (CGSConnection *) connection
                       windowID: (CGSWindowID) windowID
{
    self = [super initWithRegion: region connection: connection windowID: windowID];
    if (self == nil)
        return nil;

    _waylandConnection = (CGSConnectionWayland *) connection;
    _creationStamp = ++sOrderCounter;
    _frame = CGRectMake(0, 0, 1, 1);
    if (region != NULL)
        CGSRegionToRect(region, &_frame);
    if (!(_frame.size.width >= 1) || !(_frame.size.height >= 1)) {
        NSLog(@"CoreGraphics Wayland backend: refusing a %g x %g window",
              _frame.size.width, _frame.size.height);
        [self release];
        return nil;
    }

    union wl_argument args[2] = {{.o = NULL}};
    _surface = [_waylandConnection createObject: _waylandConnection->_compositor
                                         opcode: WP_COMPOSITOR_CREATE_SURFACE
                                      interface: &wl_surface_interface
                                      arguments: args
                                           kind: CGSWaylandObjectNone
                                         object: nil];
    if (_surface == NULL) {
        [self release];
        return nil;
    }
    [[_waylandConnection renderManager] observeSurface: _surface];

    // The role (and with it the initial commit) is made by -ensureRole once the level and style
    // are known.
    return self;
}

- (void) colorManagerAvailable {
    if (_surface == NULL)
        return;
    WaylandColorManager *color = [_waylandConnection colorManager];
    if (_colorSurface == NULL) {
        _colorSurface = [color newColorSurfaceForSurface: _surface];
        if (_colorSurface != NULL) {
            // Direct CoreGraphics windows draw sRGB content; AppKit windows describe their
            // -colorSpace themselves through the native window.
            CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            if (srgb != NULL) {
                [color setColorSpace: srgb onSurface: _colorSurface];
                CGColorSpaceRelease(srgb);
            }
        }
    }
    if (_representationSurface == NULL)
        _representationSurface = [color newRepresentationSurfaceForSurface: _surface];
}

- (void) renderManagerAvailable {
    if (_surface != NULL)
        [[_waylandConnection renderManager] observeSurface: _surface];
}

- (CGPoint) toplevelContentOffset {
    return _uiContentOffset;
}

// The window's input method state is what the connection's text input sends to the compositor while this window has
// the text input focus (see CGSInputMethod.h).
- (void) inputMethodEnabledChanged {
    [_waylandConnection inputMethodWindowChanged: self];
}

- (void) inputMethodCursorRectChanged {
    [_waylandConnection inputMethodWindowChanged: self];
}

- (void) inputMethodSurroundingTextChanged {
    [_waylandConnection inputMethodWindowChanged: self];
}

- (void) inputMethodContentTypeChanged {
    [_waylandConnection inputMethodWindowChanged: self];
}

- (void) dealloc {
    [_waylandConnection inputMethodWindowDestroyed: [self windowId]];
    // The surface's wl_egl_window references our wl_surface, so it has to go
    // first; -[CGSWindow dealloc] would only release _surfaces after this body.
    @synchronized (_surfaces) {
        [_surfaces removeAllObjects];
    }
    _surfaceObject = nil;

    [_title release];
    [_uiMenuService release];
    [_uiMenuPath release];
    WaylandColorManager *color = [_waylandConnection colorManager];
    [color destroyColorSurface: _colorSurface];
    [color destroyRepresentationSurface: _representationSurface];
    _colorSurface = NULL;
    _representationSurface = NULL;
    [self destroyRole];
    destroyProxy(&_alphaModifier, WP_ALPHA_MODIFIER_SURFACE_DESTROY);
    [[_waylandConnection renderManager] destroySurface: _surface];
    if (_surface != NULL)
        WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    [_waylandConnection flush];
    if (_displayOverlay)
        [_waylandConnection pointerLockTargetMayHaveChanged];
    [super dealloc];
}

#pragma mark - Role

static void destroyProxy(struct wl_proxy **proxy, uint32_t opcode) {
    if (*proxy == NULL)
        return;
    WaylandMarshal(*proxy, opcode, NULL, WL_MARSHAL_FLAG_DESTROY, (union wl_argument[1]) {{.o = NULL}});
    *proxy = NULL;
}

- (CGSWaylandRole) role { return _role; }
- (BOOL) isShown { return _shown; }
- (BOOL) isActivated { return _activated; }
- (BOOL) isDisplayOverlay { return _displayOverlay; }

// Whether the window floats: above the normal level (and below the main menu) or with the floating
// style. See the comment in CGSWindowWayland.h.
- (BOOL) isFloating {
    return (_styleFlags & kCGSWindowStyleFloating) != 0 ||
           (_level > kCGNormalWindowLevel && _level < kCGMainMenuWindowLevel);
}

- (BOOL) isDocumentLike {
    return _role == CGSWaylandRoleToplevel && ![self isFloating];
}

// The window a floating window or a popup belongs to: for a popup the menu bar when it is shown,
// else the window the user works in; for a floating window that window only. nil for none.
- (CGSWindowWayland *) windowToAttachTo: (BOOL) allowBar {
    CGSWindowWayland *bar = nil, *active = nil, *any = nil;
    NSArray *windows = [_waylandConnection copyAllWindows];
    for (CGSWindow *candidate in windows) {
        CGSWindowWayland *window = (CGSWindowWayland *) candidate;
        if (window == self || !window->_shown || window->_role == CGSWaylandRoleNone ||
            window->_role == CGSWaylandRolePopup)
            continue;
        if (window->_role == CGSWaylandRoleLayer) {
            bar = window;
        } else if (![window isFloating]) {
            if (window->_activated)
                active = window;
            any = window;
        }
    }
    CGSWindowWayland *result = (allowBar && bar != nil) ? bar : active != nil ? active : any;
    [result retain];
    [windows release];
    return [result autorelease];
}

- (CGSWaylandRole) wantedRole {
    if (_level == kCGMainMenuWindowLevel && _waylandConnection->_layerShell != NULL)
        return CGSWaylandRoleLayer;
    if (_level > kCGMainMenuWindowLevel && [self windowToAttachTo: YES] != nil)
        return CGSWaylandRolePopup;
    return CGSWaylandRoleToplevel;
}

- (void) createToplevelRole {
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
    _xdgSurface = [_waylandConnection createObject: _waylandConnection->_wmBase
                                            opcode: WP_WM_BASE_GET_XDG_SURFACE
                                         interface: &xdg_surface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectXdgSurface
                                            object: self];
    if (_xdgSurface == NULL)
        return;
    args[0].o = NULL;
    _toplevel = [_waylandConnection createObject: _xdgSurface
                                          opcode: WP_XDG_SURFACE_GET_TOPLEVEL
                                       interface: &xdg_toplevel_interface
                                       arguments: args
                                            kind: CGSWaylandObjectToplevel
                                          object: self];
    if (_toplevel == NULL)
        return;
    _role = CGSWaylandRoleToplevel;
    if (_title != nil) {
        union wl_argument title[1] = {{.s = [_title UTF8String]}};
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, title);
    }
    [self applyToplevelStyle: ~0u];
    [self updatePlasmaSurface];
}

// The menu bar: a strip along the top of the output as wide as the output and as high as the window,
// which other windows keep clear of.
- (void) createLayerRole {
    int32_t height = MAX(1, (int32_t) ceil(_frame.size.height));
    union wl_argument args[5] = {{.o = NULL}, {.o = (struct wl_object *) _surface}, {.o = NULL},
                                 {.u = WP_LAYER_TOP}, {.s = "menubar"}};
    _layerSurface = [_waylandConnection createObject: _waylandConnection->_layerShell
                                              opcode: WP_LAYER_SHELL_GET_LAYER_SURFACE
                                           interface: &zwlr_layer_surface_v1_interface
                                           arguments: args
                                                kind: CGSWaylandObjectLayerSurface
                                              object: self];
    if (_layerSurface == NULL)
        return;
    _role = CGSWaylandRoleLayer;
    union wl_argument anchor[1] = {{.u = WP_LAYER_ANCHOR_TOP | WP_LAYER_ANCHOR_LEFT | WP_LAYER_ANCHOR_RIGHT}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_ANCHOR, NULL, 0, anchor);
    union wl_argument size[2] = {{.u = 0}, {.u = (uint32_t) height}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_SIZE, NULL, 0, size);
    union wl_argument zone[1] = {{.i = height}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_EXCLUSIVE_ZONE, NULL, 0, zone);
    // The bar takes no keyboard focus (the protocol default): the menus it opens are tracked with the
    // application's own input.
}

// A pop-up window: placed where it asked to be, relative to the window it belongs to, which is the
// layer surface of the menu bar or an xdg surface. Not grabbed: the application orders it out itself.
- (void) createPopupRole: (CGSWindowWayland *) parent {
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *positioner = [_waylandConnection createObject: _waylandConnection->_wmBase
                                                            opcode: WP_WM_BASE_CREATE_POSITIONER
                                                         interface: &xdg_positioner_interface
                                                         arguments: args
                                                              kind: CGSWaylandObjectNone
                                                            object: nil];
    if (positioner == NULL)
        return;
    args[0].i = MAX(1, (int32_t) ceil(_frame.size.width));
    args[1].i = MAX(1, (int32_t) ceil(_frame.size.height));
    WaylandMarshal(positioner, WP_POSITIONER_SET_SIZE, NULL, 0, args);
    CGRect parentFrame = parent->_frame;
    int32_t x = (int32_t) floor(_frame.origin.x - parentFrame.origin.x);
    int32_t y = (int32_t) floor(_frame.origin.y - parentFrame.origin.y);
    // The anchor has to be inside the parent's geometry; what lies beyond it is an offset.
    int32_t anchorX = MAX(0, MIN(x, (int32_t) ceil(parentFrame.size.width) - 1));
    int32_t anchorY = MAX(0, MIN(y, (int32_t) ceil(parentFrame.size.height) - 1));
    args[0].i = anchorX;
    args[1].i = anchorY;
    args[2].i = args[3].i = 1;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR_RECT, NULL, 0, args);
    args[0].i = x - anchorX;
    args[1].i = y - anchorY;
    WaylandMarshal(positioner, WP_POSITIONER_SET_OFFSET, NULL, 0, args);
    args[0].u = WP_POSITIONER_ANCHOR_TOP_LEFT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR, NULL, 0, args);
    args[0].u = WP_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_GRAVITY, NULL, 0, args);
    args[0].u = WP_POSITIONER_SLIDE_X | WP_POSITIONER_SLIDE_Y | WP_POSITIONER_FLIP_X | WP_POSITIONER_FLIP_Y;
    WaylandMarshal(positioner, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, NULL, 0, args);

    args[0].o = NULL;
    args[1].o = (struct wl_object *) _surface;
    _xdgSurface = [_waylandConnection createObject: _waylandConnection->_wmBase
                                            opcode: WP_WM_BASE_GET_XDG_SURFACE
                                         interface: &xdg_surface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectXdgSurface
                                            object: self];
    if (_xdgSurface != NULL) {
        BOOL layerParent = parent->_layerSurface != NULL;
        args[0].o = NULL;
        args[1].o = layerParent ? NULL : (struct wl_object *) parent->_xdgSurface;
        args[2].o = (struct wl_object *) positioner;
        _popup = [_waylandConnection createObject: _xdgSurface
                                           opcode: WP_XDG_SURFACE_GET_POPUP
                                        interface: &xdg_popup_interface
                                        arguments: args
                                             kind: CGSWaylandObjectPopup
                                           object: self];
        if (_popup != NULL && layerParent) {
            // A popup of a layer surface has no xdg parent; the layer surface adopts it.
            args[0].o = (struct wl_object *) _popup;
            WaylandMarshal(parent->_layerSurface, WP_LAYER_SURFACE_GET_POPUP, NULL, 0, args);
        }
        if (_popup != NULL) {
            _popupParent = [parent retain];
            _role = CGSWaylandRolePopup;
        }
    }
    WaylandMarshal(positioner, WP_POSITIONER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                   (union wl_argument[1]) {{.o = NULL}});
}

// Makes the role of the window, once. The initial commit carries no buffer: the compositor answers
// with a configure, and the first buffer maps the window.
- (BOOL) ensureRole {
    @synchronized (self) {
        if (_role != CGSWaylandRoleNone)
            return YES;
        // The role of a window of the UI layer is made when the UI layer shows it.
        if (_ui)
            return NO;

        switch ([self wantedRole]) {
        case CGSWaylandRoleLayer:
            [self createLayerRole];
            break;
        case CGSWaylandRolePopup: {
            CGSWindowWayland *parent = [self windowToAttachTo: YES];
            if (parent != nil)
                [self createPopupRole: parent];
            break;
        }
        default:
            break;
        }
        if (_role == CGSWaylandRoleNone)
            [self createToplevelRole];
        if (_role == CGSWaylandRoleNone) {
            [self destroyRole];
            return NO;
        }

        [self colorManagerAvailable];

        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        if (WL.wl_display_roundtrip(_waylandConnection->_wlDisplay) < 0) {
            NSLog(@"CoreGraphics Wayland backend: the connection failed while "
                  @"creating a window (error %d)",
                  WL.wl_display_get_error(_waylandConnection->_wlDisplay));
            return NO;
        }
        if (_role == CGSWaylandRoleToplevel)
            [self updateLevelParent];
        return YES;
    }
}

- (void) destroyRole {
    destroyProxy(&_uiAppMenu, WP_APPMENU_RELEASE);
    destroyProxy(&_decoration, WP_TOPLEVEL_DECORATION_DESTROY);
    destroyProxy(&_plasmaSurface, WP_PLASMA_SURFACE_DESTROY);
    destroyProxy(&_toplevel, WP_TOPLEVEL_DESTROY);
    destroyProxy(&_popup, WP_POPUP_DESTROY);
    destroyProxy(&_layerSurface, WP_LAYER_SURFACE_DESTROY);
    destroyProxy(&_xdgSurface, WP_XDG_SURFACE_DESTROY);
    [_popupParent release];
    _popupParent = nil;
    _levelParent = nil;
    _role = CGSWaylandRoleNone;
}

// A floating window is a child of the window the user works in, so that the compositor keeps it in
// front of that window; any other window has no parent. The compositor drops the relation when the
// parent is unmapped, so it is made again whenever a window is shown.
- (void) updateLevelParent {
    // A toplevel window of the UI layer is related to the window the UI layer names (-setToplevelParent:).
    if (_ui || _toplevel == NULL)
        return;
    CGSWindowWayland *parent = [self isFloating] ? [self windowToAttachTo: NO] : nil;
    if (parent != nil && parent->_toplevel == NULL)
        parent = nil;
    if (parent == _levelParent)
        return;
    _levelParent = parent;
    union wl_argument args[1] = {{.o = (struct wl_object *) (parent != nil ? parent->_toplevel : NULL)}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_PARENT, NULL, 0, args);
    [_waylandConnection flush];
}

// A compositor that follows the xdg-shell rule that an unmapped toplevel goes back to its initial state
// (wlroots ones, sway) has forgotten the title, the size limits and the parent when the window is
// shown again: they are said again before its next buffer maps it.
- (void) restoreToplevelState {
    _unmappedToplevel = NO;
    if (_toplevel == NULL)
        return;
    if (_title != nil) {
        union wl_argument args[1] = {{.s = [_title UTF8String]}};
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
    }
    [self applyToplevelStyle: kCGSWindowStyleFixedSize];
    _levelParent = nil;
    [self updateLevelParent];
    [_waylandConnection flush];
}

// Compositors that stack toplevels in the order they were mapped (wlroots ones, sway) do not move a child
// that was mapped before its parent in front of it when it is given that parent. The floating windows
// that are shown when a document window is shown for the first time are therefore mapped again, after it,
// which is also what keeps them in front of a document window that is opened later. This is done only for
// windows whose pixels the backend keeps and can put on the screen again (what a program draws into
// a window), as a window that renders through a GL surface has nothing to show after it was unmapped.
- (void) mapFloatingWindowsAgain: (NSArray *) windows {
    for (CGSWindowWayland *window in windows) {
        if (window == self || window->_role != CGSWaylandRoleToplevel || !window->_shown ||
            ![window isFloating] || window->_levelParent != self)
            continue;
        if (![window withContents: ^(const void *bytes, size_t rowBytes, CGSize size) {}])
            continue;
        [window orderWindow: kCGSOrderOut relativeTo: nil];
        [window orderWindow: kCGSOrderIn relativeTo: nil];
    }
}

// Where the window asked to be, for a compositor whose plasma shell lets a client say so; the other
// compositors place a toplevel themselves. The window is also kept out of task lists when it is a
// utility window.
- (void) updatePlasmaSurface {
    if (_toplevel == NULL || _waylandConnection->_plasmaShell == NULL)
        return;
    if (_plasmaSurface == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _plasmaSurface = [_waylandConnection createObject: _waylandConnection->_plasmaShell
                                                   opcode: WP_PLASMA_SHELL_GET_SURFACE
                                                interface: &org_kde_plasma_surface_interface
                                                arguments: args
                                                     kind: CGSWaylandObjectNone
                                                   object: nil];
        if (_plasmaSurface == NULL)
            return;
    }
    union wl_argument position[2] = {{.i = (int32_t) lround(_frame.origin.x)}, {.i = (int32_t) lround(_frame.origin.y)}};
    WaylandMarshal(_plasmaSurface, WP_PLASMA_SURFACE_SET_POSITION, NULL, 0, position);
    union wl_argument skip[1] = {{.u = (_styleFlags & kCGSWindowStyleUtility) ? 1 : 0}};
    if (_waylandConnection->_plasmaShellVersion >= 2)
        WaylandMarshal(_plasmaSurface, WP_PLASMA_SURFACE_SET_SKIP_TASKBAR, NULL, 0, skip);
    if (_waylandConnection->_plasmaShellVersion >= 5)
        WaylandMarshal(_plasmaSurface, WP_PLASMA_SURFACE_SET_SKIP_SWITCHER, NULL, 0, skip);
}

// The toplevel's state that follows the style bits in `mask`.
- (void) applyToplevelStyle: (uint32_t) mask {
    if (_toplevel == NULL)
        return;

    if ((mask & kCGSWindowStyleFixedSize)) {
        union wl_argument size[2] = {{.i = 0}, {.i = 0}};
        if (_styleFlags & kCGSWindowStyleFixedSize) {
            size[0].i = (int32_t) _frame.size.width;
            size[1].i = (int32_t) _frame.size.height;
        }
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, size);
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, size);
    }

    if ((mask & (kCGSWindowStyleBorderless | kCGSWindowStyleUnmanaged)) && _waylandConnection->_decorationManager != NULL) {
        // A window with a frame has the compositor draw it; one without says so, as compositors differ
        // on what a window that says nothing gets.
        if (_decoration == NULL) {
            union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _toplevel}};
            _decoration = [_waylandConnection createObject: _waylandConnection->_decorationManager
                                                    opcode: WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION
                                                 interface: &zxdg_toplevel_decoration_v1_interface
                                                 arguments: args
                                                      kind: CGSWaylandObjectNone
                                                    object: nil];
        }
        if (_decoration != NULL) {
            BOOL framed = !(_styleFlags & (kCGSWindowStyleBorderless | kCGSWindowStyleUnmanaged));
            union wl_argument mode[1] = {{.u = framed ? WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE
                                                      : WP_TOPLEVEL_DECORATION_MODE_CLIENT_SIDE}};
            WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, mode);
        }
    }
}

- (void) surfaceDestroyed: (CGSSurfaceWayland *) surface {
    if (_surfaceObject == surface)
        _surfaceObject = nil;
}

#pragma mark - Events

// Acknowledges a configure of the xdg surface or the layer surface, now or, while the window is being
// unmapped, when that is over.
- (void) acknowledgeConfigure: (uint32_t) serial {
    if (_unmapping) {
        _pendingConfigureSerial = serial;
        _hasPendingConfigure = YES;
        return;
    }
    union wl_argument ack[1] = {{.u = serial}};
    if (_layerSurface != NULL)
        WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
    else if (_xdgSurface != NULL)
        WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
    [_waylandConnection flush];
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
           arguments: (union wl_argument *) args
{
    if (_ui) {
        [self handleToplevelEvent: opcode kind: kind arguments: args];
        return;
    }
    if (kind == CGSWaylandObjectXdgSurface) {
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE)
            [self acknowledgeConfigure: args[0].u];
        return;
    }

    if (kind == CGSWaylandObjectLayerSurface) {
        if (opcode == WP_LAYER_SURFACE_EV_CONFIGURE) {
            [self acknowledgeConfigure: args[0].u];
            // A zero extent leaves the size to the client, so the requested one stands.
            CGSize size = CGSizeMake(args[1].u != 0 ? args[1].u : _frame.size.width,
                                     args[2].u != 0 ? args[2].u : _frame.size.height);
            if (!CGSizeEqualToSize(size, _frame.size)) {
                _frame.size = size;
                [_surfaceObject windowResizedTo: size];
                [self resizeContentsTo: size];
                _CGSPostWindowEvent(kCGSWindowEventBounds, self.windowId, _frame);
            }
        }
        return;
    }

    if (kind == CGSWaylandObjectPopup) {
        // The compositor places the popup as it was asked to; it has no say in the size. When it
        // dismisses the popup the application's own ordering out still follows.
        return;
    }

    if (kind != CGSWaylandObjectToplevel)
        return;

    if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
        // A zero extent means "pick your own size", so the requested one stands.
        if (args[0].i > 0 && args[1].i > 0) {
            CGSize size = CGSizeMake(args[0].i, args[1].i);
            if (!CGSizeEqualToSize(size, _frame.size)) {
                _frame.size = size;
                [_surfaceObject windowResizedTo: size];
                [self resizeContentsTo: size];
                _CGSPostWindowEvent(kCGSWindowEventBounds, self.windowId, _frame);
            }
        }

        BOOL activated = NO;
        struct wl_array *states = args[2].a;
        for (size_t i = 0; states != NULL && i < states->size / sizeof(uint32_t); i++) {
            if (((uint32_t *) states->data)[i] == WP_TOPLEVEL_STATE_ACTIVATED)
                activated = YES;
        }
        if (activated != _activated) {
            _activated = activated;
            if (activated)
                [self bumpOrder];
            _CGSPostWindowEvent(activated ? kCGSWindowEventActivated : kCGSWindowEventDeactivated,
                                self.windowId, CGRectNull);
        }
    } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
        _CGSPostWindowEvent(kCGSWindowEventCloseRequested, self.windowId, CGRectNull);
    }
}


#pragma mark - Toplevel windows of the UI layer

- (instancetype) initToplevelWithAttributes: (const CGSToplevelAttributes *) attributes
                                 connection: (CGSConnection *) connection
                                   windowID: (CGSWindowID) windowID
{
    self = [self initWithRegion: NULL connection: connection windowID: windowID];
    if (self == nil)
        return nil;
    _ui = YES;
    _uiFrame = attributes->frame;
    return self;
}

- (struct wl_proxy *) xdgSurfaceProxy { return _xdgSurface; }
- (struct wl_proxy *) toplevelProxy { return _toplevel; }
- (struct wl_proxy *) popupProxy { return _popup; }
- (struct wl_proxy *) layerSurfaceProxy { return _layerSurface; }
- (void) setToplevelPopupGrabSerial: (uint32_t) serial { _uiPopupGrabSerial = serial; }
- (void) setToplevelContentOffset: (CGPoint) offset { _uiContentOffset = offset; }
- (void) noteToplevelFrame: (CGRect) frame { _uiFrame = frame; }
- (CGRect) toplevelFrame { return _ui ? _uiFrame : CGRectNull; }

- (CGError) setToplevelHints: (const CGSToplevelHints *) hints {
    if (!_ui || hints == NULL)
        return kCGErrorNotImplemented;
    _uiHints = *hints;
    return kCGSErrorSuccess;
}

- (CGError) reserveToplevelDockStrip {
    // The strip of a window shown as a layer surface is reserved with the surface.
    return _ui ? kCGSErrorSuccess : kCGErrorNotImplemented;
}

// The window's frame, whose origin is the one the UI layer asked for: a popup is placed relative to its parent and a
// layer surface along the output's top edge, so the origin matters to those only.
- (CGError) setToplevelFrame: (CGRect) frame {
    if (!_ui)
        return kCGErrorNotImplemented;
    BOOL moved = !CGPointEqualToPoint(frame.origin, _uiFrame.origin);
    BOOL sized = !CGSizeEqualToSize(frame.size, _uiFrame.size);
    _uiFrame = frame;
    if (_role == CGSWaylandRolePopup && (moved || sized) && WL.wl_proxy_get_version(_popup) >= 3) {
        struct wl_proxy *positioner = [self newUIPopupPositioner];
        union wl_argument args[2] = {{.o = (struct wl_object *) positioner}, {.u = ++_uiRepositionToken}};
        WaylandMarshal(_popup, WP_POPUP_REPOSITION, NULL, 0, args);
        WaylandMarshal(positioner, WP_POSITIONER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
        [_waylandConnection flush];
    } else if (_role == CGSWaylandRoleLayer && sized) {
        [self updateUILayerSize];
    }
    return kCGSErrorSuccess;
}

// The size limits as the window's geometry in the surface, in points (the UI layer adds what its own frame needs). A
// layer surface has its height from its frame instead.
- (CGError) setToplevelMinimumSize: (CGSize) minimum maximumSize: (CGSize) maximum {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiMinimumSize = minimum;
    _uiMaximumSize = maximum;
    _uiLimitsSet = YES;
    [self applyUIToplevelLimits];
    return kCGSErrorSuccess;
}

- (void) applyUIToplevelLimits {
    if (_toplevel == NULL || !_uiLimitsSet)
        return;
    union wl_argument min[2] = {{.i = (int32_t) _uiMinimumSize.width}, {.i = (int32_t) _uiMinimumSize.height}};
    union wl_argument max[2] = {{.i = (int32_t) _uiMaximumSize.width}, {.i = (int32_t) _uiMaximumSize.height}};
    // Double buffered: the compositor sees them with the surface's next commit.
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, min);
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, max);
}

// alpha-modifier-v1 multiplies the surface's per-pixel alpha. The protocol's factor is 0 for fully transparent and
// UINT32_MAX for fully opaque. Without the protocol the opacity is not applied (the compositor composites the window as
// it is); the UI layer decides what to do with a window that must be invisible (see -toplevelWindowSystemComposites).
- (CGError) setToplevelAlpha: (CGFloat) alpha {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiAlpha = alpha > 0 ? (alpha < 1 ? alpha : 1) : 0;
    [self applyUIAlpha];
    return kCGSErrorSuccess;
}

- (CGFloat) listedAlpha {
    return _ui && _uiAlphaSet ? _uiAlpha : 1;
}

- (void) alphaModifierAvailable {
    if (_ui && _uiAlphaSet)
        [self applyUIAlpha];
}

- (void) applyUIAlpha {
    _uiAlphaSet = YES;
    if (_surface == NULL || _waylandConnection->_alphaModifierManager == NULL)
        return;
    if (_alphaModifier == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _alphaModifier = [_waylandConnection createObject: _waylandConnection->_alphaModifierManager
                                                   opcode: WP_ALPHA_MODIFIER_GET_SURFACE
                                                interface: &wp_alpha_modifier_surface_v1_interface
                                                arguments: args
                                                     kind: CGSWaylandObjectNone
                                                   object: nil];
        if (_alphaModifier == NULL)
            return;
    }
    union wl_argument value[1] = {{.u = (uint32_t) ((double) _uiAlpha * (double) UINT32_MAX)}};
    WaylandMarshal(_alphaModifier, WP_ALPHA_MODIFIER_SURFACE_SET_MULTIPLIER, NULL, 0, value);
    // The multiplier is double-buffered: a surface that shows content takes it with its next commit.
    if (_uiConfigured) {
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        [_waylandConnection flush];
    }
}

- (CGError) setToplevelDecorated: (BOOL) decorated {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiDecorationRequest = decorated ? 1 : 2;
    [self applyUIDecoration];
    return kCGSErrorSuccess;
}

#pragma mark - Application menu

// The compositor is told the address of the menu while the window is a toplevel and has a manager for it; the object is
// released when either is gone.
- (void) applyApplicationMenu {
    if (_toplevel == NULL || _waylandConnection->_appMenuManager == NULL || _uiMenuService == nil || _uiMenuPath == nil) {
        destroyProxy(&_uiAppMenu, WP_APPMENU_RELEASE);
        return;
    }
    if (_uiAppMenu == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
        _uiAppMenu = [_waylandConnection createObject: _waylandConnection->_appMenuManager
                                               opcode: WP_APPMENU_MANAGER_CREATE
                                            interface: &org_kde_kwin_appmenu_interface
                                            arguments: args
                                                 kind: CGSWaylandObjectNone
                                               object: nil];
        if (_uiAppMenu == NULL)
            return;
    }
    // Both are ASCII: a unique bus name and an object path.
    union wl_argument address[2] = {{.s = [_uiMenuService UTF8String]}, {.s = [_uiMenuPath UTF8String]}};
    WaylandMarshal(_uiAppMenu, WP_APPMENU_SET_ADDRESS, NULL, 0, address);
    [_waylandConnection flush];
}

- (CGError) setToplevelApplicationMenuServiceName: (NSString *) service objectPath: (NSString *) path {
    if (!_ui)
        return kCGErrorNotImplemented;
    [_uiMenuService release];
    [_uiMenuPath release];
    _uiMenuService = [service copy];
    _uiMenuPath = [path copy];
    [self applyApplicationMenu];
    return kCGSErrorSuccess;
}

- (void) unsetToplevelDecoration {
    _uiDecorationRequest = 3;
    [self applyUIDecoration];
}

// A window with no title bar leaves the frame to the compositor's choice; one that shows no title bar of its own declares
// that it draws its frame itself (compositors differ on the default for a window that says nothing); a standard title
// bar is the compositor's unless the UI layer prefers to draw it.
- (void) updateUIDecorationRequest {
    switch (_uiTitlebarKind) {
    case kCGSToplevelTitlebarNone: _uiDecorationRequest = 3; break;
    case kCGSToplevelTitlebarHidden: _uiDecorationRequest = 2; break;
    case kCGSToplevelTitlebarStandard: _uiDecorationRequest = _uiPrefersClientDecoration ? 2 : 1; break;
    }
    [self applyUIDecoration];
}

- (CGError) setToplevelTitlebarKind: (CGSToplevelTitlebarKind) kind {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiTitlebarKind = kind;
    [self updateUIDecorationRequest];
    return kCGSErrorSuccess;
}

- (CGSToplevelTitlebarKind) toplevelTitlebarKind {
    return _uiTitlebarKind;
}

- (CGError) setToplevelPrefersClientDecoration: (BOOL) prefers {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiPrefersClientDecoration = prefers;
    [self updateUIDecorationRequest];
    return kCGSErrorSuccess;
}

#pragma mark - Client-side frame

- (CGError) setToplevelClientDecorationLayout: (const CGSToplevelDecorationLayout *) layout {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiHasDecorationLayout = layout != NULL;
    if (layout != NULL)
        _uiDecorationLayout = *layout;
    return kCGSErrorSuccess;
}

- (BOOL) toplevelClientDecorationContainsPoint: (CGPoint) point {
    if (!_uiHasDecorationLayout)
        return NO;
    const CGSToplevelDecorationLayout *layout = &_uiDecorationLayout;
    CGFloat left = layout->border, top = layout->border + layout->titleHeight;
    return point.x < left || point.y < top || point.x >= layout->size.width - layout->border ||
           point.y >= layout->size.height - layout->border;
}

// The press on the frame: an edge resizes (a window that cannot be resized ignores it), a button acts, the rest of the
// title bar moves the window. Every button of the frame is the frame's, the press and the release.
- (BOOL) handleToplevelDecorationButton: (uint32_t) button pressed: (BOOL) pressed serial: (uint32_t) serial atPoint: (CGPoint) point {
    if (![self toplevelClientDecorationContainsPoint: point])
        return NO;
    struct wl_proxy *seat = [_waylandConnection seat];
    if (!pressed || button != WP_BTN_LEFT || _toplevel == NULL || seat == NULL)
        return YES;
    const CGSToplevelDecorationLayout *layout = &_uiDecorationLayout;
    CGFloat border = layout->border;
    uint32_t edge = 0;
    if (point.y < border) edge |= 1;
    if (point.y >= layout->size.height - border) edge |= 2;
    if (point.x < border) edge |= 4;
    if (point.x >= layout->size.width - border) edge |= 8;
    union wl_argument args[3] = {{.o = (struct wl_object *) seat}, {.u = serial}, {.u = edge}};
    if (edge != 0) {
        if (layout->resizable)
            WaylandMarshal(_toplevel, WP_TOPLEVEL_RESIZE, NULL, 0, args);
    } else if (!CGRectIsNull(layout->closeButton) && CGRectContainsPoint(layout->closeButton, point)) {
        CGSToplevelEvent event = {.kind = kCGSToplevelEventCloseRequested, .rect = CGRectNull};
        [self postToplevelEvent: &event];
    } else if (!CGRectIsNull(layout->miniaturizeButton) && CGRectContainsPoint(layout->miniaturizeButton, point)) {
        [self miniaturizeToplevel];
    } else if (!CGRectIsNull(layout->zoomButton) && CGRectContainsPoint(layout->zoomButton, point)) {
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_toplevel, _uiPending.maximized ? WP_TOPLEVEL_UNSET_MAXIMIZED : WP_TOPLEVEL_SET_MAXIMIZED, NULL, 0,
                       none);
    } else {
        WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    }
    [_waylandConnection flush];
    return YES;
}

// xdg_toplevel.move for the left button press that is being held on the window, with the serial of that press.
- (CGError) beginToplevelMoveByWindowSystem {
    struct wl_proxy *seat = [_waylandConnection seat];
    uint32_t serial = _toplevel != NULL && seat != NULL ? [_waylandConnection heldLeftPressSerialForSurface: _surface] : 0;
    if (serial == 0)
        return kCGErrorFailure;
    union wl_argument args[2] = {{.o = (struct wl_object *) seat}, {.u = serial}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_MOVE, NULL, 0, args);
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

// Tells the compositor which side draws the frame. Compositors differ on the default for a window that says nothing, so a
// window whose frame is its own says so.
- (void) applyUIDecoration {
    if (_toplevel == NULL || _waylandConnection->_decorationManager == NULL || _uiDecorationRequest == 0)
        return;
    if (_uiDecorationRequest == 3) {
        if (_decoration != NULL) {
            union wl_argument none[1] = {{.o = NULL}};
            WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_UNSET_MODE, NULL, 0, none);
        }
        return;
    }
    if (_decoration == NULL) {
        union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _toplevel}};
        _decoration = [_waylandConnection createObject: _waylandConnection->_decorationManager
                                                opcode: WP_DECORATION_MANAGER_GET_TOPLEVEL_DECORATION
                                             interface: &zxdg_toplevel_decoration_v1_interface
                                             arguments: args
                                                  kind: CGSWaylandObjectDecoration
                                                object: self];
        if (_decoration == NULL)
            return;
    }
    union wl_argument mode[1] = {{.u = _uiDecorationRequest == 1 ? WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE
                                                                 : WP_TOPLEVEL_DECORATION_MODE_CLIENT_SIDE}};
    WaylandMarshal(_decoration, WP_TOPLEVEL_DECORATION_SET_MODE, NULL, 0, mode);
}

// An empty input region lets pointer input reach the surfaces below; no region restores the default.
- (CGError) setToplevelIgnoresMouseEvents: (BOOL) ignores {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiIgnoresMouse = ignores;
    struct wl_proxy *region = NULL;
    if (ignores) {
        union wl_argument regionArgs[1] = {{.o = NULL}};
        region = [_waylandConnection createObject: _waylandConnection->_compositor
                                           opcode: WP_COMPOSITOR_CREATE_REGION
                                        interface: &wl_region_interface
                                        arguments: regionArgs
                                             kind: CGSWaylandObjectNone
                                           object: nil];
    }
    union wl_argument inputArgs[1] = {{.o = (struct wl_object *) region}};
    WaylandMarshal(_surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, inputArgs);
    if (region != NULL)
        WaylandMarshal(region, WP_REGION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    return kCGSErrorSuccess;
}

// A new native window with the surface's role gone: the wl_surface keeps its role for its lifetime, so a window that is
// shown with another role needs a new one. Whatever the UI layer made of the old surface (subsurfaces, extensions) is
// destroyed before this is called. The role has to be hidden.
- (CGError) recreateToplevelWithAttributes: (const CGSToplevelAttributes *) attributes {
    if (!_ui || attributes == NULL)
        return kCGErrorNotImplemented;
    if (_role != CGSWaylandRoleNone)
        return kCGErrorFailure;
    destroyProxy(&_alphaModifier, WP_ALPHA_MODIFIER_SURFACE_DESTROY);
    if (_surface != NULL)
        WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    union wl_argument args[2] = {{.o = NULL}};
    _surface = [_waylandConnection createObject: _waylandConnection->_compositor
                                         opcode: WP_COMPOSITOR_CREATE_SURFACE
                                      interface: &wl_surface_interface
                                      arguments: args
                                           kind: CGSWaylandObjectNone
                                         object: nil];
    if (_surface == NULL)
        return kCGErrorFailure;
    _uiFrame = attributes->frame;
    _uiIgnoresMouse = NO;
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

- (CGSWaylandRole) wantedUIRole {
    if (_uiHints.kind == kCGSToplevelKindDock && _waylandConnection->_layerShell != NULL)
        return CGSWaylandRoleLayer;
    BOOL popupKind = _uiHints.kind == kCGSToplevelKindDropdownMenu || _uiHints.kind == kCGSToplevelKindPopupMenu ||
                     _uiHints.kind == kCGSToplevelKindTooltip;
    CGSWindowWayland *parent = (CGSWindowWayland *) _uiHints.transientFor;
    if (popupKind && parent != nil && (parent->_xdgSurface != NULL || parent->_layerSurface != NULL))
        return CGSWaylandRolePopup;
    return CGSWaylandRoleToplevel;
}

// The bar is anchored to the top, left and right edges, as tall as the window is, and keeps that strip free of other
// windows (the exclusive zone).
- (void) updateUILayerSize {
    int32_t height = MAX(1, (int32_t) ceil(_uiFrame.size.height));
    union wl_argument size[2] = {{.u = 0}, {.u = (uint32_t) height}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_SIZE, NULL, 0, size);
    union wl_argument zone[1] = {{.i = height}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_EXCLUSIVE_ZONE, NULL, 0, zone);
}

- (void) createUILayerRole {
    union wl_argument args[5] = {{.o = NULL}, {.o = (struct wl_object *) _surface}, {.o = NULL},
                                 {.u = WP_LAYER_TOP}, {.s = "menubar"}};
    _layerSurface = [_waylandConnection createObject: _waylandConnection->_layerShell
                                              opcode: WP_LAYER_SHELL_GET_LAYER_SURFACE
                                           interface: &zwlr_layer_surface_v1_interface
                                           arguments: args
                                                kind: CGSWaylandObjectLayerSurface
                                              object: self];
    if (_layerSurface == NULL)
        return;
    _role = CGSWaylandRoleLayer;
    union wl_argument anchor[1] = {{.u = WP_LAYER_ANCHOR_TOP | WP_LAYER_ANCHOR_LEFT | WP_LAYER_ANCHOR_RIGHT}};
    WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_SET_ANCHOR, NULL, 0, anchor);
    [self updateUILayerSize];
    // The bar never takes the keyboard focus (the protocol default): a compositor that gives an on-demand surface the focus
    // when the pointer is over it would take it from the application's window, which then looks like the application losing
    // the focus, so the bar would hide, and show again once the focus came back, in a loop. The menus the bar opens grab
    // the keyboard themselves.
}

// The positioner of the pop-up: where the window's frame is relative to its parent's content. The frames are in the space
// of -setToplevelFrame: (y up), the pop-up's position in the parent's surface (y down); the parent's own frame, when it
// has one, starts at its content offset.
- (struct wl_proxy *) newUIPopupPositioner {
    CGSWindowWayland *parent = _popupParent;
    union wl_argument args[4] = {{.o = NULL}};
    struct wl_proxy *positioner = [_waylandConnection createObject: _waylandConnection->_wmBase
                                                            opcode: WP_WM_BASE_CREATE_POSITIONER
                                                         interface: &xdg_positioner_interface
                                                         arguments: args
                                                              kind: CGSWaylandObjectNone
                                                            object: nil];
    args[0].i = MAX(1, (int32_t) ceil(_uiFrame.size.width));
    args[1].i = MAX(1, (int32_t) ceil(_uiFrame.size.height));
    WaylandMarshal(positioner, WP_POSITIONER_SET_SIZE, NULL, 0, args);
    CGRect parentFrame = parent->_uiFrame;
    CGPoint offset = parent->_uiContentOffset;
    int32_t x = (int32_t) floor(_uiFrame.origin.x - parentFrame.origin.x + offset.x);
    int32_t y = (int32_t) floor(CGRectGetMaxY(parentFrame) - CGRectGetMaxY(_uiFrame) + offset.y);
    // A submenu can start beyond its parent edge. Keep the anchor inside the parent geometry, expressing the remaining
    // displacement as an offset.
    int32_t anchorX = MAX(0, MIN(x, (int32_t) ceil(parentFrame.size.width + 2 * offset.x) - 1));
    int32_t anchorY = MAX(0, MIN(y, (int32_t) ceil(parentFrame.size.height + offset.x + offset.y) - 1));
    args[0].i = anchorX;
    args[1].i = anchorY;
    args[2].i = args[3].i = 1;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR_RECT, NULL, 0, args);
    args[0].i = x - anchorX;
    args[1].i = y - anchorY;
    WaylandMarshal(positioner, WP_POSITIONER_SET_OFFSET, NULL, 0, args);
    args[0].u = WP_POSITIONER_ANCHOR_TOP_LEFT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_ANCHOR, NULL, 0, args);
    args[0].u = WP_POSITIONER_GRAVITY_BOTTOM_RIGHT;
    WaylandMarshal(positioner, WP_POSITIONER_SET_GRAVITY, NULL, 0, args);
    args[0].u = WP_POSITIONER_SLIDE_X | WP_POSITIONER_SLIDE_Y | WP_POSITIONER_FLIP_X | WP_POSITIONER_FLIP_Y;
    WaylandMarshal(positioner, WP_POSITIONER_SET_CONSTRAINT_ADJUSTMENT, NULL, 0, args);
    return positioner;
}

// A pop-up of the window the UI layer named. A pop-up that the UI layer gave a grab serial is grabbed, one that it
// gave none is not (a tool tip, a pop-up window of the application: they end when the UI layer hides them).
- (void) createUIPopupRole {
    CGSWindowWayland *parent = (CGSWindowWayland *) _uiHints.transientFor;
    _popupParent = [parent retain];
    union wl_argument args[3] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
    _xdgSurface = [_waylandConnection createObject: _waylandConnection->_wmBase
                                            opcode: WP_WM_BASE_GET_XDG_SURFACE
                                         interface: &xdg_surface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectXdgSurface
                                            object: self];
    if (_xdgSurface == NULL)
        return;
    struct wl_proxy *positioner = [self newUIPopupPositioner];
    // A popup of a layer surface has no xdg parent; the layer surface adopts it.
    BOOL layerParent = parent->_layerSurface != NULL;
    args[0].o = NULL;
    args[1].o = layerParent ? NULL : (struct wl_object *) parent->_xdgSurface;
    args[2].o = (struct wl_object *) positioner;
    _popup = [_waylandConnection createObject: _xdgSurface
                                       opcode: WP_XDG_SURFACE_GET_POPUP
                                    interface: &xdg_popup_interface
                                    arguments: args
                                         kind: CGSWaylandObjectPopup
                                       object: self];
    if (_popup != NULL && layerParent) {
        args[0].o = (struct wl_object *) _popup;
        WaylandMarshal(parent->_layerSurface, WP_LAYER_SURFACE_GET_POPUP, NULL, 0, args);
    }
    WaylandMarshal(positioner, WP_POSITIONER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                   (union wl_argument[1]) {{.o = NULL}});
    if (_popup == NULL)
        return;
    _role = CGSWaylandRolePopup;
    if (_uiPopupGrabSerial != 0 && [_waylandConnection seat] != NULL) {
        args[0].o = (struct wl_object *) [_waylandConnection seat];
        args[1].u = _uiPopupGrabSerial;
        WaylandMarshal(_popup, WP_POPUP_GRAB, NULL, 0, args);
    }
}

- (void) createUIToplevelRole {
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _surface}};
    _xdgSurface = [_waylandConnection createObject: _waylandConnection->_wmBase
                                            opcode: WP_WM_BASE_GET_XDG_SURFACE
                                         interface: &xdg_surface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectXdgSurface
                                            object: self];
    if (_xdgSurface == NULL)
        return;
    args[0].o = NULL;
    _toplevel = [_waylandConnection createObject: _xdgSurface
                                          opcode: WP_XDG_SURFACE_GET_TOPLEVEL
                                       interface: &xdg_toplevel_interface
                                       arguments: args
                                            kind: CGSWaylandObjectToplevel
                                          object: self];
    if (_toplevel == NULL)
        return;
    _role = CGSWaylandRoleToplevel;
    // A new toplevel starts as the compositor makes it: windowed, not minimized.
    _uiFullscreenRequested = _uiFullscreen = _uiFullscreenSettling = NO;
    _uiSuspended = _uiActivated = NO;
    union wl_argument title[1] = {{.s = _title != nil ? [_title UTF8String] : ""}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, title);
    union wl_argument appID[1] = {{.s = [[[NSProcessInfo processInfo] processName] UTF8String]}};
    if (appID[0].s != NULL)
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_APP_ID, NULL, 0, appID);
    [self applyUIToplevelLimits];
    [self applyUIDecoration];
    [self applyApplicationMenu];
}

- (CGError) showToplevel {
    if (_role != CGSWaylandRoleNone) {
        _shown = YES;
        return kCGSErrorSuccess;
    }
    _uiMinimizeAdvertised = NO;
    _uiDecorationReported = NO;
    memset(&_uiPending, 0, sizeof(_uiPending));
    switch ([self wantedUIRole]) {
    case CGSWaylandRoleLayer:
        [self createUILayerRole];
        break;
    case CGSWaylandRolePopup:
        [self createUIPopupRole];
        break;
    default:
        [self createUIToplevelRole];
        break;
    }
    if (_role == CGSWaylandRoleNone) {
        [self destroyRole];
        return kCGErrorFailure;
    }
    _shown = YES;
    CGSToplevelEvent event = {.kind = kCGSToplevelEventWillShow, .rect = CGRectNull};
    [self postToplevelEvent: &event];
    // The initial commit has no buffer: content follows the first configure.
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

// Unmapping an xdg surface requires a new configure sequence before it can be shown again, so the role objects are
// destroyed and created again when the window is shown. The wl_surface stays: what the UI layer attached to it keeps
// its place.
- (CGError) hideToplevel {
    [_waylandConnection inputMethodWindowUnmapped: self];
    _shown = NO;
    _uiConfigured = NO;
    if (_role == CGSWaylandRoleNone)
        return kCGSErrorSuccess;
    // The toplevel is gone, and so is what the compositor did to it.
    [self endMinimized];
    _uiActivated = _uiSuspended = NO;
    _uiFullscreenRequested = _uiFullscreen = _uiFullscreenSettling = NO;
    [self destroyRole];
    NSArray *windows = [_waylandConnection copyAllWindows];
    for (CGSWindow *window in windows)
        if ([window isKindOfClass: [CGSWindowWayland class]])
            [(CGSWindowWayland *) window relatedToplevelHidden: self];
    [windows release];
    union wl_argument attach[3] = {{.o = NULL}, {.i = 0}, {.i = 0}};
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
    _uiPending.popupX = _uiPending.popupY = 0;
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

// What the compositor sends the window's objects is told to the UI layer: the pieces of a configure sequence are
// gathered, and the sequence's end (xdg_surface.configure) is acknowledged and reported with all of them.
- (void) handleToplevelEvent: (uint32_t) opcode
                        kind: (CGSWaylandObjectKind) kind
                   arguments: (union wl_argument *) args
{
    switch (kind) {
    case CGSWaylandObjectXdgSurface:
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE) {
            union wl_argument ack[1] = {{.u = args[0].u}};
            WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
            [self postConfigured];
        }
        break;

    case CGSWaylandObjectLayerSurface:
        if (opcode == WP_LAYER_SURFACE_EV_CONFIGURE) {
            union wl_argument ack[1] = {{.u = args[0].u}};
            WaylandMarshal(_layerSurface, WP_LAYER_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
            // A zero size leaves the choice to the client.
            memset(&_uiPending, 0, sizeof(_uiPending));
            _uiPending.width = (int32_t) args[1].u;
            _uiPending.height = (int32_t) args[2].u;
            [self postConfigured];
        } else if (opcode == WP_LAYER_SURFACE_EV_CLOSED) {
            CGSToplevelEvent event = {.kind = kCGSToplevelEventDismissed, .rect = CGRectNull};
            [self postToplevelEvent: &event];
        }
        break;

    case CGSWaylandObjectToplevel:
        if (opcode == WP_TOPLEVEL_EV_CONFIGURE) {
            _uiPending.width = args[0].i;
            _uiPending.height = args[1].i;
            struct wl_array *states = args[2].a;
            _uiPending.activated = _uiPending.maximized = _uiPending.fullscreen = _uiPending.suspended = false;
            const uint32_t *state;
            if (states != NULL)
                wl_array_for_each(state, states) {
                    switch (*state) {
                    case WP_TOPLEVEL_STATE_ACTIVATED: _uiPending.activated = true; break;
                    case WP_TOPLEVEL_STATE_MAXIMIZED: _uiPending.maximized = true; break;
                    case WP_TOPLEVEL_STATE_FULLSCREEN: _uiPending.fullscreen = true; break;
                    case WP_TOPLEVEL_STATE_SUSPENDED: _uiPending.suspended = true; break;
                    }
                }
        } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
            CGSToplevelEvent event = {.kind = kCGSToplevelEventCloseRequested, .rect = CGRectNull};
            [self postToplevelEvent: &event];
        } else if (opcode == WP_TOPLEVEL_EV_WM_CAPABILITIES) {
            // Applies with the configure that follows it.
            _uiPending.minimizeAdvertised = false;
            const uint32_t *capability;
            if (args[0].a != NULL)
                wl_array_for_each(capability, args[0].a)
                    if (*capability == WP_TOPLEVEL_CAPABILITY_MINIMIZE)
                        _uiPending.minimizeAdvertised = true;
            _uiMinimizeAdvertised = _uiPending.minimizeAdvertised;
        }
        break;

    case CGSWaylandObjectDecoration:
        if (opcode == WP_TOPLEVEL_DECORATION_EV_CONFIGURE) {
            _uiDecorationReported = YES;
            _uiClientDecorated = args[0].u != WP_TOPLEVEL_DECORATION_MODE_SERVER_SIDE;
        }
        break;

    case CGSWaylandObjectPopup:
        if (opcode == WP_POPUP_EV_CONFIGURE) {
            _uiPending.popupX = args[0].i;
            _uiPending.popupY = args[1].i;
            _uiPending.width = args[2].i;
            _uiPending.height = args[3].i;
        } else if (opcode == WP_POPUP_EV_DONE) {
            CGSToplevelEvent event = {.kind = kCGSToplevelEventDismissed, .rect = CGRectNull};
            [self postToplevelEvent: &event];
        }
        break;

    default:
        break;
    }
}

- (void) postConfigured {
    CGSToplevelEvent event = {.kind = kCGSToplevelEventConfigured, .rect = CGRectNull};
    event.configure = _uiPending;
    event.configure.minimizeAdvertised = _uiMinimizeAdvertised;
    event.configure.decorationReported = _uiDecorationReported;
    event.configure.clientDecorated = _uiClientDecorated;
    BOOL first = !_uiConfigured;
    _uiConfigured = YES;
    [self postToplevelEvent: &event];
    [self applyConfiguredState];
    // What the window drew while it waited for the configure is shown now.
    if (first && [self withContents: ^(const void *bytes, size_t rowBytes, CGSize size) {}])
        [self presentRect: CGRectMake(0, 0, _frame.size.width, _frame.size.height)];
}


#pragma mark - Order, relation, focus, minimizing and fullscreen

// The window's place in the order the process knows of its windows: the window that was activated or ordered to the front
// last comes first, then the windows that never were, the older one in front (xdg-shell tells a client nothing of the
// stacking, so this is the order that follows what the compositor told).
- (uint64_t) orderRank {
    const uint64_t base = UINT64_C(1) << 62;
    return _orderStamp != 0 ? base + _orderStamp : base - _creationStamp;
}

- (void) bumpOrder {
    _orderStamp = ++sOrderCounter;
}

- (BOOL) isOrderedIn {
    return _shown || _uiHeldBack;
}

- (BOOL) isUIToplevel {
    return _ui;
}

- (BOOL) isMinimizedByRequest {
    return _uiMinimized;
}

- (void) postStateEvent: (CGSToplevelEventKind) kind state: (BOOL) state {
    CGSToplevelEvent event = {.kind = kind, .rect = CGRectNull, .state = state};
    [self postToplevelEvent: &event];
}

// What the end of a configure sequence says of the window, as the changes of its state: the keyboard focus, being covered,
// being fullscreen, and an answer to a request for fullscreen. The window is shown again when it is activated.
- (void) applyConfiguredState {
    BOOL toplevel = _role == CGSWaylandRoleToplevel;
    BOOL activated = toplevel && _uiPending.activated;
    BOOL suspended = toplevel && _uiPending.suspended;
    BOOL fullscreen = toplevel && _uiPending.fullscreen;
    if (activated != _uiActivated) {
        _uiActivated = activated;
        if (activated) {
            [self bumpOrder];
            // Only the change to activated shows a restore: a configure that repeats the state of a window that was active
            // when it was minimized may already be on its way.
            [self endMinimized];
        }
        [self postStateEvent: activated ? kCGSToplevelEventFocusGained : kCGSToplevelEventFocusLost state: activated];
    }
    if (suspended != _uiSuspended) {
        _uiSuspended = suspended;
        [self postStateEvent: kCGSToplevelEventOcclusionChanged state: suspended];
    }
    if (fullscreen != _uiFullscreen) {
        _uiFullscreen = fullscreen;
        [self postStateEvent: kCGSToplevelEventFullscreenChanged state: fullscreen];
    }
    if (_uiFullscreenSettling && fullscreen == _uiFullscreenRequested) {
        _uiFullscreenSettling = NO;
        ++_uiSettleToken;
        [self postStateEvent: kCGSToplevelEventFullscreenSettled state: fullscreen];
    }
}

- (CGError) setToplevelLevel: (int) level {
    if (!_ui)
        return kCGErrorNotImplemented;
    // xdg-shell can relate windows but not stack them by level: what the level means is the UI layer's decision, which it
    // makes known with -setToplevelParent:.
    _uiLevel = level;
    return kCGSErrorSuccess;
}

- (CGError) setToplevelStacksByLevel: (BOOL) stacks {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiStacksByLevel = stacks;
    return kCGSErrorSuccess;
}

- (CGError) restackToplevelForLevels {
    return _ui ? kCGSErrorSuccess : kCGErrorNotImplemented;
}

// The compositor stacks the windows of a client as it likes; the only thing a client knows is the order it activated or
// asked for them in. Ordering in front of another window, or to the back, cannot be asked for.
- (CGError) orderToplevelAbove: (CGSWindow *) sibling {
    if (!_ui || sibling != nil)
        return kCGErrorNotImplemented;
    [self bumpOrder];
    return kCGSErrorSuccess;
}

- (CGError) orderToplevelBelow: (CGSWindow *) sibling {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelHeldBack: (BOOL) heldBack {
    if (!_ui)
        return kCGErrorNotImplemented;
    _uiHeldBack = heldBack;
    return kCGSErrorSuccess;
}

- (BOOL) toplevelHoldsKeyboardFocus {
    return _ui && _shown && _uiActivated;
}

- (BOOL) toplevelIsOccluded {
    return _ui && _shown && _uiSuspended;
}

#pragma mark Parent

- (CGSWindow *) toplevelParent {
    return _ui ? _levelParent : nil;
}

- (CGError) setToplevelParent: (CGSWindow *) parentWindow {
    if (!_ui)
        return kCGErrorNotImplemented;
    if (_toplevel == NULL)
        return kCGErrorFailure;
    CGSWindowWayland *parent = (CGSWindowWayland *) parentWindow;
    if (parent != nil) {
        if (![parent isKindOfClass: [CGSWindowWayland class]] || parent == self || parent->_toplevel == NULL)
            return kCGErrorIllegalArgument;
        // A window must not be its own ancestor: that is a protocol error.
        int depth = 0;
        for (CGSWindowWayland *up = parent->_levelParent; up != nil && depth < 16; up = up->_levelParent, depth++)
            if (up == self)
                return kCGErrorIllegalArgument;
    }
    if (parent == _levelParent)
        return kCGSErrorSuccess;
    _levelParent = parent;
    WaylandToplevelSetParent(_toplevel, parent != nil ? parent->_toplevel : NULL);
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

// The compositor reparents the windows that were children of the hidden one itself.
- (void) relatedToplevelHidden: (CGSWindowWayland *) hidden {
    if (!_ui || _levelParent != hidden)
        return;
    _levelParent = nil;
    [self postStateEvent: kCGSToplevelEventParentLost state: NO];
}

#pragma mark Fullscreen

- (CGError) setToplevelFullscreen: (BOOL) fullscreen force: (BOOL) force {
    return [self setToplevelFullscreen: fullscreen onOutput: NULL force: force];
}

- (CGError) setToplevelFullscreen: (BOOL) fullscreen onOutput: (struct wl_proxy *) output force: (BOOL) force {
    if (!_ui || _toplevel == NULL)
        return kCGErrorNotImplemented;
    if (fullscreen == _uiFullscreenRequested && !force)
        return kCGSErrorSuccess;
    _uiFullscreenRequested = fullscreen;
    if (fullscreen)
        WaylandToplevelSetFullscreen(_toplevel, output);
    else
        WaylandToplevelUnsetFullscreen(_toplevel);
    if (_uiConfigured)
        [self beginFullscreenSettle];
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

// After set_fullscreen or unset_fullscreen the client waits for the configure that answers it before it commits again:
// the compositor decides the size. A commit sent before the answer arrives has the size the window gets from the
// application's own side of the change (the title bar goes away, for instance), and a compositor that lets a client's size
// count for a floating window (sway) then sends one more configure with that size and the fullscreen state, which wins over
// the real fullscreen size. The wait ends with a configure that brings the requested state, or after a second when the
// compositor answers nothing.
- (void) beginFullscreenSettle {
    _uiFullscreenSettling = YES;
    NSUInteger token = ++_uiSettleToken;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (self->_uiSettleToken != token || !self->_uiFullscreenSettling)
            return;
        self->_uiFullscreenSettling = NO;
        [self postStateEvent: kCGSToplevelEventFullscreenSettled state: self->_uiFullscreen];
    });
}

- (BOOL) toplevelFullscreenRequested {
    return _ui && _uiFullscreenRequested;
}

- (BOOL) toplevelIsFullscreen {
    return _ui && _shown && _uiFullscreen;
}

- (BOOL) toplevelFullscreenSettling {
    return _ui && _uiFullscreenSettling;
}

#pragma mark Minimizing

// xdg-shell has no request to undo set_minimized and no event that says a toplevel is minimized, so the window keeps the
// state itself. GUESS: the compositor minimizes the window when asked (it may ignore the request, and then the window is
// reported miniaturized until it is shown again). The state is kept only when something can bring the window back
// (xdg-activation) and the compositor advertised that it minimizes (a compositor that did not ignores the request, so the
// window would be reported miniaturized while it stays on screen). Otherwise the request is sent as before and the window
// keeps being reported as not miniaturized. GUESS: a compositor that predates the capabilities event (xdg_toplevel before
// version 5) minimizes.
- (BOOL) compositorMinimizes {
    return WL.wl_proxy_get_version(_toplevel) < 5 || _uiMinimizeAdvertised;
}

- (CGError) miniaturizeToplevel {
    if (!_ui || _toplevel == NULL)
        return kCGErrorNotImplemented;
    if (_uiMinimized)
        return kCGSErrorSuccess;
    WaylandToplevelSetMinimized(_toplevel);
    [_waylandConnection flush];
    if (_waylandConnection->_activation == NULL || ![self compositorMinimizes])
        return kCGSErrorSuccess;
    _uiMinimized = YES;
    [_waylandConnection performAfterDispatch: ^{
        if (self->_uiMinimized)
            [self postStateEvent: kCGSToplevelEventMiniaturized state: YES];
    }];
    return kCGSErrorSuccess;
}

// The only client-side way to bring a minimized toplevel back is to ask for its activation (xdg-activation-v1); the
// compositor decides, and may only mark the window as wanting attention. The window counts as shown again from the
// request on. If no request could be made (one is waiting for its token) the state stays, and asking again later works. A
// restore the compositor does itself (its task bar) ends the state when a configure changes the window to activated (see
// -applyConfiguredState); a compositor that never reports the window deactivated cannot be told.
- (CGError) deminiaturizeToplevel {
    if (!_ui)
        return kCGErrorNotImplemented;
    if (_uiMinimized && [_waylandConnection requestActivationOfWindow: self])
        [self endMinimized];
    return kCGSErrorSuccess;
}

- (BOOL) toplevelIsMiniaturized {
    return _ui && _uiMinimized;
}

// The window is shown again (activated by the compositor, or mapped anew): tells the UI layer.
- (void) endMinimized {
    if (!_uiMinimized)
        return;
    _uiMinimized = NO;
    [_waylandConnection performAfterDispatch: ^{
        if (!self->_uiMinimized)
            [self postStateEvent: kCGSToplevelEventDeminiaturized state: NO];
    }];
}

#pragma mark - CGSWindow

- (void *) nativeWindow {
    return _surface;
}

- (CGSSurface *) createSurface {
    // The surfaces of a toplevel window are subsurfaces (any number); the surface of any other window is the
    // window's own, and there is one
    BOOL sub = _role == CGSWaylandRoleToplevel && _waylandConnection->_subcompositor != NULL;
    if (!sub && _surfaceObject != nil) {
        NSLog(@"CoreGraphics Wayland backend: window %d already has a surface; "
              @"more than one surface per window needs subsurfaces, which a toplevel window has",
              (int) self.windowId);
        return nil;
    }

    if (![self ensureRole])
        return nil;
    sub = _role == CGSWaylandRoleToplevel && _waylandConnection->_subcompositor != NULL;
    CGSSurfaceID surfaceID = _nextSurfaceId++;
    CGSSurfaceWayland *surface =
            [[CGSSurfaceWayland alloc] initWithWindow: self surfaceID: surfaceID];
    if (surface == nil)
        return nil;

    @synchronized (_surfaces) {
        [_surfaces setObject: surface
                      forKey: [NSNumber numberWithInt: surfaceID]];
    }
    if (!sub)
        _surfaceObject = surface;
    [surface release];
    return surface;
}

- (CGError) orderWindow: (CGSWindowOrderingMode) place
             relativeTo: (CGSWindow *) window
{
    if (_ui) {
        if (place == kCGSOrderOut)
            return [self hideToplevel];
        if (place == kCGSOrderIn || place == kCGSOrderAbove)
            return [self showToplevel];
        return kCGErrorNotImplemented;
    }
    if (window != nil) {
        // Wayland gives a client no say in how its toplevels stack.
        NSLog(@"CoreGraphics Wayland backend: relative window ordering is not "
              @"available on Wayland");
        return kCGErrorNotImplemented;
    }

    switch (place) {
    case kCGSOrderOut: {
        [_waylandConnection inputMethodWindowUnmapped: self];
        _shown = NO;
        // The pointer lock held for an overlay that goes away is made on a window again.
        if (_displayOverlay)
            [_waylandConnection pointerLockTargetMayHaveChanged];
        if (_role == CGSWaylandRoleNone)
            return kCGSErrorSuccess;
        if (_role == CGSWaylandRolePopup) {
            // A popup cannot be shown again: its role is made anew when the window is next shown.
            [self destroyRole];
            union wl_argument attach[3] = {{.o = NULL}, {.i = 0}, {.i = 0}};
            union wl_argument none[1] = {{.o = NULL}};
            WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
            WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
            [_waylandConnection flush];
            return kCGSErrorSuccess;
        }
        // Attaching a null buffer unmaps the toplevel, which also returns the
        // xdg_surface to the unconfigured state. xdg-shell then requires the
        // initial commit procedure again before the next buffer, so the empty
        // commit and the wait for its configure happen here rather than leaving
        // the next eglSwapBuffers to attach into an unconfigured surface.
        union wl_argument attach[3] = {{.o = NULL}, {.i = 0}, {.i = 0}};
        union wl_argument none[1] = {{.o = NULL}};
        // What the compositor sent so far is acknowledged before the window is unmapped
        if (WL.wl_display_roundtrip(_waylandConnection->_wlDisplay) < 0)
            return kCGErrorFailure;
        _unmapping = YES;
        _unmappedToplevel = YES;
        WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        int result = WL.wl_display_roundtrip(_waylandConnection->_wlDisplay);
        _unmapping = NO;
        if (_hasPendingConfigure) {
            _hasPendingConfigure = NO;
            [self acknowledgeConfigure: _pendingConfigureSerial];
        }
        if (result < 0) {
            NSLog(@"CoreGraphics Wayland backend: the connection failed while "
                  @"hiding window %d", (int) self.windowId);
            return kCGErrorFailure;
        }
        return kCGSErrorSuccess;
    }

    case kCGSOrderIn:
    case kCGSOrderAbove:
        if (![self ensureRole])
            return kCGErrorFailure;
        BOOL wasShown = _shown;
        _shown = YES;
        BOOL restored = _unmappedToplevel;
        if (restored)
            [self restoreToplevelState];
        // A floating window that was shown before the window it floats over gets that parent now.
        if ([self isDocumentLike]) {
            NSArray *windows = [_waylandConnection copyAllWindows];
            for (CGSWindowWayland *window in windows)
                if (window != self && !window->_ui && window->_role == CGSWaylandRoleToplevel)
                    [window updateLevelParent];
            [windows release];
        }
        // A toplevel is mapped by its first committed buffer. A window that a program draws into
        // shows its contents, or a blank window while it has drawn none; the others appear when
        // their surface swaps.
        if (_usesContents)
            [self _showBlankContentsIfNone];
        if (restored) {
            // KWin takes the parent of a shown-again toplevel only when it changes
            CGSWindowWayland *parent = _levelParent;
            if (parent != nil && _toplevel != NULL) {
                union wl_argument none[1] = {{.o = NULL}};
                WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_PARENT, NULL, 0, none);
                _levelParent = nil;
                [self updateLevelParent];
            }
        }
        if (!wasShown && [self isDocumentLike] && _usesContents) {
            NSArray *windows = [_waylandConnection copyAllWindows];
            [self mapFloatingWindowsAgain: windows];
            [windows release];
        }
        // The pointer of the relative mouse mode is locked to an overlay while there is one.
        if (_displayOverlay)
            [_waylandConnection pointerLockTargetMayHaveChanged];
        return kCGSErrorSuccess;

    case kCGSOrderBelow:
    default:
        NSLog(@"CoreGraphics Wayland backend: window ordering mode %d is not "
              @"available on Wayland", (int) place);
        return kCGErrorNotImplemented;
    }
}

- (CGError) becomeDisplayOverlay: (void **) drawable {
    if (drawable == NULL)
        return kCGErrorIllegalArgument;

    // The overlay is a toplevel that covers the output, whatever level it has. The compositor draws no
    // frame for it: a toplevel that asks for server-side decoration keeps its title bar above the content
    // on some compositors even when fullscreen, which puts the surface below the output's origin by the
    // height of the bar and shifts the pointer's surface coordinates with it.
    BOOL hadRole = _role != CGSWaylandRoleNone;
    _styleFlags |= kCGSWindowStyleBorderless | kCGSWindowStyleUnmanaged;
    if (!hadRole) {
        _level = kCGNormalWindowLevel;
        if (![self ensureRole])
            return kCGErrorFailure;
    }
    if (_toplevel == NULL)
        return kCGErrorFailure;
    if (hadRole)
        [self applyToplevelStyle: kCGSWindowStyleBorderless | kCGSWindowStyleUnmanaged];

    // The surface keeps the default input region (all of it): the overlay takes the pointer and the keys of
    // the display it covers. The pointer decoder makes events of them like those of any window,
    // but they name no window of the application (a captured display's do not either).
    _displayOverlay = YES;

    // Let the compositor pick the output; the window covers it.
    union wl_argument fullscreenArgs[1] = {{.o = NULL}};
    WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_FULLSCREEN, NULL, 0, fullscreenArgs);
    [_waylandConnection flush];

    CGSSurface *surface = [self createSurface];
    if (surface == nil)
        return kCGErrorFailure;
    *drawable = [surface nativeWindow];
    return *drawable != NULL ? kCGSErrorSuccess : kCGErrorFailure;
}

- (CGError) moveTo: (const CGPoint *) point {
    if (point == NULL)
        return kCGErrorIllegalArgument;
    // A Wayland client cannot place its own toplevels (xdg_toplevel.move only starts an interactive
    // drag, which is not what this asks for); a compositor with KDE's plasma shell takes a position.
    // The role of a layer surface or a popup fixes where it is.
    if (_waylandConnection->_plasmaShell == NULL || _role == CGSWaylandRoleLayer || _role == CGSWaylandRolePopup)
        return kCGErrorNotImplemented;
    _frame.origin = *point;
    if (_role == CGSWaylandRoleToplevel) {
        [self updatePlasmaSurface];
        [_waylandConnection flush];
    }
    return kCGSErrorSuccess;
}

- (CGError) setRegion: (CGSRegionRef) region {
    if (region == NULL)
        return kCGErrorIllegalArgument;

    CGRect rect;
    CGSRegionToRect(region, &rect);
    if (!(rect.size.width >= 1) || !(rect.size.height >= 1))
        return kCGErrorIllegalArgument;

    if (!CGPointEqualToPoint(rect.origin, _frame.origin)) {
        // A resize that also moves would otherwise silently apply half of what was asked.
        if ([self moveTo: &rect.origin] != kCGSErrorSuccess)
            return kCGErrorNotImplemented;
    }

    if (!CGSizeEqualToSize(rect.size, _frame.size)) {
        _frame.size = rect.size;
        [_surfaceObject windowResizedTo: rect.size];
        [self resizeContentsTo: rect.size];
    }
    return kCGSErrorSuccess;
}

- (CGError) getRect: (CGRect *) outRect {
    if (outRect == NULL)
        return kCGErrorIllegalArgument;
    if (_ui) {
        // The UI layer's frame (y up) as the list of windows has it: y down from the top of the main display.
        CGFloat top = CGDisplayBounds(CGMainDisplayID()).size.height;
        *outRect = CGRectMake(_uiFrame.origin.x, top - CGRectGetMaxY(_uiFrame), _uiFrame.size.width,
                              _uiFrame.size.height);
        return kCGSErrorSuccess;
    }
    // The size is the compositor's; the origin is the one that was requested,
    // because Wayland never tells a client where its toplevel ended up.
    *outRect = _frame;
    return kCGSErrorSuccess;
}

- (CGError) setProperty: (CFStringRef) key value: (CFTypeRef) value {
    if (key != NULL && CFStringCompare(key, kCGSWindowTitle, 0) == kCFCompareEqualTo) {
        NSString *title = (NSString *) value;
        if (value != NULL && ![title isKindOfClass: [NSString class]])
            return kCGErrorTypeCheck;

        [_title release];
        _title = [title copy];

        if (_toplevel != NULL) {
            union wl_argument args[1] = {{.s = _title ? [_title UTF8String] : ""}};
            WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
            [_waylandConnection flush];
        }
        return kCGSErrorSuccess;
    }

    NSLog(@"CoreGraphics Wayland backend: window property %@ is not supported",
          (NSString *) key);
    return kCGErrorNotImplemented;
}

- (CGError) getProperty: (CFStringRef) key value: (CFTypeRef *) value {
    if (value == NULL)
        return kCGErrorIllegalArgument;

    if (key != NULL && CFStringCompare(key, kCGSWindowTitle, 0) == kCFCompareEqualTo) {
        *value = _title ? CFRetain((CFTypeRef) _title) : NULL;
        return kCGSErrorSuccess;
    }
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelContentContainsSurfacePoint: (CGPoint) point {
    if (!_ui || (_uiContentOffset.x == 0 && _uiContentOffset.y == 0))
        return YES;
    return point.x >= _uiContentOffset.x && point.y >= _uiContentOffset.y &&
           point.x < _uiContentOffset.x + _uiFrame.size.width && point.y < _uiContentOffset.y + _uiFrame.size.height;
}

- (CGPoint) frameOrigin {
    return _frame.origin;
}

#pragma mark - Contents and style

- (void) bufferReleased: (struct wl_proxy *) buffer opcode: (uint32_t) opcode {
    if (opcode != WP_BUFFER_EV_RELEASE)
        return;
    [[_waylandConnection renderManager] bufferDestroyed: buffer];
    WaylandMarshal(buffer, WP_BUFFER_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                   (union wl_argument[1]) {{.o = NULL}});
    [_waylandConnection flush];
    // The reference -presentRect: took for the buffer
    [self release];
}

// A buffer is made for each presentation, from a shared memory file the contents are copied to, and
// destroyed once the compositor has released it.
- (void) presentRect: (CGRect) rect {
    if (_waylandConnection->_shm == NULL || _surface == NULL || ![self ensureRole])
        return;
    // A buffer follows the configure that answers the initial commit.
    if (_ui && !_uiConfigured)
        return;

    [self withContents: ^(const void *bytes, size_t rowBytes, CGSize size) {
        int width = (int) size.width, height = (int) size.height;
        int stride = width * 4;
        size_t length = (size_t) stride * (size_t) height;

        int fd = WaylandCreateAnonymousFile(length);
        if (fd < 0)
            return;
        void *data = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (data == MAP_FAILED) {
            close(fd);
            return;
        }
        for (int row = 0; row < height; row++)
            memcpy((uint8_t *) data + (size_t) row * stride, (const uint8_t *) bytes + row * rowBytes, stride);
        munmap(data, length);

        union wl_argument poolArgs[3] = {{.o = NULL}, {.h = fd}, {.i = (int32_t) length}};
        struct wl_proxy *pool = [_waylandConnection createObject: _waylandConnection->_shm
                                                          opcode: WP_SHM_CREATE_POOL
                                                       interface: &wl_shm_pool_interface
                                                       arguments: poolArgs
                                                            kind: CGSWaylandObjectNone
                                                          object: nil];
        close(fd);
        if (pool == NULL)
            return;

        BOOL opaque = !(_styleFlags & kCGSWindowStyleTransparent);
        union wl_argument bufferArgs[6] = {{.o = NULL}, {.i = 0}, {.i = width}, {.i = height},
                                           {.i = stride},
                                           {.u = opaque ? WP_SHM_FORMAT_XRGB8888 : WP_SHM_FORMAT_ARGB8888}};
        // The window is kept alive until the compositor releases the buffer
        struct wl_proxy *buffer = [_waylandConnection createObject: pool
                                                            opcode: WP_SHM_POOL_CREATE_BUFFER
                                                         interface: &wl_buffer_interface
                                                         arguments: bufferArgs
                                                              kind: CGSWaylandObjectBuffer
                                                            object: [self retain]];
        WaylandMarshal(pool, WP_SHM_POOL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
        if (buffer == NULL) {
            [self release];
            return;
        }

        union wl_argument attach[3] = {{.o = (struct wl_object *) buffer}, {.i = 0}, {.i = 0}};
        WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
        union wl_argument damage[4] = {{.i = 0}, {.i = 0}, {.i = width}, {.i = height}};
        WaylandMarshal(_surface, WP_SURFACE_DAMAGE, NULL, 0, damage);
        // The fifo barrier must be set before the commit that presents the frame.
        [[_waylandConnection renderManager] beginFrameForSurface: _surface buffer: buffer];
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        [_waylandConnection flush];
    }];
}

// The window of a program that draws into it is mapped by a blank buffer: white, or transparent for a
// window with the transparent style
- (void) _showBlankContentsIfNone {
    // What the window has drawn is shown again, as a window that was ordered out lost its buffer
    if ([self withContents: ^(const void *bytes, size_t rowBytes, CGSize size) {}]) {
        [self presentRect: CGRectMake(0, 0, _frame.size.width, _frame.size.height)];
        return;
    }

    size_t width = (size_t) _frame.size.width, height = (size_t) _frame.size.height;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef blank = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
            kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (blank == NULL)
        return;
    if (!(_styleFlags & kCGSWindowStyleTransparent)) {
        CGContextSetRGBFillColor(blank, 1, 1, 1, 1);
        CGContextFillRect(blank, CGRectMake(0, 0, width, height));
    }
    CGImageRef image = CGBitmapContextCreateImage(blank);
    CGContextRelease(blank);
    if (image != NULL) {
        [self drawImage: image atPoint: CGPointZero];
        CGImageRelease(image);
    }
}

- (CGError) setStyle: (uint32_t) styleFlags {
    if (_ui)
        return kCGErrorNotImplemented;
    uint32_t changed = _styleFlags ^ styleFlags;
    _usesContents = YES;
    [super setStyle: styleFlags];

    if (changed & kCGSWindowStyleIgnoresMouse) {
        // An empty input region lets pointer input reach the surfaces below; no region restores the default.
        struct wl_proxy *region = NULL;
        if (styleFlags & kCGSWindowStyleIgnoresMouse) {
            union wl_argument regionArgs[1] = {{.o = NULL}};
            region = [_waylandConnection createObject: _waylandConnection->_compositor
                                               opcode: WP_COMPOSITOR_CREATE_REGION
                                            interface: &wl_region_interface
                                            arguments: regionArgs
                                                 kind: CGSWaylandObjectNone
                                               object: nil];
        }
        union wl_argument inputArgs[1] = {{.o = (struct wl_object *) region}};
        WaylandMarshal(_surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, inputArgs);
        if (region != NULL)
            WaylandMarshal(region, WP_REGION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                           (union wl_argument[1]) {{.o = NULL}});
    }

    if (_role == CGSWaylandRoleToplevel) {
        [self applyToplevelStyle: changed];
        if (changed & (kCGSWindowStyleFloating | kCGSWindowStyleUtility)) {
            [self updateLevelParent];
            [self updatePlasmaSurface];
        }
    }
    // The other styles (borderless, no focus, unmanaged) leave the compositor nothing to ask.
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

- (CGError) setLevel: (CGWindowLevel) level {
    if (_ui)
        return kCGErrorNotImplemented;
    CGWindowLevel previous = _level;
    [super setLevel: level];
    if (_role == CGSWaylandRoleNone || level == previous)
        return kCGSErrorSuccess;
    // The role of a surface is permanent, so the level can only change what a toplevel is related to
    if (_role == CGSWaylandRoleToplevel) {
        [self updateLevelParent];
        [_waylandConnection flush];
    } else if (_role == CGSWaylandRoleLayer ? level != kCGMainMenuWindowLevel
                                            : level <= kCGMainMenuWindowLevel) {
        NSLog(@"CoreGraphics Wayland backend: window %d was shown as a %s, the level %d would make it "
              @"something else", (int) self.windowId, _role == CGSWaylandRoleLayer ? "menu bar" : "popup",
              (int) level);
    }
    return kCGSErrorSuccess;
}

@end
