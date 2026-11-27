/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Tablet CGEvents (darlinghq/darling#2591): the window system posts a tablet pointer or proximity
// CGEvent with the documented kCGTablet* fields, and AppKit makes NSEvents from it and delivers
// them to -[NSResponder tabletPoint:] and -[NSResponder tabletProximity:]. This test posts the
// CGEvents a Wayland backend would post, with no compositor or tablet hardware. The Wayland
// protocol decoding itself is checked by tests/wayland-tablet-protocol.py.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <stdio.h>

static int failures, checks;
static void expect(BOOL ok, const char *what) {
    ++checks;
    if (!ok)
        ++failures;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    fflush(stdout);
}

@interface TabletView : NSView {
@public
    int points, proximities;
    NSEvent *lastPoint, *lastProximity;
}
@end
@implementation TabletView
- (void) tabletPoint: (NSEvent *) event { points++; [lastPoint release]; lastPoint = [event retain]; }
- (void) tabletProximity: (NSEvent *) event { proximities++; [lastProximity release]; lastProximity = [event retain]; }
@end

static NSWindow *window;
static TabletView *view;
static CGFloat screenHeight(void) {
    NSArray *screens = [NSScreen screens];
    return [screens count] > 0 ? NSMaxY([[screens objectAtIndex: 0] frame]) : 0;
}

static CGEventRef makeTablet(CGEventType type, NSPoint base) {
    CGEventRef event = CGEventCreate(NULL);
    CGEventSetType(event, type);
    NSPoint screen = [window convertBaseToScreen: base];
    CGEventSetLocation(event, CGPointMake(screen.x, screenHeight() - screen.y));
    CGEventSetIntegerValueField(event, kCGSTabletWindowNumber, [window windowNumber]);
    CGEventSetIntegerValueField(event, kCGSTabletWindowNumberThatCanHandleThisEvent, [window windowNumber]);
    CGEventSetIntegerValueField(event, kCGSEventInputSerial, 4321);
    return event;
}

static void post(CGEventRef event) {
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

static NSArray *drain(void) {
    NSMutableArray *events = [NSMutableArray array];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil) {
        [events addObject: event];
        [NSApp sendEvent: event];
    }
    return events;
}

static BOOL near(double a, double b) { return fabs(a - b) < 0.01; }

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 200)
                                             styleMask: NSTitledWindowMask
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        view = [[TabletView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [window setContentView: view];
        [window orderFront: nil];
        drain();

        // Entering proximity: a device/tool pair with two extra capabilities.
        CGEventRef enter = makeTablet(kCGEventTabletProximity, NSMakePoint(100, 100));
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventVendorID, 0x1234);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventTabletID, 0x5678);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventPointerID, 42);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventDeviceID, 99);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventSystemTabletID, 0x12345678);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventVendorPointerType, 0x140);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventVendorPointerSerialNumber, 0x1122334455LL);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventVendorUniqueID, 0x1122334455LL);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventCapabilityMask, 6);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventPointerType, NSPointingDeviceTypePen);
        CGEventSetIntegerValueField(enter, kCGTabletProximityEventEnterProximity, 1);
        CGEventSetIntegerValueField(enter, kCGSTabletPointerID, 42);
        CGEventSetIntegerValueField(enter, kCGSTabletSystemTabletID, 0x12345678);
        CGEventSetIntegerValueField(enter, kCGSTabletCapabilityMask, 6);
        CGEventSetIntegerValueField(enter, kCGSTabletVendorPointerType, 0x140);
        CGEventSetIntegerValueField(enter, kCGSTabletPointerType, NSPointingDeviceTypePen);
        CGEventSetIntegerValueField(enter, kCGSTabletVendorPointerSerialNumber, 0x1122334455LL);
        post(enter);
        NSArray *events = drain();
        NSEvent *e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect([events count] == 1 && [e type] == NSEventTypeTabletProximity,
               "a tablet proximity CGEvent becomes NSEventTypeTabletProximity");
        expect(view->proximities == 1 && view->lastProximity == e,
               "the proximity event reaches -[NSResponder tabletProximity:]");
        expect(e != nil && [e isEnteringProximity] && [e vendorID] == 0x1234 && [e tabletID] == 0x5678 &&
                       [e pointingDeviceID] == 42 && [e deviceID] == 99,
               "the proximity event carries the device and tool fields");
        expect(e != nil && [e pointingDeviceType] == NSPointingDeviceTypePen && [e capabilityMask] == 6 &&
                       [e pointingDeviceSerialNumber] == (NSUInteger) 0x1122334455ULL,
               "the tool type, capabilities and serial survive the conversion");

        // A pointer event with a tip and a side button down, pressure, tilt, rotation and slider.
        CGEventRef point = makeTablet(kCGEventTabletPointer, NSMakePoint(120, 80));
        CGEventSetIntegerValueField(point, kCGTabletEventPointX, 12345);
        CGEventSetIntegerValueField(point, kCGTabletEventPointY, 23456);
        CGEventSetIntegerValueField(point, kCGTabletEventPointZ, 1000);
        CGEventSetIntegerValueField(point, kCGTabletEventPointButtons,
                                    NSEventButtonMaskPenTip | NSEventButtonMaskPenLowerSide);
        CGEventSetDoubleValueField(point, kCGTabletEventPointPressure, 0.5);
        CGEventSetDoubleValueField(point, kCGTabletEventTiltX, 0.25);
        CGEventSetDoubleValueField(point, kCGTabletEventTiltY, -0.5);
        CGEventSetDoubleValueField(point, kCGTabletEventRotation, 90);
        CGEventSetDoubleValueField(point, kCGTabletEventTangentialPressure, 0.75);
        CGEventSetIntegerValueField(point, kCGTabletEventDeviceID, 99);
        CGEventSetIntegerValueField(point, kCGTabletEventVendor1, 0x1234);
        CGEventSetIntegerValueField(point, kCGTabletEventVendor2, 0x5678);
        CGEventSetIntegerValueField(point, kCGTabletEventVendor3, 0x140);
        CGEventSetIntegerValueField(point, kCGSTabletPointerID, 42);
        CGEventSetIntegerValueField(point, kCGSTabletSystemTabletID, 0x12345678);
        CGEventSetIntegerValueField(point, kCGSTabletCapabilityMask, 6);
        CGEventSetIntegerValueField(point, kCGSTabletVendorPointerType, 0x140);
        CGEventSetIntegerValueField(point, kCGSTabletPointerType, NSPointingDeviceTypePen);
        CGEventSetIntegerValueField(point, kCGSTabletVendorPointerSerialNumber, 0x1122334455LL);
        post(point);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect([events count] == 1 && [e type] == NSEventTypeTabletPoint,
               "a tablet pointer CGEvent becomes NSEventTypeTabletPoint");
        expect(view->points == 1 && view->lastPoint == e,
               "the pointer event reaches -[NSResponder tabletPoint:]");
        expect(e != nil && near([e pressure], 0.5) && near([e tilt].x, 0.25) &&
                       near([e tilt].y, -0.5) && near([e rotation], 90) &&
                       near([e tangentialPressure], 0.75),
               "pressure, tilt, rotation and tangential pressure are mapped");
        expect(e != nil && ([e buttonMask] & NSEventButtonMaskPenTip) &&
                       ([e buttonMask] & NSEventButtonMaskPenLowerSide),
               "the tip and lower side buttons are reported");
        expect(e != nil && [e absoluteX] == 12345 && [e absoluteY] == 23456 && [e absoluteZ] == 1000,
               "the absolute tablet axes keep the tablet's coordinate space");
        expect(e != nil && [e vendorID] == 0x1234 && [e tabletID] == 0x5678 &&
                       [e pointingDeviceID] == 42 && [e deviceID] == 99 && [e pointingDeviceType] == NSPointingDeviceTypePen,
               "a pointer event keeps the tool identity from the common fields");
        expect(e != nil && NSEventMaskFromType([e type]) == NSEventMaskTabletPoint,
               "the tablet point mask matches the event type");

        // Leaving proximity.
        CGEventRef leave = makeTablet(kCGEventTabletProximity, NSMakePoint(120, 80));
        CGEventSetIntegerValueField(leave, kCGTabletProximityEventEnterProximity, 0);
        post(leave);
        events = drain();
        e = [events count] == 1 ? [events objectAtIndex: 0] : nil;
        expect(view->proximities == 2 && e != nil && ![e isEnteringProximity],
               "leaving proximity reaches the responder with enterProximity = NO");

        printf("%d/%d checks passed\n", checks - failures, checks);
        return failures == 0 ? 0 : 1;
    }
}
