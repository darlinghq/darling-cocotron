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

#import <AppKit/NSEvent.h>

// A graphics tablet event. The windowing backend posts a CGEvent with the documented tablet
// fields; this class is the only AppKit side that reads them. It never parses a windowing system's
// tablet protocol.
@interface NSEvent_tablet : NSEvent {
    float _pressure;
    NSPoint _tilt;
    float _rotation;
    float _tangentialPressure;
    NSInteger _absoluteX, _absoluteY, _absoluteZ;
    NSEventButtonMask _buttonMask;
    NSUInteger _vendorID, _tabletID, _pointerID, _deviceID, _systemTabletID, _vendorPointerType;
    unsigned long long _vendorPointerSerialNumber, _vendorUniqueID;
    NSUInteger _capabilityMask;
    NSPointingDeviceType _pointerType;
    BOOL _enterProximity;
}

- (instancetype) initWithType: (NSEventType) type
                     location: (NSPoint) location
                modifierFlags: (NSEventModifierFlags) modifierFlags
                    timestamp: (NSTimeInterval) timestamp
                 windowNumber: (NSInteger) windowNumber
                      context: (NSGraphicsContext *) context
                      cgEvent: (CGEventRef) cgEvent;

@end
