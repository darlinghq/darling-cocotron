/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "NSEvent_tablet.h"
#import <AppKit/NSApplication.h>
#import <Foundation/NSException.h>
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>

// The window system posts a tool's identity in the common fields as well as in the documented
// ones: CGEvent gives pointer and proximity events different sets of fields, but AppKit needs the
// tool's identity for both. On an event made by the application only the documented fields exist.
static int64_t fieldOr(CGEventRef event, CGEventField first, CGEventField fallback) {
    int64_t value = CGEventGetIntegerValueField(event, first);
    return value != 0 ? value : CGEventGetIntegerValueField(event, fallback);
}

@implementation NSEvent_tablet

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                      cgEvent: (CGEventRef) cgEvent
{
    (void) context;
    if (type != NSEventTypeTabletPoint && type != NSEventTypeTabletProximity) {
        [self release];
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s]: not a tablet event type: %lu", [self class],
                            sel_getName(_cmd), (unsigned long) type];
    }
    self = [super initWithType: type
                      location: location
                 modifierFlags: modifierFlags
                        window: [NSApp windowWithWindowNumber: windowNumber]];
    if (self == nil)
        return nil;

    _timestamp = timestamp;
    _pressure = (float) CGEventGetDoubleValueField(cgEvent, kCGTabletEventPointPressure);
    _rotation = (float) CGEventGetDoubleValueField(cgEvent, kCGTabletEventRotation);
    _tilt = NSMakePoint((CGFloat) CGEventGetDoubleValueField(cgEvent, kCGTabletEventTiltX),
                        (CGFloat) CGEventGetDoubleValueField(cgEvent, kCGTabletEventTiltY));
    _tangentialPressure = (float) CGEventGetDoubleValueField(cgEvent, kCGTabletEventTangentialPressure);
    _absoluteX = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGTabletEventPointX);
    _absoluteY = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGTabletEventPointY);
    _absoluteZ = (NSInteger) CGEventGetIntegerValueField(cgEvent, kCGTabletEventPointZ);
    _buttonMask = (NSEventButtonMask) CGEventGetIntegerValueField(cgEvent, kCGTabletEventPointButtons);

    BOOL point = type == NSEventTypeTabletPoint;
    _vendorID = (NSUInteger) (point ? CGEventGetIntegerValueField(cgEvent, kCGTabletEventVendor1) :
                                     CGEventGetIntegerValueField(cgEvent, kCGTabletProximityEventVendorID));
    _tabletID = (NSUInteger) (point ? CGEventGetIntegerValueField(cgEvent, kCGTabletEventVendor2) :
                                      CGEventGetIntegerValueField(cgEvent, kCGTabletProximityEventTabletID));
    _pointerID = (NSUInteger) fieldOr(cgEvent, kCGSTabletPointerID, kCGTabletProximityEventPointerID);
    _deviceID = (NSUInteger) (point ? CGEventGetIntegerValueField(cgEvent, kCGTabletEventDeviceID) :
                                      CGEventGetIntegerValueField(cgEvent, kCGTabletProximityEventDeviceID));
    _systemTabletID = (NSUInteger) fieldOr(cgEvent, kCGSTabletSystemTabletID,
                                          kCGTabletProximityEventSystemTabletID);
    _vendorPointerType = (NSUInteger) fieldOr(cgEvent, kCGSTabletVendorPointerType,
                                             kCGTabletProximityEventVendorPointerType);
    _vendorPointerSerialNumber = (unsigned long long) fieldOr(cgEvent, kCGSTabletVendorPointerSerialNumber,
                                                     kCGTabletProximityEventVendorPointerSerialNumber);
    _vendorUniqueID = (unsigned long long) (point ? _vendorPointerSerialNumber :
                                           CGEventGetIntegerValueField(cgEvent, kCGTabletProximityEventVendorUniqueID));
    _capabilityMask = (NSUInteger) fieldOr(cgEvent, kCGSTabletCapabilityMask,
                                           kCGTabletProximityEventCapabilityMask);
    _pointerType = (NSPointingDeviceType) fieldOr(cgEvent, kCGSTabletPointerType,
                                                  kCGTabletProximityEventPointerType);
    _enterProximity = CGEventGetIntegerValueField(cgEvent, kCGTabletProximityEventEnterProximity) != 0;
    return self;
}

- (float) pressure {
    return _pressure;
}

- (NSInteger) absoluteX {
    return _absoluteX;
}

- (NSInteger) absoluteY {
    return _absoluteY;
}

- (NSInteger) absoluteZ {
    return _absoluteZ;
}

- (NSEventButtonMask) buttonMask {
    return _buttonMask;
}

- (NSPoint) tilt {
    return _tilt;
}

- (float) tangentialPressure {
    return _tangentialPressure;
}

- (float) rotation {
    return _rotation;
}

- (NSUInteger) vendorID {
    return _vendorID;
}

- (NSUInteger) tabletID {
    return _tabletID;
}

- (NSUInteger) pointingDeviceID {
    return _pointerID;
}

- (NSUInteger) deviceID {
    return _deviceID;
}

- (NSUInteger) systemTabletID {
    return _systemTabletID;
}

- (NSUInteger) vendorPointingDeviceType {
    return _vendorPointerType;
}

- (NSUInteger) pointingDeviceSerialNumber {
    return _vendorPointerSerialNumber;
}

- (unsigned long long) uniqueID {
    return _vendorUniqueID;
}

- (NSUInteger) capabilityMask {
    return _capabilityMask;
}

- (NSPointingDeviceType) pointingDeviceType {
    return _pointerType;
}

- (BOOL) isEnteringProximity {
    return _enterProximity;
}

@end
