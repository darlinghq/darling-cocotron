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

// See CGSX11Tablet.h. The valuator labels and the properties used here are the XInput2 axis label convention
// and the property names of the Wacom driver's public header (wacom-properties.h of xf86-input-wacom): "Wacom Tool
// Type" is one atom (STYLUS, ERASER, CURSOR, PAD or TOUCH), "Wacom Serial IDs" five 32-bit values (tablet id, previous
// serial, previous device id, current serial, current device id). "Device Product ID" is the vendor and the product.

#import "CGSX11Tablet.h"
#import "CGSX11Pointer.h"
#import "CGSConnectionX11.h"
#import <CoreGraphics/CGEvent.h>
#import <CoreGraphics/CGEventSource.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <ctype.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

// What the last events of a tool said; an axis an event does not carry keeps its value, as on the hardware.
typedef struct {
    CGSX11TabletDevice device;
    double pressure, distance, tiltX, tiltY, tangentialPressure;
    double rawX, rawY;
    int hasRaw;
    uint32_t buttons;
    uint32_t serialTablet, serial, toolID;
} Record;

static double clampUnit(double value) {
    return value < 0 ? 0 : (value > 1 ? 1 : value);
}

// A value of an axis with a range as 0 to 1.
static double fractionOfRange(double value, double minimum, double maximum) {
    return maximum > minimum ? clampUnit((value - minimum) / (maximum - minimum)) : 0;
}

// The value of a signed axis as -1 to 1, its largest absolute limit being 1.
static double signedFraction(double value, double minimum, double maximum) {
    double limit = fmax(fabs(minimum), fabs(maximum));
    return limit > 0 ? fmax(-1.0, fmin(1.0, value / limit)) : 0;
}

@implementation CGSX11Tablet

- (instancetype) initWithPointer: (CGSX11Pointer *) pointer connection: (CGSConnectionX11 *) connection source: (void *) source {
    self = [super init];
    if (self == nil)
        return nil;
    _pointer = pointer;
    _connection = connection;
    _source = source;
    _active = -1;
    return self;
}

- (void) dealloc {
    free(_records);
    [super dealloc];
}

- (int) deviceCount {
    return _count;
}

- (Record *) records {
    return (Record *) _records;
}

#pragma mark - Devices

// A 32-bit property of a device, as many values as it has up to a limit (0 for none).
static int cardinalProperty(Display *display, int deviceID, const char *name, long *values, int limit) {
    Atom property = XInternAtom(display, name, True), type;
    int format;
    unsigned long count, after;
    unsigned char *data = NULL;

    if (property == None)
        return 0;
    if (XIGetProperty(display, deviceID, property, 0, limit, False, AnyPropertyType, &type, &format, &count, &after,
                      &data) != Success || data == NULL)
        return 0;
    int result = 0;
    if (format == 32 && type != None) {
        result = count < (unsigned long) limit ? (int) count : limit;
        memcpy(values, data, result * sizeof(long));
    }
    XFree(data);
    return result;
}

// The name of the atom a device's "Wacom Tool Type" property holds, as a lower case string in a buffer.
static BOOL toolTypeName(Display *display, int deviceID, char *buffer, size_t size) {
    long value;
    if (cardinalProperty(display, deviceID, "Wacom Tool Type", &value, 1) != 1 || value == None)
        return NO;
    char *name = XGetAtomName(display, (Atom) value);
    if (name == NULL)
        return NO;
    size_t i = 0;
    for (; name[i] != 0 && i + 1 < size; i++)
        buffer[i] = (char) tolower((unsigned char) name[i]);
    buffer[i] = 0;
    XFree(name);
    return YES;
}

static void readSerialIDs(Display *display, Record *record) {
    long ids[5];
    if (record->device.hasSerialIDs && cardinalProperty(display, record->device.deviceID, "Wacom Serial IDs", ids, 5) == 5) {
        record->serialTablet = (uint32_t) ids[0];
        record->serial = (uint32_t) ids[3];
        record->toolID = (uint32_t) ids[4];
    }
}

