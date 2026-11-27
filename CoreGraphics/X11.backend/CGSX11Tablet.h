/* CoreGraphics X11 backend: graphics tablets.

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

// Pen, eraser and puck tools of graphics tablets (XInput 2), decoded into tablet CGEvents
// (kCGEventTabletPointer and kCGEventTabletProximity) with the same fields the Wayland backend's
// zwp_tablet_v2 decoder posts: both build the event with _CGSTabletEventCreate().
//
// A tablet is an XInput2 slave device that has a pressure valuator (valuator labels "Abs Pressure", "Abs Tilt X",
// "Abs Tilt Y", "Abs Wheel" and "Abs Distance" of the XI2 axis label convention) or says what tool it is with the
// "Wacom Tool Type" property; the properties "Device Product ID" (vendor and product) and "Wacom Serial IDs" (the
// tool's serial number) identify the hardware where the driver sets them.
//
// The events come from the raw events of the root window (XI_RawMotion, XI_RawButtonPress, XI_RawButtonRelease),
// which name the slave device that made them and carry its valuators in the device's own units: selecting the
// device events of a window instead would stop the server sending that window the core pointer events the pointer
// decoder relies on. The position and the window are those of the pointer, which a tablet tool moves; the raw event
// of the tool is followed by the pointer's own events for it. XInput2 has no proximity event: the tool is in
// proximity from its first event over a window of the process, and leaves it when the pointer leaves the process'
// windows, the window it was over goes away, or the device does.

#ifndef CGSX11TABLET_H
#define CGSX11TABLET_H

#import <Foundation/NSObject.h>
#include <CoreGraphics/CGGeometry.h>
#include <X11/Xlib.h>
#include <X11/extensions/XInput2.h>
#include <stdint.h>

@class CGSConnectionX11;
@class CGSX11Pointer;

// A tablet tool device as the server describes it; a valuator number is -1 for an axis the device does not have.
typedef struct {
    int deviceID;              // the (slave) device
    int pointerType;           // kCGSTabletPointingDevice*
    int pressure, tiltX, tiltY, wheel, distance, absX, absY;
    double pressureMin, pressureMax, distanceMin, distanceMax, wheelMin, wheelMax;
    uint32_t vendorID, productID;
    int hasSerialIDs;          // the device has the "Wacom Serial IDs" property
} CGSX11TabletDevice;

@interface CGSX11Tablet : NSObject {
    // Declared here: the i386 slice has the legacy Objective-C ABI, which has no ivars in the @implementation.
    CGSX11Pointer *_pointer;       // not retained: the pointer owns the tablets
    CGSConnectionX11 *_connection; // not retained
    void *_source;                 // CGEventSourceRef of the hardware state, not owned
    void *_records;                // the devices and what the tools of them last said
    int _count;
    int _active;                   // index of the record whose tool is in proximity, or -1
    Window _activeWindow;
    CGPoint _lastRoot;
    int _lastWinX, _lastWinY;
}

- (instancetype) initWithPointer: (CGSX11Pointer *) pointer connection: (CGSConnectionX11 *) connection source: (void *) source;
// Reads the tablets from the server (it has to be called again after XI_HierarchyChanged and XI_DeviceChanged).
- (void) queryDevices;
- (int) deviceCount;

// The decoding entry points. The connection feeds these from XInput2; they are also what a test of the decoding
// uses with events it made itself, as an X server that has a tablet cannot be started everywhere.
// Replaces the devices (and ends a tool in proximity).
- (void) setTabletDevices: (const CGSX11TabletDevice *) devices count: (int) count;
// A raw motion, button press or button release event (the others are ignored). Returns whether a tablet made it.
- (BOOL) rawEvent: (const XIRawEvent *) raw;
// What the "Wacom Serial IDs" property of a device says: the tablet id, the current tool's serial number and its
// device id (the other two values of the property are the previous tool's).
- (void) setSerialIDsOfDevice: (int) deviceID tabletID: (uint32_t) tablet serial: (uint32_t) serial toolID: (uint32_t) tool;
// A property of the device changed on the server.
- (void) propertyChangedOfDevice: (int) deviceID;
// The tool leaves proximity (the pointer left the windows of the process, the window it was over is going away, or
// its device is). Nothing when no tool is in proximity.
- (void) proximityOut;
- (void) windowDestroyed: (Window) window;

@end

#endif
