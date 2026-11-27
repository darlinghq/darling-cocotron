/* CoreGraphics Wayland backend: graphics tablets.

 Copyright (C) 2026 Lubos Dolezel

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

#import "CGSWaylandTablet.h"
#import "CGSConnectionWayland.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>
#include <math.h>

// Cocoa's pointing device types and tablet button mask are in CoreGraphicsPrivate.h.
#define TabletPointerTypeUnknown kCGSTabletPointingDeviceUnknown
#define TabletPointerTypePen kCGSTabletPointingDevicePen
#define TabletPointerTypeCursor kCGSTabletPointingDeviceCursor
#define TabletPointerTypeEraser kCGSTabletPointingDeviceEraser
#define TabletButtonTip kCGSTabletButtonTip
#define TabletButtonLowerSide kCGSTabletButtonLowerSide
#define TabletButtonUpperSide kCGSTabletButtonUpperSide

@interface CGSWaylandTabletDevice : NSObject {
@public
    struct wl_proxy *_proxy;
    uint32_t _vid, _pid;
    NSString *_name, *_path;
}
@end

@implementation CGSWaylandTabletDevice
- (void) dealloc {
    [_name release];
    [_path release];
    [super dealloc];
}
@end

// One wp_tablet_tool: the descriptive events arrive before any proximity event and stay with the
// tool for the whole session, so the proximity CGEvents can carry the identifiers AppKit expects.
@interface CGSWaylandTabletToolState : NSObject {
@public
    struct wl_proxy *_proxy;
    uint32_t _toolType;
    uint32_t _serialHi, _serialLo;
    uint32_t _wacomHi, _wacomLo;
    NSUInteger _capabilities;
}
@end

@implementation CGSWaylandTabletToolState
@end

static uint32_t clampU32(uint32_t value, uint32_t maximum) {
    return value > maximum ? maximum : value;
}

static double clampUnit(double value) {
    if (value < 0)
        return 0;
    return value > 1 ? 1 : value;
}

static CGSWaylandTabletDevice *tabletDeviceForProxy(NSArray *tablets, struct wl_proxy *proxy) {
    for (CGSWaylandTabletDevice *device in tablets)
        if (device->_proxy == proxy)
            return device;
    return nil;
}

static CGSWaylandTabletToolState *tabletToolForProxy(NSArray *tools, struct wl_proxy *proxy) {
    for (CGSWaylandTabletToolState *tool in tools)
        if (tool->_proxy == proxy)
            return tool;
    return nil;
}

static uint32_t cocoaPointerType(uint32_t toolType) {
    switch (toolType) {
    case ZWP_TABLET_TOOL_TYPE_ERASER: return TabletPointerTypeEraser;
    case ZWP_TABLET_TOOL_TYPE_MOUSE: return TabletPointerTypeCursor;
    case ZWP_TABLET_TOOL_TYPE_PEN:
    case ZWP_TABLET_TOOL_TYPE_BRUSH:
    case ZWP_TABLET_TOOL_TYPE_PENCIL:
    case ZWP_TABLET_TOOL_TYPE_AIRBRUSH: return TabletPointerTypePen;
    default: return TabletPointerTypeUnknown;
    }
}

static uint64_t toolSerial(CGSWaylandTabletToolState *tool) {
    return ((uint64_t) tool->_serialHi << 32) | tool->_serialLo;
}

// A stable small id for the pointer-tool pair, as the device id of the tablet events. The protocol
// has no such number; the hardware serial and the tablet's USB ids identify the pair well enough.
static uint32_t tabletDeviceID(CGSWaylandTabletToolState *tool, CGSWaylandTabletDevice *device) {
    return _CGSTabletDeviceID(toolSerial(tool), device->_vid, device->_pid, 0);
}

@implementation CGSWaylandTablet

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection {
    self = [super init];
    if (self == nil)
        return nil;
    _connection = connection;
    _tablets = [NSMutableArray new];
    _tools = [NSMutableArray new];
    _pads = [NSMutableArray new];
    // Tablets are hardware, as the pointer and the touch screen are.
    _source = (void *) CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    return self;
}

- (struct wl_proxy *) manager {
    return _manager;
}

- (uint32_t) managerName {
    return _managerName;
}

- (uint32_t) seatName {
    return _seatName;
}

- (void) dealloc {
    [self stop];
    [_tablets release];
    [_tools release];
    [_pads release];
    if (_source != NULL)
        CFRelease((CFTypeRef) _source);
    [super dealloc];
}

#pragma mark - The objects

- (void) createTabletSeatIfPossible {
    if (_manager == NULL || _seat == NULL || _seatProxy != NULL)
        return;
    union wl_argument args[2] = {{.o = NULL}, {.o = (struct wl_object *) _seat}};
    _seatProxy = [_connection createObject: _manager
                                    opcode: ZWP_TABLET_MANAGER_GET_TABLET_SEAT
                                 interface: &zwp_tablet_seat_v2_interface
                                 arguments: args
                                      kind: CGSWaylandObjectTabletSeat
                                    object: self];
}

- (void) managerBound: (struct wl_proxy *) manager name: (uint32_t) name seat: (struct wl_proxy *) seat {
    if (manager == NULL)
        return;
    _manager = manager;
    _managerName = name;
    if (seat != NULL)
        _seat = seat;
    [self createTabletSeatIfPossible];
}

- (void) seatBound: (struct wl_proxy *) seat name: (uint32_t) name {
    if (seat == NULL)
        return;
    _seat = seat;
    _seatName = name;
    [self createTabletSeatIfPossible];
}

- (void) managerRemoved {
    [self stop];
    _manager = NULL;
    _managerName = 0;
}

- (void) seatRemoved {
    [self stopTabletSeat];
    _seat = NULL;
    _seatName = 0;
}

- (void) tabletSeatEvent: (uint32_t) opcode arguments: (union wl_argument *) args {
    struct wl_proxy *proxy = (struct wl_proxy *) args[0].o;

    if (proxy == NULL)
        return;
    switch (opcode) {
    case ZWP_TABLET_SEAT_EV_TABLET_ADDED: {
        CGSWaylandTabletDevice *device = [CGSWaylandTabletDevice new];
        device->_proxy = proxy;
        [_connection attachDispatcherTo: proxy kind: CGSWaylandObjectTablet object: self];
        [_tablets addObject: device];
        [device release];
        break;
    }
    case ZWP_TABLET_SEAT_EV_TOOL_ADDED: {
        CGSWaylandTabletToolState *tool = [CGSWaylandTabletToolState new];
        tool->_proxy = proxy;
        [_connection attachDispatcherTo: proxy kind: CGSWaylandObjectTabletTool object: self];
        [_tools addObject: tool];
        [tool release];
        break;
    }
    case ZWP_TABLET_SEAT_EV_PAD_ADDED:
        // Pads are a separate protocol. Keeping the proxy is enough to release it with the seat.
        [_connection attachDispatcherTo: proxy kind: CGSWaylandObjectTabletPad object: self];
        [_pads addObject: [NSValue valueWithPointer: proxy]];
        break;
    default:
        break;
    }
}

- (void) destroyProxy: (struct wl_proxy **) proxy opcode: (uint32_t) opcode interface: (const struct wl_interface *) interface {
    if (*proxy == NULL)
        return;
    union wl_argument args[1] = {{.o = NULL}};
    WaylandMarshal(*proxy, opcode, interface, WL_MARSHAL_FLAG_DESTROY, args);
    *proxy = NULL;
}

- (void) tabletEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args {
    CGSWaylandTabletDevice *device = tabletDeviceForProxy(_tablets, proxy);

    if (device == nil)
        return;
    switch (opcode) {
    case ZWP_TABLET_EV_NAME:
        [device->_name release];
        device->_name = [[NSString stringWithUTF8String: args[0].s ?: ""] copy];
        break;
    case ZWP_TABLET_EV_ID:
        device->_vid = args[0].u;
        device->_pid = args[1].u;
        break;
    case ZWP_TABLET_EV_PATH:
        [device->_path release];
        device->_path = [[NSString stringWithUTF8String: args[0].s ?: ""] copy];
        break;
    case ZWP_TABLET_EV_REMOVED:
        if (_inProximity && _frameTool != nil && _tabletProxy == proxy)
            [self postProximityOut];
        if (_tabletProxy == proxy)
            _tabletProxy = NULL;
        [self destroyProxy: &device->_proxy opcode: ZWP_TABLET_DESTROY
                 interface: &zwp_tablet_v2_interface];
        [_tablets removeObjectIdenticalTo: device];
        break;
    default:
        break;
    }
}

- (void) toolEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args {
    CGSWaylandTabletToolState *tool = tabletToolForProxy(_tools, proxy);

    if (tool == nil)
        return;
    switch (opcode) {
    case ZWP_TABLET_TOOL_EV_TYPE:
        tool->_toolType = args[0].u;
        break;
    case ZWP_TABLET_TOOL_EV_HARDWARE_SERIAL:
        tool->_serialHi = args[0].u;
        tool->_serialLo = args[1].u;
        break;
    case ZWP_TABLET_TOOL_EV_HARDWARE_ID_WACOM:
        tool->_wacomHi = args[0].u;
        tool->_wacomLo = args[1].u;
        break;
    case ZWP_TABLET_TOOL_EV_CAPABILITY:
        if (args[0].u >= 1 && args[0].u <= 6)
            tool->_capabilities |= 1ULL << args[0].u;
        break;
    case ZWP_TABLET_TOOL_EV_REMOVED:
        if (_inProximity && _frameTool == tool)
            [self postProximityOut];
        if (_frameTool == tool)
            _frameTool = nil;
        [self destroyProxy: &tool->_proxy opcode: ZWP_TABLET_TOOL_DESTROY
                 interface: &zwp_tablet_tool_v2_interface];
        [_tools removeObjectIdenticalTo: tool];
        break;

    // The events of a frame. Only wp_tablet_tool.frame posts a CGEvent: before it the compositor
    // may still send more axes of the same instant.
    case ZWP_TABLET_TOOL_EV_PROXIMITY_IN:
        // A new session starts with neutral axes; the compositor sends the values it has before
        // the frame, and an absent axis keeps the neutral value.
        [self resetToolState];
        _frameActive = YES;
        _inProximity = YES;
        _proximityChanged = YES;
        _proximityEntering = YES;
        _frameSerial = args[0].u;
        _tabletProxy = (struct wl_proxy *) args[1].o;
        _surface = (struct wl_proxy *) args[2].o;
        _frameTool = tool;
        break;
    case ZWP_TABLET_TOOL_EV_PROXIMITY_OUT:
        _frameActive = YES;
        _inProximity = NO;
        _proximityChanged = YES;
        _proximityEntering = NO;
        _frameTool = tool;
        _tipDown = NO;
        _buttonMask = 0;
        _sideButton1Down = _sideButton2Down = NO;
        _hasPoint = NO;
        break;
    case ZWP_TABLET_TOOL_EV_DOWN:
        _frameActive = YES;
        _frameSerial = args[0].u;
        _frameTool = tool;
        _tipDown = YES;
        _downChanged = YES;
        _buttonMask |= TabletButtonTip;
        [_connection inputPressedWithSerial: _frameSerial];
        break;
    case ZWP_TABLET_TOOL_EV_UP:
        _frameActive = YES;
        _frameTool = tool;
        _tipDown = NO;
        _downChanged = YES;
        _buttonMask &= ~((uint32_t) TabletButtonTip);
        break;
    case ZWP_TABLET_TOOL_EV_MOTION:
        _frameActive = YES;
        _frameTool = tool;
        _hasPoint = YES;
        _point = CGPointMake(wl_fixed_to_double(args[0].f), wl_fixed_to_double(args[1].f));
        break;
    case ZWP_TABLET_TOOL_EV_PRESSURE:
        _frameActive = YES;
        _frameTool = tool;
        _pressure = clampUnit(clampU32(args[0].u, 65535) / 65535.0);
        break;
    case ZWP_TABLET_TOOL_EV_DISTANCE:
        _frameActive = YES;
        _frameTool = tool;
        _distance = clampUnit(clampU32(args[0].u, 65535) / 65535.0);
        break;
    case ZWP_TABLET_TOOL_EV_TILT: {
        // The protocol's tilt is in degrees from the tablet's z axis. CGEvent's tilt fields are
        // normalised to -1 to 1, where 1 is a pen parallel to the surface, as AppKit's -tilt is.
        double x = wl_fixed_to_double(args[0].f);
        double y = wl_fixed_to_double(args[1].f);
        _frameActive = YES;
        _frameTool = tool;
        _tiltX = _CGSTabletNormalizedTilt(x);
        _tiltY = _CGSTabletNormalizedTilt(y);
        break;
    }
    case ZWP_TABLET_TOOL_EV_ROTATION:
        _frameActive = YES;
        _frameTool = tool;
        _rotation = wl_fixed_to_double(args[0].f);
        break;
    case ZWP_TABLET_TOOL_EV_SLIDER:
        // The slider's range is device-specific; Wacom's barrel wheel is a signed 16-bit value.
        _frameActive = YES;
        _frameTool = tool;
        _tangentialPressure = fmax(-1.0, fmin(1.0, args[0].i / 32767.0));
        break;
    case ZWP_TABLET_TOOL_EV_WHEEL:
        // A tablet wheel is a relative rotation, not a Cocoa tablet axis. Absorbing it here keeps
        // the rest of the frame's state together; the pointer's wheel is a separate device.
        _frameActive = YES;
        _frameTool = tool;
        break;
    case ZWP_TABLET_TOOL_EV_BUTTON: {
        uint32_t code = args[1].u;
        BOOL pressed = args[2].u == ZWP_TABLET_TOOL_BUTTON_STATE_PRESSED;

        _frameActive = YES;
        _frameSerial = args[0].u;
        _frameTool = tool;
        _buttonPressed = pressed;
        if (pressed && !_sideButton1Down && code != _sideButton2) {
            _sideButton1 = code;
            _sideButton1Down = YES;
            _buttonMask |= TabletButtonLowerSide;
        } else if (pressed && !_sideButton2Down && code != _sideButton1) {
            _sideButton2 = code;
            _sideButton2Down = YES;
            _buttonMask |= TabletButtonUpperSide;
        } else if (!pressed) {
            if (code == _sideButton1) {
                _sideButton1Down = NO;
                _buttonMask &= ~((uint32_t) TabletButtonLowerSide);
            }
            if (code == _sideButton2) {
                _sideButton2Down = NO;
                _buttonMask &= ~((uint32_t) TabletButtonUpperSide);
            }
        }
        if (pressed)
            [_connection inputPressedWithSerial: _frameSerial];
        break;
    }
    case ZWP_TABLET_TOOL_EV_FRAME:
        // frame is per tool. Another tool's frame must not post the state accumulated for this
        // one; if it arrives, drop the partial frame.
        if (tool == _frameTool)
            [self postFrame];
        else
            [self resetFrame];
        break;
    default:
        break;
    }
}

- (void) padEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args {
    (void) args;
    if (opcode != ZWP_TABLET_PAD_EV_REMOVED) // Other pad events are ignored.
        return;
    NSValue *value = [NSValue valueWithPointer: proxy];
    [_pads removeObject: value];
    WL.wl_proxy_destroy(proxy);
}

#pragma mark - Posting

- (CGPoint) globalLocationOfSurface: (struct wl_proxy *) surface point: (CGPoint) point {
    id<CGSNativeConnectionObserver> observer = [CGSConnection nativeObserver];
    CGPoint global;

    if ([observer respondsToSelector: @selector(nativeConnectionGlobalLocation:ofSurface:point:)] &&
        [observer nativeConnectionGlobalLocation: &global ofSurface: surface point: point])
        return global;
    if ([_connection globalLocation: &global ofSurface: surface point: point])
        return global;
    return point;
}

- (void) resetToolState {
    _pressure = 0;
    _distance = 0;
    _tiltX = _tiltY = 0;
    _rotation = 0;
    _tangentialPressure = 0;
    _tipDown = NO;
    _buttonMask = 0;
    _buttonPressed = NO;
    _sideButton1Down = _sideButton2Down = NO;
    _hasPoint = NO;
    _hasLocal = NO;
    _lastLocal = CGPointZero;
    _lastGlobal = CGPointZero;
}

- (void) resetFrame {
    _frameActive = NO;
    _frameSerial = 0;
    _frameTool = nil;
    _proximityChanged = NO;
    _proximityEntering = NO;
    _downChanged = NO;
    _buttonPressed = NO;
}

- (void) postFrame {
    CGSWaylandTabletToolState *tool = _frameTool;
    CGSWaylandTabletDevice *device = tabletDeviceForProxy(_tablets, _tabletProxy);

    if (!_frameActive || tool == nil || !_inProximity && !_proximityChanged) {
        [self resetFrame];
        return;
    }

    CGPoint point = _hasPoint ? [self globalLocationOfSurface: _surface point: _point] : _lastGlobal;
    CGPoint localPoint = _hasPoint ? _point : _lastLocal;
    if (_hasPoint) {
        _lastGlobal = point;
        _lastLocal = localPoint;
    }
    _hasGlobal = _hasPoint || _hasGlobal;
    _hasLocal = _hasPoint || _hasLocal;

    // The tablet axes are the surface-local motion coordinates. CGEvent's location is global, but
    // the documented absolute axes must keep the tablet's own coordinate space.
    uint32_t vid = device != nil ? device->_vid : 0;
    uint32_t pid = device != nil ? device->_pid : 0;
    uint64_t serial = toolSerial(tool);
    uint32_t windowID = [_connection windowIDForSurface: _surface];
    // Only a press grants the serial that lets a client set the clipboard. A motion frame keeps
    // the last serial internally but must not publish it.
    BOOL pressed = _proximityEntering || _downChanged || _buttonPressed;

    CGSTabletSample sample = {
        .source = (CGEventSourceRef) _source,
        .proximity = _proximityChanged,
        .entering = _proximityEntering,
        // The compositor's frame time is a monotonic millisecond count with an unspecified epoch.
        // Leave the timestamp to the event pipeline, which stamps events at posting time.
        .flags = (uint64_t) [_connection modifierFlags],
        .location = point,
        .hasNativeLocation = _hasPoint,
        .nativeLocation = localPoint,
        .nativeLocationScale = 1024,
        .hasPostedLocation = _hasGlobal,
        .axes = _hasLocal ? localPoint : CGPointZero,
        .windowID = windowID != 0 && ![_connection isDisplayOverlaySurface: _surface] ? windowID : 0,
        .nativeWindow = (int64_t) (intptr_t) _surface,
        .inputSerial = pressed ? _frameSerial : 0,
        .pressure = _pressure,
        .distance = _distance,
        .tiltX = _tiltX,
        .tiltY = _tiltY,
        .rotation = _rotation,
        .tangentialPressure = _tangentialPressure,
        .buttonMask = _buttonMask,
        .vendorID = vid,
        .tabletID = pid,
        .pointerID = tool->_serialLo,
        .deviceID = tabletDeviceID(tool, device),
        .toolSerial = serial,
        .vendorPointerType = tool->_toolType,
        .pointerType = cocoaPointerType(tool->_toolType),
        .capabilities = tool->_capabilities,
    };
    CGEventRef event = _CGSTabletEventCreate(&sample);
    if (event == NULL) {
        [self resetFrame];
        return;
    }

    // What the other devices held back (a modifier key, a scroll frame) came before the tool moved.
    [_connection flushPendingKeyboardEvents];
    [_connection flushPendingPointerEvents];

    _CGSEventStreamPost(event);
    CFRelease(event);
    [self resetFrame];
}

- (void) postProximityOut {
    if (!_inProximity || _frameTool == nil)
        return;
    _frameActive = YES;
    _proximityChanged = YES;
    _proximityEntering = NO;
    _inProximity = NO;
    [self postFrame];
    [self resetToolState];
}

- (void) surfaceDestroyed: (struct wl_proxy *) surface {
    if (surface == NULL || surface != _surface)
        return;
    [self postProximityOut];
    _surface = NULL;
    _tabletProxy = NULL;
    _hasPoint = NO;
    _hasGlobal = NO;
    _hasLocal = NO;
    _frameTool = nil;
}

- (void) stopTabletSeat {
    [self postProximityOut];
    [self resetFrame];
    _surface = NULL;
    _tabletProxy = NULL;
    _hasPoint = _hasGlobal = _hasLocal = NO;

    for (CGSWaylandTabletToolState *tool in [[_tools copy] autorelease]) {
        if (tool->_proxy != NULL) {
            [self destroyProxy: &tool->_proxy opcode: ZWP_TABLET_TOOL_DESTROY
                     interface: &zwp_tablet_tool_v2_interface];
        }
        [_tools removeObjectIdenticalTo: tool];
    }
    for (CGSWaylandTabletDevice *device in [[_tablets copy] autorelease]) {
        if (device->_proxy != NULL) {
            [self destroyProxy: &device->_proxy opcode: ZWP_TABLET_DESTROY
                     interface: &zwp_tablet_v2_interface];
        }
        [_tablets removeObjectIdenticalTo: device];
    }
    for (NSValue *value in [[_pads copy] autorelease]) {
        struct wl_proxy *pad = (struct wl_proxy *) [value pointerValue];
        if (pad != NULL)
            WL.wl_proxy_destroy(pad);
        [_pads removeObject: value];
    }
    [self destroyProxy: &_seatProxy opcode: ZWP_TABLET_SEAT_DESTROY
             interface: &zwp_tablet_seat_v2_interface];
}

- (void) stop {
    [self stopTabletSeat];
    if (_manager != NULL) {
        [self destroyProxy: &_manager opcode: ZWP_TABLET_MANAGER_DESTROY
                 interface: &zwp_tablet_manager_v2_interface];
    }
}

@end