- (void) queryDevices {
    Display *display = _connection->_display;
    int count = 0;
    XIDeviceInfo *devices = display != NULL ? XIQueryDevice(display, XIAllDevices, &count) : NULL;
    Record *found = NULL;
    int foundCount = 0;

    for (int d = 0; d < count; d++) {
        const XIDeviceInfo *info = &devices[d];
        if (info->use != XISlavePointer && info->use != XIFloatingSlave)
            continue;
        CGSX11TabletDevice device = {.deviceID = info->deviceid, .pressure = -1, .tiltX = -1, .tiltY = -1, .wheel = -1,
                                     .distance = -1, .absX = -1, .absY = -1};
        for (int c = 0; c < info->num_classes; c++) {
            if (info->classes[c]->type != XIValuatorClass)
                continue;
            const XIValuatorClassInfo *axis = (const XIValuatorClassInfo *) info->classes[c];
            char *label = axis->label != None ? XGetAtomName(display, axis->label) : NULL;
            if (label == NULL)
                continue;
            if (strcmp(label, "Abs X") == 0)
                device.absX = axis->number;
            else if (strcmp(label, "Abs Y") == 0)
                device.absY = axis->number;
            else if (strcmp(label, "Abs Pressure") == 0) {
                device.pressure = axis->number;
                device.pressureMin = axis->min;
                device.pressureMax = axis->max;
            } else if (strcmp(label, "Abs Tilt X") == 0)
                device.tiltX = axis->number;
            else if (strcmp(label, "Abs Tilt Y") == 0)
                device.tiltY = axis->number;
            else if (strcmp(label, "Abs Wheel") == 0) {
                device.wheel = axis->number;
                device.wheelMin = axis->min;
                device.wheelMax = axis->max;
            } else if (strcmp(label, "Abs Distance") == 0) {
                device.distance = axis->number;
                device.distanceMin = axis->min;
                device.distanceMax = axis->max;
            }
            XFree(label);
        }

        // Pads and touch surfaces of a tablet are other devices that are no tools.
        char type[32] = "";
        BOOL typed = toolTypeName(display, device.deviceID, type, sizeof(type));
        if (typed && (strcmp(type, "pad") == 0 || strcmp(type, "touch") == 0))
            continue;
        if (device.pressure < 0 && !typed)
            continue;
        if (device.absX < 0 || device.absY < 0)
            continue;

        const char *name = info->name != NULL ? info->name : "";
        if (typed && strcmp(type, "eraser") == 0)
            device.pointerType = kCGSTabletPointingDeviceEraser;
        else if (typed && strcmp(type, "cursor") == 0)
            device.pointerType = kCGSTabletPointingDeviceCursor;
        else if (typed)
            device.pointerType = kCGSTabletPointingDevicePen;
        else if (strcasestr(name, "eraser") != NULL)
            device.pointerType = kCGSTabletPointingDeviceEraser;
        else if (strcasestr(name, "cursor") != NULL)
            device.pointerType = kCGSTabletPointingDeviceCursor;
        else
            device.pointerType = kCGSTabletPointingDevicePen;

        long ids[2];
        if (cardinalProperty(display, device.deviceID, "Device Product ID", ids, 2) == 2) {
            device.vendorID = (uint32_t) ids[0];
            device.productID = (uint32_t) ids[1];
        }
        // Whether the device has the property: XIListProperties tells.
        int propertyCount = 0;
        Atom *properties = XIListProperties(display, device.deviceID, &propertyCount);
        device.hasSerialIDs = 0;
        Atom serialIDs = XInternAtom(display, "Wacom Serial IDs", True);
        for (int p = 0; p < propertyCount && serialIDs != None; p++)
            if (properties[p] == serialIDs)
                device.hasSerialIDs = 1;
        if (properties != NULL)
            XFree(properties);

        found = realloc(found, (foundCount + 1) * sizeof(*found));
        if (found == NULL) {
            foundCount = 0;
            break;
        }
        memset(&found[foundCount], 0, sizeof(*found));
        found[foundCount].device = device;
        readSerialIDs(display, &found[foundCount]);
        foundCount++;
    }
    if (devices != NULL)
        XIFreeDeviceInfo(devices);
    [self installRecords: found count: foundCount];
}

