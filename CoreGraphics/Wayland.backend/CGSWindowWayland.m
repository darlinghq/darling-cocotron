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

#import <CoreGraphics/CGSSurface.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <sys/mman.h>
#include <unistd.h>
#include <string.h>

@implementation CGSWindowWayland

- (instancetype) initWithRegion: (CGSRegionRef) region
                     connection: (CGSConnection *) connection
                       windowID: (CGSWindowID) windowID
{
    self = [super initWithRegion: region connection: connection windowID: windowID];
    if (self == nil)
        return nil;

    _waylandConnection = (CGSConnectionWayland *) connection;
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

- (void) dealloc {
    // The surface's wl_egl_window references our wl_surface, so it has to go
    // first; -[CGSWindow dealloc] would only release _surfaces after this body.
    @synchronized (_surfaces) {
        [_surfaces removeAllObjects];
    }
    _surfaceObject = nil;

    [_title release];
    WaylandColorManager *color = [_waylandConnection colorManager];
    [color destroyColorSurface: _colorSurface];
    [color destroyRepresentationSurface: _representationSurface];
    _colorSurface = NULL;
    _representationSurface = NULL;
    [self destroyRole];
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
    if (_toplevel == NULL)
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
            _CGSPostWindowEvent(activated ? kCGSWindowEventActivated : kCGSWindowEventDeactivated,
                                self.windowId, CGRectNull);
        }
    } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
        _CGSPostWindowEvent(kCGSWindowEventCloseRequested, self.windowId, CGRectNull);
    }
}

#pragma mark - CGSWindow

- (void *) nativeWindow {
    return _surface;
}

- (CGSSurface *) createSurface {
    if (_surfaceObject != nil) {
        NSLog(@"CoreGraphics Wayland backend: window %d already has a surface; "
              @"more than one surface per window would need subsurfaces, which "
              @"are not implemented", (int) self.windowId);
        return nil;
    }

    if (![self ensureRole])
        return nil;
    CGSSurfaceID surfaceID = _nextSurfaceId++;
    CGSSurfaceWayland *surface =
            [[CGSSurfaceWayland alloc] initWithWindow: self surfaceID: surfaceID];
    if (surface == nil)
        return nil;

    @synchronized (_surfaces) {
        [_surfaces setObject: surface
                      forKey: [NSNumber numberWithInt: surfaceID]];
    }
    _surfaceObject = surface;
    [surface release];
    return surface;
}

- (CGError) orderWindow: (CGSWindowOrderingMode) place
             relativeTo: (CGSWindow *) window
{
    if (window != nil) {
        // Wayland gives a client no say in how its toplevels stack.
        NSLog(@"CoreGraphics Wayland backend: relative window ordering is not "
              @"available on Wayland");
        return kCGErrorNotImplemented;
    }

    switch (place) {
    case kCGSOrderOut: {
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
        _shown = YES;
        // A floating window that was shown before the window it floats over gets that parent now.
        if ([self isDocumentLike]) {
            NSArray *windows = [_waylandConnection copyAllWindows];
            for (CGSWindowWayland *window in windows)
                if (window != self && window->_role == CGSWaylandRoleToplevel)
                    [window updateLevelParent];
            [windows release];
        }
        // A toplevel is mapped by its first committed buffer. A window that a program draws into
        // shows its contents, or a blank window while it has drawn none; the others appear when
        // their surface swaps.
        if (_usesContents)
            [self _showBlankContentsIfNone];
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

- (CGPoint) frameOrigin {
    return _frame.origin;
}

#pragma mark - Contents and style

- (void) bufferReleased: (struct wl_proxy *) buffer opcode: (uint32_t) opcode {
    if (opcode != WP_BUFFER_EV_RELEASE)
        return;
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
