/* CoreGraphics: tablet CGEvents of the window system backends.

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

// The tablet CGEvent a backend's decoder makes from its sample (see CGSTabletSample in
// CoreGraphicsPrivate.h). The Wayland and the X11 backend share it, so a tool is described the same
// way to the frameworks above whichever window system it came through.

#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>

double _CGSTabletNormalizedTilt(double degrees) {
    return fmax(-1.0, fmin(1.0, degrees / 90.0));
}

uint32_t _CGSTabletDeviceID(uint64_t toolSerial, uint32_t vendorID, uint32_t tabletID, uint32_t extra) {
    uint32_t id = (uint32_t) toolSerial ^ (uint32_t) (toolSerial >> 32) ^ vendorID ^ tabletID ^ extra;
    return id != 0 ? id : 1;
}

CGEventRef _CGSTabletEventCreate(const CGSTabletSample *sample) {
    CGEventRef event = CGEventCreate(sample->source);
    if (event == NULL)
        return NULL;
    CGEventSetType(event, sample->proximity ? kCGEventTabletProximity : kCGEventTabletPointer);
    CGEventSetFlags(event, (CGEventFlags) sample->flags);
    CGEventSetLocation(event, sample->location);

    if (sample->windowID != 0) {
        CGEventSetIntegerValueField(event, kCGSTabletWindowNumber, sample->windowID);
        CGEventSetIntegerValueField(event, kCGSTabletWindowNumberThatCanHandleThisEvent, sample->windowID);
    }
    CGEventSetIntegerValueField(event, kCGSEventNativeWindow, sample->nativeWindow);
    if (sample->hasNativeLocation) {
        CGEventSetIntegerValueField(event, kCGSEventNativeLocationX, llround(sample->nativeLocation.x * sample->nativeLocationScale));
        CGEventSetIntegerValueField(event, kCGSEventNativeLocationY, llround(sample->nativeLocation.y * sample->nativeLocationScale));
    }
    if (sample->hasPostedLocation) {
        CGEventSetIntegerValueField(event, kCGSEventPostedLocationX, llround(sample->location.x * 1024));
        CGEventSetIntegerValueField(event, kCGSEventPostedLocationY, llround(sample->location.y * 1024));
    }
    CGEventSetIntegerValueField(event, kCGSEventInputSerial, sample->inputSerial);

    // The documented absolute axes keep the tablet's own coordinate space.
    CGEventSetIntegerValueField(event, kCGTabletEventPointX, llround(sample->axes.x));
    CGEventSetIntegerValueField(event, kCGTabletEventPointY, llround(sample->axes.y));
    CGEventSetIntegerValueField(event, kCGTabletEventPointZ, (int64_t) (sample->distance * 65535));
    CGEventSetIntegerValueField(event, kCGTabletEventPointButtons, sample->buttonMask);
    CGEventSetDoubleValueField(event, kCGTabletEventPointPressure, sample->pressure);
    CGEventSetDoubleValueField(event, kCGTabletEventTiltX, sample->tiltX);
    CGEventSetDoubleValueField(event, kCGTabletEventTiltY, sample->tiltY);
    CGEventSetDoubleValueField(event, kCGTabletEventRotation, sample->rotation);
    CGEventSetDoubleValueField(event, kCGTabletEventTangentialPressure, sample->tangentialPressure);
    CGEventSetIntegerValueField(event, kCGTabletEventDeviceID, sample->deviceID);
    CGEventSetIntegerValueField(event, kCGTabletEventVendor1, sample->vendorID);
    CGEventSetIntegerValueField(event, kCGTabletEventVendor2, sample->tabletID);
    CGEventSetIntegerValueField(event, kCGTabletEventVendor3, sample->vendorPointerType);

    int64_t systemTabletID = (int64_t) (((uint64_t) sample->vendorID << 32) | sample->tabletID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventVendorID, sample->vendorID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventTabletID, sample->tabletID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventPointerID, sample->pointerID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventDeviceID, sample->deviceID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventSystemTabletID, systemTabletID);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventVendorPointerType, sample->vendorPointerType);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventVendorPointerSerialNumber, (int64_t) sample->toolSerial);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventVendorUniqueID, (int64_t) sample->toolSerial);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventCapabilityMask, (int64_t) sample->capabilities);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventPointerType, sample->pointerType);
    CGEventSetIntegerValueField(event, kCGTabletProximityEventEnterProximity, sample->entering ? 1 : 0);

    // The common copies: the documented proximity fields are not present on tablet pointer events,
    // so the tool's identity would be lost on every event after it entered proximity.
    CGEventSetIntegerValueField(event, kCGSTabletPointerID, sample->pointerID);
    CGEventSetIntegerValueField(event, kCGSTabletSystemTabletID, systemTabletID);
    CGEventSetIntegerValueField(event, kCGSTabletCapabilityMask, (int64_t) sample->capabilities);
    CGEventSetIntegerValueField(event, kCGSTabletVendorPointerType, sample->vendorPointerType);
    CGEventSetIntegerValueField(event, kCGSTabletPointerType, sample->pointerType);
    CGEventSetIntegerValueField(event, kCGSTabletVendorPointerSerialNumber, (int64_t) sample->toolSerial);
    return event;
}