// Takes the new device list. A tool in proximity stays in it if its device is still there.
- (void) installRecords: (Record *) records count: (int) count {
    int activeDevice = _active >= 0 ? [self records][_active].device.deviceID : -1;
    int stillThere = -1;
    for (int i = 0; i < count; i++)
        if (records[i].device.deviceID == activeDevice)
            stillThere = i;
    if (_active >= 0 && stillThere < 0)
        [self proximityOut];
    Record *old = [self records];
    int oldCount = _count;
    if (stillThere >= 0)
        for (int i = 0; i < oldCount; i++)
            if (old[i].device.deviceID == activeDevice) {
                Record state = old[i];
                state.device = records[stillThere].device;
                records[stillThere] = state;
            }
    free(_records);
    _records = records;
    _count = count;
    _active = stillThere;
}

- (void) setTabletDevices: (const CGSX11TabletDevice *) devices count: (int) count {
    Record *records = count > 0 ? calloc(count, sizeof(*records)) : NULL;
    if (records == NULL)
        count = 0;
    for (int i = 0; i < count; i++)
        records[i].device = devices[i];
    [self proximityOut];
    [self installRecords: records count: count];
}

- (int) indexOfDevice: (int) deviceID {
    Record *records = [self records];
    for (int i = 0; i < _count; i++)
        if (records[i].device.deviceID == deviceID)
            return i;
    return -1;
}

- (void) setSerialIDsOfDevice: (int) deviceID tabletID: (uint32_t) tablet serial: (uint32_t) serial toolID: (uint32_t) tool {
    int index = [self indexOfDevice: deviceID];
    if (index < 0)
        return;
    Record *record = &[self records][index];
    record->serialTablet = tablet;
    record->serial = serial;
    record->toolID = tool;
}

- (void) propertyChangedOfDevice: (int) deviceID {
    int index = [self indexOfDevice: deviceID];
    if (index < 0 || _connection->_display == NULL)
        return;
    readSerialIDs(_connection->_display, &[self records][index]);
}

#pragma mark - Events

- (CGSTabletSample) sampleOfRecord: (const Record *) record window: (Window) window winX: (int) winX winY: (int) winY root: (CGPoint) root {
    const CGSX11TabletDevice *device = &record->device;
    CGPoint global = [_connection _cgPointFromRoot: root];
    CGSWindowID windowID = [_connection _windowIDForNativeWindow: window];
    uint32_t tabletID = record->serialTablet != 0 ? record->serialTablet : device->productID;
    uint64_t capabilities = 0;

    if (device->tiltX >= 0 && device->tiltY >= 0)
        capabilities |= kCGSTabletCapabilityTilt;
    if (device->pressure >= 0)
        capabilities |= kCGSTabletCapabilityPressure;
    if (device->distance >= 0)
        capabilities |= kCGSTabletCapabilityDistance;
    if (device->wheel >= 0)
        capabilities |= kCGSTabletCapabilitySlider;
    // The wheel is the airbrush finger wheel here, which Cocoa calls the tangential pressure.
    CGSTabletSample sample = {
        .source = (CGEventSourceRef) _source,
        .flags = (uint64_t) [_connection modifierFlags],
        .location = global,
        .hasNativeLocation = YES,
        .nativeLocation = CGPointMake(winX, winY),
        .nativeLocationScale = 1,
        .hasPostedLocation = YES,
        .axes = record->hasRaw ? CGPointMake(record->rawX, record->rawY) : CGPointMake(winX, winY),
        .windowID = windowID != 0 && ![_connection _isDisplayOverlayNativeWindow: window] ? windowID : 0,
        .nativeWindow = (int64_t) window,
        .pressure = record->pressure,
        .distance = record->distance,
        .tiltX = record->tiltX,
        .tiltY = record->tiltY,
        .tangentialPressure = record->tangentialPressure,
        .buttonMask = record->buttons,
        .vendorID = device->vendorID,
        .tabletID = tabletID,
        .pointerID = record->serial,
        .deviceID = _CGSTabletDeviceID(record->serial, device->vendorID, tabletID, (uint32_t) device->deviceID),
        .toolSerial = record->serial,
        .vendorPointerType = record->toolID != 0 ? record->toolID : (uint32_t) device->pointerType,
        .pointerType = (uint32_t) device->pointerType,
        .capabilities = capabilities,
    };
    return sample;
}

- (void) post: (CGSTabletSample *) sample {
    CGEventRef event = _CGSTabletEventCreate(sample);
    if (event == NULL)
        return;
    // What the other devices held back came before the tool moved: the pointer and the keyboard post as they
    // read, so there is nothing held back here.
    _CGSEventStreamPost(event);
    CFRelease(event);
}

