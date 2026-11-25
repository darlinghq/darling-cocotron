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

#import "CGSWaylandOutputManager.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <time.h>

@class CGSWaylandOutputHead;

@interface CGSWaylandOutputManager ()
- (void) headFinished: (CGSWaylandOutputHead *) head;
- (void) attachDispatcherTo: (struct wl_proxy *) proxy kind: (CGSWaylandObjectKind) kind object: (id) object;
@end

@interface CGSWaylandOutputHeadMode : NSObject <CGSWaylandOutputManagementEvents> {
@public
    struct wl_proxy *_proxy;
    int32_t _width, _height, _refresh;
}
@end

@interface CGSWaylandOutputHead : NSObject <CGSWaylandOutputManagementEvents> {
@public
    struct wl_proxy *_proxy;
    CGSWaylandOutputManager *_manager;
    NSMutableArray *_modes;
    CGSWaylandOutputHeadMode *_current;
    BOOL _enabled;
    int32_t _x, _y, _transform, _scale;
}
@end

// Result of a test or apply request.
@interface CGSWaylandOutputConfiguration : NSObject <CGSWaylandOutputManagementEvents> {
@public
    int _result; // 0 pending, 1 succeeded, 2 failed, 3 cancelled
}
@end

@implementation CGSWaylandOutputHeadMode
- (void) handleEvent: (uint32_t) opcode kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_WLR_MODE_EV_SIZE:
        _width = args[0].i;
        _height = args[1].i;
        break;
    case WP_WLR_MODE_EV_REFRESH:
        _refresh = args[0].i;
        break;
    default:
        break;
    }
}
@end

@implementation CGSWaylandOutputConfiguration
- (void) handleEvent: (uint32_t) opcode kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_WLR_CONFIGURATION_EV_SUCCEEDED: _result = 1; break;
    case WP_WLR_CONFIGURATION_EV_FAILED: _result = 2; break;
    case WP_WLR_CONFIGURATION_EV_CANCELLED: _result = 3; break;
    default: break;
    }
}
@end

@implementation CGSWaylandOutputHead

- (instancetype) init {
    if ((self = [super init]))
        _modes = [NSMutableArray new];
    return self;
}

- (void) dealloc {
    [_modes release];
    [super dealloc];
}

- (void) handleEvent: (uint32_t) opcode kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_WLR_HEAD_EV_MODE: {
        CGSWaylandOutputHeadMode *mode = [[CGSWaylandOutputHeadMode new] autorelease];
        mode->_proxy = (struct wl_proxy *) args[0].o;
        [_manager attachDispatcherTo: mode->_proxy kind: CGSWaylandObjectOutputHeadMode object: mode];
        [_modes addObject: mode];
        break;
    }
    case WP_WLR_HEAD_EV_ENABLED:
        _enabled = args[0].i != 0;
        break;
    case WP_WLR_HEAD_EV_CURRENT_MODE:
        _current = args[0].o ? (CGSWaylandOutputHeadMode *) WL.wl_proxy_get_user_data((struct wl_proxy *) args[0].o) : nil;
        break;
    case WP_WLR_HEAD_EV_POSITION:
        _x = args[0].i;
        _y = args[1].i;
        break;
    case WP_WLR_HEAD_EV_TRANSFORM:
        _transform = args[0].i;
        break;
    case WP_WLR_HEAD_EV_SCALE:
        _scale = args[0].i;
        break;
    case WP_WLR_HEAD_EV_FINISHED:
        [_manager headFinished: self];
        break;
    default:
        break;
    }
}

@end

@implementation CGSWaylandOutputManager

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection manager: (struct wl_proxy *) manager {
    if ((self = [super init])) {
        _connection = connection; // Not retained: the connection owns the manager.
        _proxy = manager;
        _heads = [NSMutableArray new];
    }
    return self;
}

- (void) dealloc {
    [self stop];
    [_heads release];
    [super dealloc];
}

// The dispatcher of the connection for an object the compositor created with an event.
- (void) attachDispatcherTo: (struct wl_proxy *) proxy kind: (CGSWaylandObjectKind) kind object: (id) object {
    [_connection attachDispatcherTo: proxy kind: kind object: object];
}

