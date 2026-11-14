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
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"

#import <CoreGraphics/CGSSurface.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

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

    args[0].o = NULL;
    args[1].o = (struct wl_object *) _surface;
    _xdgSurface = [_waylandConnection createObject: _waylandConnection->_wmBase
                                            opcode: WP_WM_BASE_GET_XDG_SURFACE
                                         interface: &xdg_surface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectXdgSurface
                                            object: self];
    if (_xdgSurface == NULL) {
        [self release];
        return nil;
    }

    args[0].o = NULL;
    _toplevel = [_waylandConnection createObject: _xdgSurface
                                          opcode: WP_XDG_SURFACE_GET_TOPLEVEL
                                       interface: &xdg_toplevel_interface
                                       arguments: args
                                            kind: CGSWaylandObjectToplevel
                                          object: self];
    if (_toplevel == NULL) {
        [self release];
        return nil;
    }

    // The initial commit carries no buffer: the compositor answers with a
    // configure, and the first buffer maps the window.
    union wl_argument none[1] = {{.o = NULL}};
    WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
    if (WL.wl_display_roundtrip(_waylandConnection->_wlDisplay) < 0) {
        NSLog(@"CoreGraphics Wayland backend: the connection failed while "
              @"creating a window (error %d)",
              WL.wl_display_get_error(_waylandConnection->_wlDisplay));
        [self release];
        return nil;
    }
    return self;
}

- (void) dealloc {
    // The surface's wl_egl_window references our wl_surface, so it has to go
    // first; -[CGSWindow dealloc] would only release _surfaces after this body.
    @synchronized (_surfaces) {
        [_surfaces removeAllObjects];
    }
    _surfaceObject = nil;

    [_title release];
    if (_toplevel != NULL)
        WaylandMarshal(_toplevel, WP_TOPLEVEL_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    if (_xdgSurface != NULL)
        WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_DESTROY, NULL,
                       WL_MARSHAL_FLAG_DESTROY, (union wl_argument[1]) {{.o = NULL}});
    if (_surface != NULL)
        WaylandMarshal(_surface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    [_waylandConnection flush];
    [super dealloc];
}

- (void) surfaceDestroyed: (CGSSurfaceWayland *) surface {
    if (_surfaceObject == surface)
        _surfaceObject = nil;
}

#pragma mark - Events

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
           arguments: (union wl_argument *) args
{
    if (kind == CGSWaylandObjectXdgSurface) {
        if (opcode == WP_XDG_SURFACE_EV_CONFIGURE) {
            union wl_argument ack[1] = {{.u = args[0].u}};
            WaylandMarshal(_xdgSurface, WP_XDG_SURFACE_ACK_CONFIGURE, NULL, 0, ack);
            [_waylandConnection flush];
        }
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
            }
        }
    } else if (opcode == WP_TOPLEVEL_EV_CLOSE) {
        // CGS has no way to deliver a close request to whoever created the
        // window, so this is reported rather than acted on.
        NSLog(@"CoreGraphics Wayland backend: the compositor asked window %d to "
              @"close; CGS has no close notification to deliver",
              (int) self.windowId);
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
        // Attaching a null buffer unmaps the toplevel, which also returns the
        // xdg_surface to the unconfigured state. xdg-shell then requires the
        // initial commit procedure again before the next buffer, so the empty
        // commit and the wait for its configure happen here rather than leaving
        // the next eglSwapBuffers to attach into an unconfigured surface.
        union wl_argument attach[3] = {{.o = NULL}, {.i = 0}, {.i = 0}};
        union wl_argument none[1] = {{.o = NULL}};
        WaylandMarshal(_surface, WP_SURFACE_ATTACH, NULL, 0, attach);
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        WaylandMarshal(_surface, WP_SURFACE_COMMIT, NULL, 0, none);
        if (WL.wl_display_roundtrip(_waylandConnection->_wlDisplay) < 0) {
            NSLog(@"CoreGraphics Wayland backend: the connection failed while "
                  @"hiding window %d", (int) self.windowId);
            return kCGErrorFailure;
        }
        return kCGSErrorSuccess;
    }

    case kCGSOrderIn:
    case kCGSOrderAbove:
        // A toplevel is mapped by its first committed buffer, so there is
        // nothing to send here: the window appears when its surface swaps.
        return kCGSErrorSuccess;

    case kCGSOrderBelow:
    default:
        NSLog(@"CoreGraphics Wayland backend: window ordering mode %d is not "
              @"available on Wayland", (int) place);
        return kCGErrorNotImplemented;
    }
}

- (CGError) moveTo: (const CGPoint *) point {
    // A Wayland client cannot place its own toplevels; xdg_toplevel.move only
    // starts an interactive drag, which is not what this asks for.
    return kCGErrorNotImplemented;
}

- (CGError) setRegion: (CGSRegionRef) region {
    if (region == NULL)
        return kCGErrorIllegalArgument;

    CGRect rect;
    CGSRegionToRect(region, &rect);
    if (!(rect.size.width >= 1) || !(rect.size.height >= 1))
        return kCGErrorIllegalArgument;

    if (!CGPointEqualToPoint(rect.origin, _frame.origin)) {
        // Moving is refused outright (see -moveTo:); a resize that also moves
        // would otherwise silently apply half of what was asked.
        return kCGErrorNotImplemented;
    }

    if (!CGSizeEqualToSize(rect.size, _frame.size)) {
        _frame.size = rect.size;
        [_surfaceObject windowResizedTo: rect.size];
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

        union wl_argument args[1] = {{.s = _title ? [_title UTF8String] : ""}};
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_TITLE, NULL, 0, args);
        [_waylandConnection flush];
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

@end
