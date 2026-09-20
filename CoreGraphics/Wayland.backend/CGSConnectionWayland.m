/* CoreGraphics Wayland backend: the window-server connection.

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

#import "CGSConnectionWayland.h"
#import "CGSWindowWayland.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"

#import <CoreGraphics/CGSScreen.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#include <poll.h>
#include <stdlib.h>
#include <string.h>

// One wl_output and the state its events accumulate until wl_output.done.
@interface CGSWaylandOutput : NSObject {
@public
    CGSConnectionWayland *_connection; // Not retained; it outlives its outputs.
    struct wl_proxy *_proxy;
    uint32_t _name;
    int32_t _x, _y;
    int32_t _width, _height;
    int32_t _refresh; // mHz
    BOOL _haveMode;
}
@end

@implementation CGSWaylandOutput
@end

static int CGSWaylandDispatch(const void *kind, void *proxy, uint32_t opcode,
                              const struct wl_message *message,
                              union wl_argument *args)
{
    id object = (id) WL.wl_proxy_get_user_data(proxy);
    CGSWaylandObjectKind objectKind = (CGSWaylandObjectKind) (uintptr_t) kind;

    // An exception can't unwind through libwayland's native frames.
    @autoreleasepool {
        @try {
            switch (objectKind) {
            case CGSWaylandObjectXdgSurface:
            case CGSWaylandObjectToplevel:
                [(CGSWindowWayland *) object handleEvent: opcode
                                                    kind: objectKind
                                               arguments: args];
                break;
            case CGSWaylandObjectOutput:
                [((CGSWaylandOutput *) object)->_connection handleEvent: opcode
                                                                   kind: objectKind
                                                                 object: object
                                                              arguments: args];
                break;
            default:
                [(CGSConnectionWayland *) object handleEvent: opcode
                                                        kind: objectKind
                                                      object: object
                                                   arguments: args];
                break;
            }
        } @catch (NSException *exception) {
            NSLog(@"CoreGraphics Wayland backend: exception while handling an "
                  @"event: %@", exception);
        }
    }
    return 0;
}

@interface CGSConnectionWayland ()
- (void) processPendingEvents;
@end

static void socketCallback(CFSocketRef socket, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info)
{
    [(CGSConnectionWayland *) info processPendingEvents];
}

@implementation CGSConnectionWayland

+ (BOOL) isAvailable {
    // CGS.m selects by NSPriority alone, with no variable of its own; gating on
    // AppKit's keeps both frameworks on the same display server.
    const char *requested = getenv("DARLING_APPKIT_BACKEND");
    if (requested == NULL || strcasecmp(requested, "wayland") != 0)
        return NO;
    if (getenv("WAYLAND_DISPLAY") == NULL) {
        NSLog(@"CoreGraphics Wayland backend: DARLING_APPKIT_BACKEND=wayland "
              @"but WAYLAND_DISPLAY is unset");
        return NO;
    }
    return YES;
}

- (instancetype) initWithConnectionID: (CGSConnectionID) connId {
    if (!WaylandLibraryLoad() || !WaylandCheckOpcodes()) {
        NSLog(@"CoreGraphics Wayland backend: unavailable, trying the next "
              @"backend");
        [self release];
        return nil;
    }

    self = [super initWithConnectionID: connId];
    if (self == nil)
        return nil;

    _outputs = [NSMutableArray new];

    _wlDisplay = WL.wl_display_connect(NULL);
    if (_wlDisplay == NULL) {
        const char *name = getenv("WAYLAND_DISPLAY");
        NSLog(@"CoreGraphics Wayland backend: cannot connect to the compositor "
              @"(WAYLAND_DISPLAY=%s)", name ? name : "unset");
        [self release];
        return nil;
    }

    union wl_argument args[1] = {{.o = NULL}};
    _registry = [self createObject: (struct wl_proxy *) _wlDisplay
                            opcode: WP_DISPLAY_GET_REGISTRY
                         interface: &wl_registry_interface
                         arguments: args
                              kind: CGSWaylandObjectRegistry
                            object: self];
    if (_registry == NULL) {
        [self release];
        return nil;
    }

    // The first roundtrip delivers the globals, the second the initial events
    // of the objects bound meanwhile (output geometry and modes).
    if (WL.wl_display_roundtrip(_wlDisplay) < 0 ||
        WL.wl_display_roundtrip(_wlDisplay) < 0)
    {
        NSLog(@"CoreGraphics Wayland backend: the compositor connection failed "
              @"during setup (error %d)", WL.wl_display_get_error(_wlDisplay));
        [self release];
        return nil;
    }

    if (_compositor == NULL || _wmBase == NULL) {
        NSLog(@"CoreGraphics Wayland backend: the compositor lacks%s%s",
              _compositor ? "" : " wl_compositor", _wmBase ? "" : " xdg_wm_base");
        [self release];
        return nil;
    }

    CFSocketContext context = {.version = 0, .info = self};
    _cfSocket = CFSocketCreateWithNative(kCFAllocatorDefault,
                                         WL.wl_display_get_fd(_wlDisplay),
                                         kCFSocketReadCallBack, socketCallback,
                                         &context);
    if (_cfSocket != NULL) {
        // The descriptor belongs to libwayland.
        CFSocketSetSocketFlags(_cfSocket, CFSocketGetSocketFlags(_cfSocket) &
                                                  ~kCFSocketCloseOnInvalidate);
        _source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocket, 0);
    }
    if (_source == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot watch the compositor "
              @"connection");
        [self release];
        return nil;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

    [self flush];
    NSLog(@"CoreGraphics Wayland backend: connected, %lu output(s)",
          (unsigned long) [_outputs count]);
    return self;
}

- (void) dealloc {
    // Windows destroy wl_proxies and flush, so they have to go while the
    // display is still connected; -[CGSConnection dealloc] releases _windows
    // only after this body runs.
    @synchronized (_windows) {
        [_windows removeAllObjects];
    }

    if (_source != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
    }
    if (_cfSocket != NULL) {
        CFSocketInvalidate(_cfSocket);
        CFRelease(_cfSocket);
    }

    for (CGSWaylandOutput *output in _outputs)
        WL.wl_proxy_destroy(output->_proxy);
    [_outputs release];
    [_screens release];

    if (_wlDisplay != NULL) {
        WL.wl_display_disconnect(_wlDisplay);
        _wlDisplay = NULL;
    }

    [super dealloc];
}

#pragma mark - Wayland plumbing

- (struct wl_proxy *) createObject: (struct wl_proxy *) proxy
                            opcode: (uint32_t) opcode
                         interface: (const struct wl_interface *) interface
                         arguments: (union wl_argument *) args
                              kind: (CGSWaylandObjectKind) kind
                            object: (id) object
{
    struct wl_proxy *created = WaylandMarshal(proxy, opcode, interface, 0, args);
    if (created == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot create a %s",
              interface->name);
        return NULL;
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(created, CGSWaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return created;
}

- (struct wl_proxy *) bindGlobal: (uint32_t) name
                       interface: (const struct wl_interface *) interface
                         version: (uint32_t) version
                            kind: (CGSWaylandObjectKind) kind
                          object: (id) object
{
    union wl_argument args[4] = {
            {.u = name}, {.s = interface->name}, {.u = version}, {.o = NULL}};
    struct wl_proxy *proxy = WL.wl_proxy_marshal_array_flags(
            _registry, WP_REGISTRY_BIND, interface, version, 0, args);
    if (proxy == NULL) {
        NSLog(@"CoreGraphics Wayland backend: cannot bind %s", interface->name);
        return NULL;
    }
    if (kind != 0)
        WL.wl_proxy_add_dispatcher(proxy, CGSWaylandDispatch,
                                   (void *) (uintptr_t) kind, object);
    return proxy;
}

- (void) flush {
    if (_wlDisplay != NULL)
        WL.wl_display_flush(_wlDisplay);
}

- (void) connectionFailed {
    // Matches AppKit's backend: a lost compositor connection leaves every proxy
    // unusable, and there is nothing to fall back to at this point.
    NSLog(@"CoreGraphics Wayland backend: lost the connection to the compositor "
          @"(error %d)", WL.wl_display_get_error(_wlDisplay));
    exit(1);
}

- (void) processPendingEvents {
    if (_wlDisplay == NULL)
        return;

    while (WL.wl_display_prepare_read(_wlDisplay) != 0) {
        if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
            [self connectionFailed];
    }
    WL.wl_display_flush(_wlDisplay);

    struct pollfd pfd = {.fd = WL.wl_display_get_fd(_wlDisplay), .events = POLLIN};
    if (poll(&pfd, 1, 0) > 0) {
        if (WL.wl_display_read_events(_wlDisplay) < 0)
            [self connectionFailed];
    } else {
        WL.wl_display_cancel_read(_wlDisplay);
    }

    if (WL.wl_display_dispatch_pending(_wlDisplay) < 0)
        [self connectionFailed];

    WL.wl_display_flush(_wlDisplay);
}

#pragma mark - Events

- (void) registryGlobal: (uint32_t) name
              interface: (const char *) interface
                version: (uint32_t) version
{
    if (strcmp(interface, "wl_compositor") == 0 && _compositor == NULL) {
        _compositor = [self bindGlobal: name interface: &wl_compositor_interface
                               version: MIN(version, 4u)
                                   kind: CGSWaylandObjectNone object: nil];
    } else if (strcmp(interface, "xdg_wm_base") == 0 && _wmBase == NULL) {
        _wmBase = [self bindGlobal: name interface: &xdg_wm_base_interface
                           version: MIN(version, 2u)
                              kind: CGSWaylandObjectWmBase object: self];
    } else if (strcmp(interface, "wl_output") == 0) {
        CGSWaylandOutput *output = [CGSWaylandOutput new];
        output->_connection = self;
        output->_name = name;
        output->_proxy = [self bindGlobal: name interface: &wl_output_interface
                                  version: MIN(version, 2u)
                                     kind: CGSWaylandObjectOutput object: output];
        if (output->_proxy == NULL) {
            [output release];
            return;
        }
        @synchronized (self) {
            [_outputs addObject: output];
            [_screens release];
            _screens = nil;
        }
        [output release];
    }
}

- (void) registryGlobalRemove: (uint32_t) name {
    @synchronized (self) {
        for (NSUInteger i = 0; i < [_outputs count]; i++) {
            CGSWaylandOutput *output = [_outputs objectAtIndex: i];
            if (output->_name != name)
                continue;
            WL.wl_proxy_destroy(output->_proxy);
            [_outputs removeObjectAtIndex: i];
            [_screens release];
            _screens = nil;
            return;
        }
    }
}

// -createScreens reads _outputs under the same lock, and it can be called from
// any thread while events arrive on the run loop thread.
- (void) invalidateScreens {
    @synchronized (self) {
        [_screens release];
        _screens = nil;
    }
}

- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
              object: (id) object
           arguments: (union wl_argument *) args
{
    switch (kind) {
    case CGSWaylandObjectRegistry:
        if (opcode == WP_REGISTRY_EV_GLOBAL)
            [self registryGlobal: args[0].u interface: args[1].s version: args[2].u];
        else if (opcode == WP_REGISTRY_EV_GLOBAL_REMOVE)
            [self registryGlobalRemove: args[0].u];
        break;

    case CGSWaylandObjectWmBase:
        if (opcode == WP_WM_BASE_EV_PING) {
            union wl_argument pong[1] = {{.u = args[0].u}};
            WaylandMarshal(_wmBase, WP_WM_BASE_PONG, NULL, 0, pong);
            [self flush];
        }
        break;

    case CGSWaylandObjectOutput: {
        CGSWaylandOutput *output = (CGSWaylandOutput *) object;
        if (opcode == WP_OUTPUT_EV_GEOMETRY) {
            output->_x = args[0].i;
            output->_y = args[1].i;
        } else if (opcode == WP_OUTPUT_EV_MODE &&
                   (args[0].u & WP_OUTPUT_MODE_CURRENT) != 0) {
            output->_width = args[1].i;
            output->_height = args[2].i;
            output->_refresh = args[3].i;
            output->_haveMode = YES;
        } else if (opcode == WP_OUTPUT_EV_DONE) {
            [self invalidateScreens];
        }
        break;
    }

    default:
        break;
    }
}

#pragma mark - CGSConnection

- (void *) nativeDisplay {
    // EGLNativeDisplayType on Wayland is the wl_display.
    return _wlDisplay;
}

- (CGPoint) mouseLocation {
    // Wayland reports the pointer only through wl_pointer events over a client's
    // own surfaces, which these are not. A made-up origin would be
    // indistinguishable from a real one, so this is CGEventObjC.m's sentinel.
    static BOOL warned;
    if (!warned) {
        warned = YES;
        NSLog(@"CoreGraphics Wayland backend: the pointer position is not "
              @"available to Wayland clients; CGEventGetLocation() has no value "
              @"to report");
    }
    return CGPointMake(CGFLOAT_MAX, CGFLOAT_MAX);
}

- (NSArray<CGSScreen *> *) createScreens {
    @synchronized (self) {
        if (_screens == nil) {
            NSMutableArray *screens = [NSMutableArray array];
            for (CGSWaylandOutput *output in _outputs) {
                if (!output->_haveMode)
                    continue;
                NSDictionary *mode = @{
                    @"Width": @(output->_width),
                    @"Height": @(output->_height),
                    // wl_output reports mHz; CGDisplayModeGetRefreshRate is Hz.
                    @"RefreshRate": @(output->_refresh / 1000.0),
                    @"OriginX": @(output->_x),
                    @"OriginY": @(output->_y),
                };
                CGSScreen *screen = [CGSScreen new];
                screen.modes = @[mode];
                screen.currentMode = 0;
                [screens addObject: screen];
                [screen release];
            }
            // CGEventGetUnflippedLocation reads nil as "no answer", so no usable
            // output stays nil rather than claiming a screenless desktop.
            if ([screens count] > 0)
                _screens = [screens copy];
        }
        return [_screens retain];
    }
}

- (CGSWindow *) newWindow: (CGSRegionRef) region {
    CGSWindowID windowID = _nextWindowId++;
    CGSWindowWayland *window =
            [[CGSWindowWayland alloc] initWithRegion: region
                                          connection: self
                                            windowID: windowID];
    if (window == nil)
        return nil;

    @synchronized (_windows) {
        [_windows setObject: window forKey: [NSNumber numberWithInt: windowID]];
    }
    [window release];
    return window;
}

@end