- (void) proximityOut {
    if (_active < 0 || _active >= _count)
        return;
    Record *record = &[self records][_active];
    record->pressure = 0;
    record->buttons = 0;
    CGSTabletSample sample = [self sampleOfRecord: record window: _activeWindow winX: _lastWinX winY: _lastWinY root: _lastRoot];
    sample.proximity = YES;
    sample.entering = NO;
    _active = -1;
    _activeWindow = None;
    [self post: &sample];
    record->distance = record->tiltX = record->tiltY = record->tangentialPressure = 0;
    record->hasRaw = 0;
}

- (void) windowDestroyed: (Window) window {
    if (_active >= 0 && _activeWindow == window)
        [self proximityOut];
}

- (BOOL) rawEvent: (const XIRawEvent *) raw {
    if (_count == 0 || (raw->evtype != XI_RawMotion && raw->evtype != XI_RawButtonPress && raw->evtype != XI_RawButtonRelease))
        return NO;
    int index = raw->sourceid != 0 ? [self indexOfDevice: raw->sourceid] : -1;
    if (index < 0)
        return NO;
    Record *record = &[self records][index];
    const CGSX11TabletDevice *device = &record->device;

    // Where the tool is: the tablet's events only matter while it is over a window of the process.
    Window window = None;
    int winX = 0, winY = 0;
    CGPoint root = CGPointZero;
    unsigned int state = 0;
    if (![_pointer windowUnderPointer: &window x: &winX y: &winY root: &root state: &state])
        return YES;

    if (_active != index) {
        // One tool at a time: another tool's proximity ends first. A tool enters with neutral axes, as on Wayland.
        [self proximityOut];
        record->pressure = record->distance = record->tiltX = record->tiltY = record->tangentialPressure = 0;
        record->buttons = 0;
        record->hasRaw = 0;
        _active = index;
        _activeWindow = window;
        CGSTabletSample enter = [self sampleOfRecord: record window: window winX: winX winY: winY root: root];
        enter.proximity = YES;
        enter.entering = YES;
        [self post: &enter];
    }
    _activeWindow = window;
    _lastRoot = root;
    _lastWinX = winX;
    _lastWinY = winY;

    if (raw->valuators.mask != NULL && raw->raw_values != NULL) {
        const double *values = raw->raw_values;
        for (int bit = 0, i = 0; bit < raw->valuators.mask_len * 8; bit++) {
            if (!XIMaskIsSet(raw->valuators.mask, bit))
                continue;
            double value = values[i++];
            if (bit == device->pressure)
                record->pressure = fractionOfRange(value, device->pressureMin, device->pressureMax);
            else if (bit == device->distance)
                record->distance = fractionOfRange(value, device->distanceMin, device->distanceMax);
            // The tilt valuators of tablet drivers are in degrees from the tablet's normal (range -64 to 63 on the
            // servers whose axes were looked at; their resolution of 57 units per radian is one unit per degree).
            else if (bit == device->tiltX)
                record->tiltX = _CGSTabletNormalizedTilt(value);
            else if (bit == device->tiltY)
                record->tiltY = _CGSTabletNormalizedTilt(value);
            else if (bit == device->wheel)
                record->tangentialPressure = signedFraction(value, device->wheelMin, device->wheelMax);
            else if (bit == device->absX) {
                record->rawX = value;
                record->hasRaw = 1;
            } else if (bit == device->absY) {
                record->rawY = value;
                record->hasRaw = 1;
            }
        }
    }
    if (raw->evtype != XI_RawMotion) {
        // The tip is the first button, then the two side buttons; the others (the wheel's) are no tablet buttons.
        uint32_t bit = raw->detail == 1 ? kCGSTabletButtonTip : raw->detail == 2 ? kCGSTabletButtonLowerSide
                       : raw->detail == 3 ? kCGSTabletButtonUpperSide : 0;
        if (raw->evtype == XI_RawButtonPress)
            record->buttons |= bit;
        else
            record->buttons &= ~bit;
    }
    CGSTabletSample sample = [self sampleOfRecord: record window: window winX: winX winY: winY root: root];
    [self post: &sample];
    return YES;
}

@end