- (void) stop {
    if (_proxy == NULL)
        return;
    for (CGSWaylandOutputHead *head in _heads) {
        for (CGSWaylandOutputHeadMode *mode in head->_modes)
            WL.wl_proxy_destroy(mode->_proxy);
        WL.wl_proxy_destroy(head->_proxy);
    }
    [_heads removeAllObjects];
    if (!_stopped)
        WaylandMarshal(_proxy, WP_WLR_MANAGER_STOP, NULL, 0, NULL);
    WL.wl_proxy_destroy(_proxy);
    _proxy = NULL;
}

- (void) headFinished: (CGSWaylandOutputHead *) head {
    for (CGSWaylandOutputHeadMode *mode in head->_modes)
        WL.wl_proxy_destroy(mode->_proxy);
    WL.wl_proxy_destroy(head->_proxy);
    [_heads removeObject: head];
}

- (void) handleEvent: (uint32_t) opcode kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args
{
    switch (opcode) {
    case WP_WLR_MANAGER_EV_HEAD: {
        CGSWaylandOutputHead *head = [[CGSWaylandOutputHead new] autorelease];
        head->_manager = self;
        head->_proxy = (struct wl_proxy *) args[0].o;
        [self attachDispatcherTo: head->_proxy kind: CGSWaylandObjectOutputHead object: head];
        [_heads addObject: head];
        break;
    }
    case WP_WLR_MANAGER_EV_DONE:
        _serial = args[0].u;
        break;
    case WP_WLR_MANAGER_EV_FINISHED:
        _stopped = YES;
        break;
    default:
        break;
    }
}

// The head of the wl_output at x, y with the given current size: heads are
// matched by position in the compositor's layout, then by current size;
// a single enabled head is the one when nothing else tells them apart.
- (CGSWaylandOutputHead *) headAtX: (int) x y: (int) y width: (int) width height: (int) height {
    CGSWaylandOutputHead *byPosition = nil, *only = nil;
    int enabledCount = 0;
    for (CGSWaylandOutputHead *head in _heads) {
        if (!head->_enabled || head->_current == nil)
            continue;
        enabledCount++;
        only = head;
        if (head->_x == x && head->_y == y) {
            if (head->_current->_width == width && head->_current->_height == height)
                return head;
            if (byPosition == nil)
                byPosition = head;
        }
    }
    return byPosition ?: (enabledCount == 1 ? only : nil);
}

- (NSArray *) modesForOutputAtX: (int) x y: (int) y width: (int) width height: (int) height {
    CGSWaylandOutputHead *head = [self headAtX: x y: y width: width height: height];
    if (head == nil)
        return nil;
    NSMutableArray *modes = [NSMutableArray array];
    for (CGSWaylandOutputHeadMode *mode in head->_modes) {
        if (mode->_width <= 0 || mode->_height <= 0)
            continue;
        NSDictionary *dictionary = @{
            @"Width" : @(mode->_width),
            @"Height" : @(mode->_height),
            @"Depth" : @(24),
            @"RefreshRate" : @(mode->_refresh / 1000.0)
        };
        if (![modes containsObject: dictionary])
            [modes addObject: dictionary];
    }
    return modes;
}

