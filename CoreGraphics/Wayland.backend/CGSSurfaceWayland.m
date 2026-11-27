/* CoreGraphics Wayland backend: a window-server surface.

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

#import "CGSSurfaceWayland.h"
#import "CGSWindowWayland.h"
#import "WaylandLibrary.h"
#import "CGSConnectionWayland.h"
#import "WaylandProtocol.h"
#import "WaylandRender.h"

#import <Foundation/NSString.h>

// wl_surface.set_opaque_region and wl_region.add of the core protocol
enum { kSurfaceSetOpaqueRegion = 4, kRegionAdd = 1 };

@implementation CGSSurfaceWayland

// What GL draws is opaque whatever its alpha channel holds: the window's alpha is for the windows that ask for a
// translucent one, and the compositor would blend a GL window of drawn alpha below one with what is behind it
- (void) markOpaque {
    if (_ownSurface == NULL)
        return;
    CGSConnectionWayland *connection = _waylandWindow->_waylandConnection;
    union wl_argument regionArgs[1] = {{.o = NULL}};
    struct wl_proxy *region = [connection createObject: connection->_compositor
                                                opcode: WP_COMPOSITOR_CREATE_REGION
                                             interface: &wl_region_interface
                                             arguments: regionArgs
                                                  kind: CGSWaylandObjectNone
                                                object: nil];
    if (region == NULL)
        return;
    union wl_argument add[4] = {{.i = 0}, {.i = 0}, {.i = (int32_t) ceil(_size.width)}, {.i = (int32_t) ceil(_size.height)}};
    WaylandMarshal(region, kRegionAdd, NULL, 0, add);
    WaylandMarshal(_ownSurface, kSurfaceSetOpaqueRegion, NULL, 0, (union wl_argument[1]) {{.o = (struct wl_object *) region}});
    WaylandMarshal(region, WP_REGION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, (union wl_argument[1]) {{.o = NULL}});
}

- (instancetype) initWithWindow: (CGSWindow *) window
                      surfaceID: (CGSSurfaceID) surfaceID
{
    self = [super initWithWindow: window surfaceID: surfaceID];
    if (self == nil)
        return nil;

    _waylandWindow = (CGSWindowWayland *) window;

    if (!WL.hasEGL) {
        NSLog(@"CoreGraphics Wayland backend: libwayland-egl is unavailable, so "
              @"this window cannot be given a drawable surface");
        [self release];
        return nil;
    }

    CGRect frame;
    [_waylandWindow getRect: &frame];
    _size = frame.size;

    struct wl_proxy *drawn = _waylandWindow->_surface;
    CGSConnectionWayland *connection = _waylandWindow->_waylandConnection;
    if ([_waylandWindow role] == CGSWaylandRoleToplevel && connection->_subcompositor != NULL) {
        // The window's wl_surface keeps the window's contents; GL gets a subsurface of it.
        union wl_argument surfaceArgs[2] = {{.o = NULL}};
        _ownSurface = [connection createObject: connection->_compositor
                                        opcode: WP_COMPOSITOR_CREATE_SURFACE
                                     interface: &wl_surface_interface
                                     arguments: surfaceArgs
                                          kind: CGSWaylandObjectNone
                                        object: nil];
        if (_ownSurface != NULL) {
            union wl_argument args[3] = {{.o = NULL}, {.o = (struct wl_object *) _ownSurface},
                                         {.o = (struct wl_object *) _waylandWindow->_surface}};
            _subsurface = [connection createObject: connection->_subcompositor
                                            opcode: WP_SUBCOMPOSITOR_GET_SUBSURFACE
                                         interface: &wl_subsurface_interface
                                         arguments: args
                                              kind: CGSWaylandObjectNone
                                            object: nil];
        }
        if (_subsurface == NULL) {
            [self destroySubsurface];
            [self release];
            return nil;
        }
        // Its buffers go out when GL swaps, not with the commits of the window
        WaylandMarshal(_subsurface, WP_SUBSURFACE_SET_DESYNC, NULL, 0, (union wl_argument[1]) {{.o = NULL}});
        [[connection renderManager] observeSurface: _ownSurface];
        drawn = _ownSurface;
        [self markOpaque];
    }

    _eglWindow = WL.wl_egl_window_create(
            (struct wl_surface *) drawn,
            (int) _size.width, (int) _size.height);
    if (_eglWindow == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot create a %g x %g EGL window",
              _size.width, _size.height);
        [self release];
        return nil;
    }
    return self;
}

// The subsurface and its wl_surface, which the wl_egl_window has to be gone before
- (void) destroySubsurface {
    CGSConnectionWayland *connection = _waylandWindow->_waylandConnection;
    if (_subsurface != NULL)
        WaylandMarshal(_subsurface, WP_SUBSURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    if (_ownSurface != NULL) {
        [[connection renderManager] destroySurface: _ownSurface];
        WaylandMarshal(_ownSurface, WP_SURFACE_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                       (union wl_argument[1]) {{.o = NULL}});
    }
    _subsurface = NULL;
    _ownSurface = NULL;
    [connection flush];
}

- (void) dealloc {
    if (_eglWindow != NULL)
        WL.wl_egl_window_destroy(_eglWindow);
    [self destroySubsurface];
    [_waylandWindow surfaceDestroyed: self];
    [super dealloc];
}

- (void) windowResizedTo: (CGSize) size {
    // a subsurface is sized by its bounds
    if (_ownSurface != NULL)
        return;
    if (_eglWindow == NULL || CGSizeEqualToSize(size, _size))
        return;
    _size = size;
    WL.wl_egl_window_resize(_eglWindow, (int) size.width, (int) size.height, 0, 0);
}

- (CGError) setBounds: (CGRect) rect {
    if (!(rect.size.width >= 1) || !(rect.size.height >= 1))
        return kCGErrorIllegalArgument;

    if (_subsurface != NULL) {
        WaylandMarshal(_subsurface, WP_SUBSURFACE_SET_POSITION, NULL, 0,
                       (union wl_argument[2]) {{.i = (int32_t) rect.origin.x}, {.i = (int32_t) rect.origin.y}});
        _size = rect.size;
        WL.wl_egl_window_resize(_eglWindow, (int) rect.size.width, (int) rect.size.height, 0, 0);
        [self markOpaque];
        [self _boundsDidChange: rect];
        return kCGSErrorSuccess;
    }
    if (rect.origin.x != 0 || rect.origin.y != 0) {
        // Offsetting a surface inside its window needs a wl_subsurface of its
        // own, which this backend does not create (see -createSurface).
        NSLog(@"CoreGraphics Wayland backend: a surface offset within its "
              @"window is not implemented");
        return kCGErrorNotImplemented;
    }

    [self windowResizedTo: rect.size];
    [self _boundsDidChange: rect];
    return kCGSErrorSuccess;
}

- (void *) nativeWindow {
    return _eglWindow;
}

@end
