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
        // A toplevel is mapped by its first committed buffer. A window that a program draws into
        // shows its contents, or a blank window while it has drawn none; the others appear when
        // their surface swaps.
        if (_usesContents)
            [self _showBlankContentsIfNone];
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

    // An empty input region lets pointer input reach the surfaces below.
    union wl_argument regionArgs[1] = {{.o = NULL}};
    struct wl_proxy *region = [_waylandConnection createObject: _waylandConnection->_compositor
                                                        opcode: WP_COMPOSITOR_CREATE_REGION
                                                     interface: &wl_region_interface
                                                     arguments: regionArgs
                                                          kind: CGSWaylandObjectNone
                                                        object: nil];
    if (region == NULL)
        return kCGErrorFailure;
    union wl_argument inputArgs[1] = {{.o = (struct wl_object *) region}};
    WaylandMarshal(_surface, WP_SURFACE_SET_INPUT_REGION, NULL, 0, inputArgs);
    WaylandMarshal(region, WP_REGION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY,
                   (union wl_argument[1]) {{.o = NULL}});

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
    if (_waylandConnection->_shm == NULL || _surface == NULL)
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

    if (changed & kCGSWindowStyleFixedSize) {
        union wl_argument size[2] = {{.i = 0}, {.i = 0}};
        if (styleFlags & kCGSWindowStyleFixedSize) {
            size[0].i = (int32_t) _frame.size.width;
            size[1].i = (int32_t) _frame.size.height;
        }
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MIN_SIZE, NULL, 0, size);
        WaylandMarshal(_toplevel, WP_TOPLEVEL_SET_MAX_SIZE, NULL, 0, size);
    }

    // Floating (always on top), utility, borderless and unmanaged windows: a Wayland client has no
    // say in these, the compositor decides how toplevels are stacked and framed.
    [_waylandConnection flush];
    return kCGSErrorSuccess;
}

@end