// Describes every head, with `mode` for `target`, in a new configuration and
// sends request (test or apply). Returns the configuration's outcome:
// 1 succeeded, 2 failed, 3 cancelled (state changed), 0 no answer.
- (int) configureHead: (CGSWaylandOutputHead *) target mode: (CGSWaylandOutputHeadMode *) mode request: (uint32_t) request {
    CGSWaylandOutputConfiguration *configuration = [[CGSWaylandOutputConfiguration new] autorelease];
    union wl_argument createArgs[] = {{.o = NULL}, {.u = _serial}};
    struct wl_proxy *configProxy = [_connection createObject: _proxy
                                                      opcode: WP_WLR_MANAGER_CREATE_CONFIGURATION
                                                   interface: &zwlr_output_configuration_v1_interface
                                                   arguments: createArgs
                                                        kind: CGSWaylandObjectOutputConfiguration
                                                      object: configuration];
    NSMutableArray *headConfigs = [NSMutableArray array];

    for (CGSWaylandOutputHead *head in _heads) {
        if (!head->_enabled || head->_current == nil) {
            union wl_argument disable[] = {{.o = (struct wl_object *) head->_proxy}};
            WaylandMarshal(configProxy, WP_WLR_CONFIGURATION_DISABLE_HEAD, NULL, 0, disable);
            continue;
        }
        union wl_argument enable[] = {{.o = NULL}, {.o = (struct wl_object *) head->_proxy}};
        struct wl_proxy *headConfig = WaylandMarshal(configProxy, WP_WLR_CONFIGURATION_ENABLE_HEAD,
                                                     &zwlr_output_configuration_head_v1_interface, 0, enable);
        [headConfigs addObject: [NSValue valueWithPointer: headConfig]];
        // Everything is stated, so that nothing depends on what the compositor keeps for omitted properties.
        union wl_argument setMode[] = {{.o = (struct wl_object *) (head == target ? mode : head->_current)->_proxy}};
        WaylandMarshal(headConfig, WP_WLR_CONFIGURATION_HEAD_SET_MODE, NULL, 0, setMode);
        union wl_argument position[] = {{.i = head->_x}, {.i = head->_y}};
        WaylandMarshal(headConfig, WP_WLR_CONFIGURATION_HEAD_SET_POSITION, NULL, 0, position);
        union wl_argument transform[] = {{.i = head->_transform}};
        WaylandMarshal(headConfig, WP_WLR_CONFIGURATION_HEAD_SET_TRANSFORM, NULL, 0, transform);
        union wl_argument scale[] = {{.f = head->_scale}};
        WaylandMarshal(headConfig, WP_WLR_CONFIGURATION_HEAD_SET_SCALE, NULL, 0, scale);
    }
    WaylandMarshal(configProxy, request, NULL, 0, NULL);

    // The answer comes with the next events; the compositor may take a few round trips.
    for (int i = 0; i < 400 && configuration->_result == 0; i++) {
        if (WL.wl_display_roundtrip(_connection->_wlDisplay) < 0)
            break;
        if (configuration->_result == 0) {
            struct timespec pause = {0, 5 * 1000 * 1000};
            nanosleep(&pause, NULL);
        }
    }
    int result = configuration->_result;
    WaylandMarshal(configProxy, WP_WLR_CONFIGURATION_DESTROY, NULL, WL_MARSHAL_FLAG_DESTROY, NULL);
    for (NSValue *value in headConfigs)
        WL.wl_proxy_destroy([value pointerValue]);
    return result;
}

- (BOOL) setModeWidth: (int) width height: (int) height refresh: (int) refresh
        forOutputAtX: (int) x y: (int) y currentWidth: (int) currentWidth currentHeight: (int) currentHeight
{
    if (_proxy == NULL)
        return NO;
    // A cancelled configuration means the state moved on while it was built:
    // the events that say so are dispatched meanwhile, so try again with them.
    for (int attempt = 0; attempt < 4; attempt++) {
        WL.wl_display_roundtrip(_connection->_wlDisplay);
        CGSWaylandOutputHead *head = [self headAtX: x y: y width: currentWidth height: currentHeight];
        if (head == nil)
            return NO;
        [[head retain] autorelease]; // a finished head leaves the list while we wait
        CGSWaylandOutputHeadMode *wanted = nil;
        for (CGSWaylandOutputHeadMode *mode in head->_modes) {
            if (mode->_width != width || mode->_height != height)
                continue;
            if (wanted == nil || abs(mode->_refresh - refresh) < abs(wanted->_refresh - refresh))
                wanted = mode;
        }
        if (wanted == nil)
            return NO;
        if (wanted == head->_current)
            return YES;

        int tested = [self configureHead: head mode: wanted request: WP_WLR_CONFIGURATION_TEST];
        if (tested == 3)
            continue;
        if (tested != 1)
            return NO;
        int applied = [self configureHead: head mode: wanted request: WP_WLR_CONFIGURATION_APPLY];
        if (applied == 3)
            continue;
        if (applied != 1)
            return NO;
        // The new state arrives as head and output events.
        for (int i = 0; i < 400 && head->_current != wanted; i++) {
            if (WL.wl_display_roundtrip(_connection->_wlDisplay) < 0)
                break;
            if (head->_current != wanted) {
                struct timespec pause = {0, 5 * 1000 * 1000};
                nanosleep(&pause, NULL);
            }
        }
        return head->_current == wanted;
    }
    return NO;
}

@end
