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

// The process' tablet tools on Wayland: it binds zwp_tablet_manager_v2, asks it for the seat's
// zwp_tablet_seat_v2, and decodes the tools' events into tablet CGEvents (kCGEventTabletPointer
// and kCGEventTabletProximity, with the documented kCGTabletEvent* fields). The state a frame
// describes is accumulated until wp_tablet_tool.frame, the protocol's event boundary, so a tap
// never sees a half-updated tool. Tablet pads and rings are not decoded: their objects are kept
// only so they can be released with the seat.

#ifndef CGSWAYLANDTABLET_H
#define CGSWAYLANDTABLET_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <stdint.h>
#include <wayland-util.h>

@class CGSConnectionWayland;
@class NSMutableArray;
@class CGSWaylandTabletToolState;
struct wl_proxy;

@interface CGSWaylandTablet : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the
    // @implementation.
    CGSConnectionWayland *_connection; // not retained: the connection owns the decoder
    void *_source;                     // CGEventSourceRef of the hardware state
    struct wl_proxy *_manager, *_seat, *_seatProxy;
    uint32_t _managerName, _seatName;
    NSMutableArray *_tablets, *_tools, *_pads;
    // The frame being accumulated for one tool: wp_tablet_tool.frame carries the time, the rest
    // comes from the events before it. Absent axes keep their previous value, as they do on the
    // hardware.
    BOOL _frameActive;
    uint32_t _frameSerial;
    // The surface and tablet of the current proximity session; frame events themselves name
    // neither, so they use these.
    struct wl_proxy *_surface, *_tabletProxy;
    CGSWaylandTabletToolState *_frameTool;
    CGPoint _point, _lastGlobal, _lastLocal;
    BOOL _hasPoint, _hasGlobal, _hasLocal;
    BOOL _inProximity, _tipDown, _proximityChanged, _proximityEntering, _downChanged;
    BOOL _buttonPressed; // A side button of this frame grants a clipboard serial.
    double _pressure, _distance, _tiltX, _tiltY, _rotation, _tangentialPressure;
    uint32_t _buttonMask; // kCGTablet...ButtonMask bits (tip, lower side, upper side)
    // Wayland gives buttons numbers, Cocoa only three names. The first two side buttons that go
    // down map to the lower and upper side; a third one keeps the upper side pressed with it.
    uint32_t _sideButton1, _sideButton2;
    BOOL _sideButton1Down, _sideButton2Down;
}

- (instancetype) initWithConnection: (CGSConnectionWayland *) connection;
- (struct wl_proxy *) manager;
- (uint32_t) managerName;
- (uint32_t) seatName;

// The manager global arrived (or went away), and the seat it makes tablet seats for. The tablet
// seat is created as soon as both are known; wl_seat.capabilities says nothing about tablets.
- (void) managerBound: (struct wl_proxy *) manager name: (uint32_t) name seat: (struct wl_proxy *) seat;
- (void) seatBound: (struct wl_proxy *) seat name: (uint32_t) name;
- (void) managerRemoved;
- (void) seatRemoved;

// Events of the objects this decoder owns. These are also the entry points a test of the
// decoding uses, as a compositor with a tablet cannot be started everywhere.
- (void) tabletSeatEvent: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) tabletEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) toolEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args;
- (void) padEvent: (struct wl_proxy *) proxy opcode: (uint32_t) opcode arguments: (union wl_argument *) args;

// A window of the process went away: a tool over it leaves proximity without a compositor event.
- (void) surfaceDestroyed: (struct wl_proxy *) surface;
// Posts a proximity-out for a tool in proximity and releases the tablet seat and its objects.
- (void) stopTabletSeat;
// Releases the tablet seat and the manager: the connection is closing or the manager went away.
- (void) stop;

@end

#endif
