// CFLAGS: -framework Foundation -framework AppKit -framework CoreGraphics
// Copyright (C) 2026 Lubos Dolezel
//
// Tablet tools on the X11 backend: the tablet decoder of CoreGraphics' X11 backend makes tablet CGEvents from the
// XInput2 raw events of a tablet device (the valuators of its axes and its buttons, and what its properties say about the
// tool), and AppKit makes NSEventTypeTabletProximity and NSEventTypeTabletPoint events of them with the accessors the
// documentation names. The same stroke and the same expectations as tests/appkit-tablet-cgevents.m and the Wayland tablet
// session (AppKit/Wayland.backend/tests/tablet-session-probe.m), here with the identity of the tablet and tool given
// the way an X server gives it: the "Device Product ID" and "Wacom Serial IDs" properties. A server in the test has no
// tablet, so the raw events are made here and given to the decoder (the entry points the connection's own XInput2
// handling feeds); where the pointer is comes from the server, so the program waits for the harness
// (appkit-tablet-raw-x11.sh) to put it over the window. It prints READY, then PASS or FAIL lines, then ALL PASSED or FAILED n.
// Usage: appkit-tablet-raw-x11 (no arguments)
#import <AppKit/AppKit.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

// The mirror of Xlib's XIRawEvent (XInput2.h), which the guest SDK does not have
typedef struct {
    int mask_len;
    unsigned char *mask;
    double *values;
} RawValuators;
typedef struct {
    int type;
    unsigned long serial;
    int send_event;
    void *display;
    int extension;
    int evtype;
    unsigned long time;
    int deviceid;
    int sourceid;
    int detail;
    int flags;
    RawValuators valuators;
    double *raw_values;
} RawEvent;
// The mirror of CGSX11TabletDevice (CGSX11Tablet.h)
typedef struct {
    int deviceID;
    int pointerType;
    int pressure, tiltX, tiltY, wheel, distance, absX, absY;
    double pressureMin, pressureMax, distanceMin, distanceMax, wheelMin, wheelMax;
    unsigned int vendorID, productID;
    int hasSerialIDs;
} TabletDevice;

enum {
    XIRawButtonPress = 15,
    XIRawButtonRelease = 16,
    XIRawMotion = 17,
    PenDevice = 31,
    EraserDevice = 32,
    ValuatorX = 0,
    ValuatorY = 1,
    ValuatorPressure = 2,
    ValuatorTiltX = 3,
    ValuatorTiltY = 4,
    ValuatorWheel = 5,
};

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    fflush(stdout);
    if (!ok)
        failures++;
}

@interface TabletView : NSView {
@public
    NSMutableArray *events;
}
@end
@implementation TabletView
- (BOOL) acceptsFirstResponder { return YES; }
- (void) record: (NSEvent *) event {
    if (events == nil)
        events = [NSMutableArray new];
    [events addObject: event];
}
- (void) tabletPoint: (NSEvent *) event { [self record: event]; }
- (void) tabletProximity: (NSEvent *) event { [self record: event]; }
@end

static id tablet;

static void pump(void) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 0.3];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

// A raw event of the device: the six valuators of the tablet (x, y, pressure, tilt x, tilt y, wheel) carry these values
static void feed(int type, int device, int detail, double x, double y, double pressure, double tiltX, double tiltY, double wheel) {
    unsigned char mask[1] = {0x3f};
    double values[6] = {x, y, pressure, tiltX, tiltY, wheel};
    RawEvent raw;
    memset(&raw, 0, sizeof(raw));
    raw.type = 35; // GenericEvent
    raw.evtype = type;
    raw.deviceid = 2;
    raw.sourceid = device;
    raw.detail = detail;
    raw.valuators.mask_len = 1;
    raw.valuators.mask = mask;
    raw.valuators.values = values;
    raw.raw_values = values;
    ((BOOL (*)(id, SEL, const RawEvent *)) objc_msgSend)(tablet, sel_registerName("rawEvent:"), &raw);
    pump();
}

static BOOL near(double a, double b, double epsilon) { return fabs(a - b) <= epsilon; }

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        id display = [NSClassFromString(@"NSDisplay") performSelector: @selector(currentDisplay)];
        if (![NSStringFromClass([display class]) hasPrefix: @"X11"]) {
            printf("SKIP the display is %s, not the X11 backend\n", [NSStringFromClass([display class]) UTF8String]);
            return 77;
        }
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 200)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        TabletView *view = [[TabletView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
        [window setContentView: view];
        [window setFrameTopLeftPoint: NSMakePoint(0, NSMaxY([[NSScreen mainScreen] frame]))];
        [window makeKeyAndOrderFront: nil];
        pump();

        Class connection = objc_getClass("CGSConnectionX11");
        id pointer = connection != nil && class_getClassMethod(connection, sel_registerName("_processPointer")) != NULL
                             ? ((id (*)(id, SEL)) objc_msgSend)(connection, sel_registerName("_processPointer"))
                             : nil;
        tablet = pointer != nil && class_getInstanceMethod(object_getClass(pointer), sel_registerName("tablet")) != NULL
                         ? ((id (*)(id, SEL)) objc_msgSend)(pointer, sel_registerName("tablet"))
                         : nil;
        if (tablet == nil) {
            printf("FAIL no X11 tablet decoder in the process (the server has no XInput2?)\n");
            return 1;
        }
        TabletDevice devices[2] = {
            {PenDevice, 1, ValuatorPressure, ValuatorTiltX, ValuatorTiltY, ValuatorWheel, -1, ValuatorX, ValuatorY,
             0, 65535, 0, 0, -900, 899, 0x1234, 0x5678, 0},
            {EraserDevice, 3, ValuatorPressure, ValuatorTiltX, ValuatorTiltY, ValuatorWheel, -1, ValuatorX, ValuatorY,
             0, 65535, 0, 0, -900, 899, 0x1234, 0x5678, 0},
        };
        ((void (*)(id, SEL, const TabletDevice *, int)) objc_msgSend)(tablet, sel_registerName("setTabletDevices:count:"), devices, 2);
        // What the "Wacom Serial IDs" property of the pen says: the tablet, the tool's serial number and its device id.
        ((void (*)(id, SEL, int, unsigned, unsigned, unsigned)) objc_msgSend)(
                tablet, sel_registerName("setSerialIDsOfDevice:tabletID:serial:toolID:"), PenDevice, 0x5678, 0x22334455, 0x802);
        printf("READY\n");
        fflush(stdout);

        // The harness puts the pointer over the window, at the stroke's first position.
        NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 30];
        BOOL over = NO;
        while (!over && [end timeIntervalSinceNow] > 0) {
            pump();
            NSPoint where = [NSEvent mouseLocation];
            over = NSPointInRect(where, [window frame]);
        }
        expect(over, "the pointer is over the window");
        if (!over)
            return 1;
        // The server has told the process of the window and of the pointer in it by now.
        for (int i = 0; i < 4; i++)
            pump();

        // The stroke of the Wayland session: hover, tip down with pressure and tilt, move, a side button, up, away.
        feed(XIRawMotion, PenDevice, 0, 100, 50, 0, 0, 0, 0);
        feed(XIRawButtonPress, PenDevice, 1, 100, 50, 32768, 30, -20, 0);
        feed(XIRawMotion, PenDevice, 0, 120, 60, 49152, 30, -20, 0);
        feed(XIRawButtonPress, PenDevice, 2, 120, 60, 49152, 30, -20, 450);
        feed(XIRawButtonRelease, PenDevice, 2, 120, 60, 49152, 30, -20, 0);
        feed(XIRawButtonRelease, PenDevice, 1, 120, 60, 0, 30, -20, 0);
        // Another tool's events: not a tablet's (device 99), nothing.
        feed(XIRawMotion, 99, 0, 5, 5, 100, 0, 0, 0);
        NSArray *events = [[view->events copy] autorelease];
        expect([events count] == 7, "a proximity event and six point events for the stroke");

        NSEvent *in = [events count] > 0 ? [events objectAtIndex: 0] : nil;
        expect(in != nil && [in type] == NSEventTypeTabletProximity && [in isEnteringProximity],
               "the first event is the tool entering proximity");
        expect(in != nil && [in pointingDeviceType] == NSPointingDeviceTypePen, "the tool is a pen");
        expect(in != nil && [in vendorID] == 0x1234 && [in tabletID] == 0x5678 && [in systemTabletID] == (NSUInteger) (0x1234ULL << 32 | 0x5678),
               "the tablet's vendor, product and system tablet ids");
        expect(in != nil && [in pointingDeviceSerialNumber] == 0x22334455 && [in uniqueID] == 0x22334455ULL &&
                       [in pointingDeviceID] == 0x22334455,
               "the tool's serial number is its serial number, unique id and pointing device id");
        expect(in != nil && [in vendorPointingDeviceType] == 0x802, "the vendor's tool type is the tool's device id");
        expect(in != nil && [in deviceID] != 0 && [in capabilityMask] == ((1 << 1) | (1 << 2) | (1 << 5)),
               "a device id, and tilt, pressure and slider capabilities");

        NSEvent *hover = [events count] > 1 ? [events objectAtIndex: 1] : nil;
        expect(hover != nil && [hover type] == NSEventTypeTabletPoint && near([hover pressure], 0, 0.001) &&
                       near([hover locationInWindow].x, 100, 0.5) && near([hover locationInWindow].y, 150, 0.5) &&
                       [hover absoluteX] == 100 && [hover absoluteY] == 50,
               "the hovering tool is at its position in the window (y up) and keeps the tablet's axes");
        expect(hover != nil && [hover pointingDeviceID] == 0x22334455 && [hover vendorID] == 0x1234 &&
                       [hover pointingDeviceType] == NSPointingDeviceTypePen && [hover deviceID] == [in deviceID],
               "a point event keeps the tool's identity");
        NSEvent *down = [events count] > 2 ? [events objectAtIndex: 2] : nil;
        expect(down != nil && near([down pressure], 0.5, 0.001) && near([down tilt].x, 30.0 / 90, 0.001) &&
                       near([down tilt].y, -20.0 / 90, 0.001) && ([down buttonMask] & NSEventButtonMaskPenTip),
               "pressure 0.5, tilt of 30 and -20 degrees as -1 to 1, and the tip in the button mask");
        NSEvent *moved = [events count] > 3 ? [events objectAtIndex: 3] : nil;
        // The position is the pointer's, which the server keeps where the harness put it; the tablet's own axes move.
        expect(moved != nil && near([moved pressure], 0.75, 0.001) && near([moved locationInWindow].x, 100, 0.5) &&
                       near([moved locationInWindow].y, 150, 0.5) && [moved absoluteX] == 120 && [moved absoluteY] == 60,
               "pressure 0.75, and the tablet's axes at the moved position");
        NSEvent *side = [events count] > 4 ? [events objectAtIndex: 4] : nil;
        expect(side != nil && ([side buttonMask] & NSEventButtonMaskPenLowerSide) && ([side buttonMask] & NSEventButtonMaskPenTip) &&
                       near([side tangentialPressure], 450.0 / 900, 0.001),
               "the side button joins the tip in the button mask, and the wheel is the tangential pressure");
        NSEvent *sideUp = [events count] > 5 ? [events objectAtIndex: 5] : nil;
        expect(sideUp != nil && [sideUp buttonMask] == NSEventButtonMaskPenTip,
               "the button mask has only the tip once the side button is released");
        NSEvent *up = [events count] > 6 ? [events objectAtIndex: 6] : nil;
        expect(up != nil && [up buttonMask] == 0 && near([up pressure], 0, 0.001), "and nothing once the tip is up");

        // The eraser: its own device, another kind of tool. One tool is in proximity at a time.
        [view->events removeAllObjects];
        feed(XIRawMotion, EraserDevice, 0, 100, 50, 0, 0, 0, 0);
        events = [[view->events copy] autorelease];
        expect([events count] == 3 && [[events objectAtIndex: 0] type] == NSEventTypeTabletProximity &&
                       ![[events objectAtIndex: 0] isEnteringProximity] && [[events objectAtIndex: 0] pointingDeviceType] == NSPointingDeviceTypePen,
               "the pen leaves proximity when the eraser comes");
        NSEvent *eraser = [events count] > 1 ? [events objectAtIndex: 1] : nil;
        expect(eraser != nil && [eraser isEnteringProximity] && [eraser pointingDeviceType] == NSPointingDeviceTypeEraser &&
                       [eraser deviceID] != [in deviceID] && [eraser pointingDeviceSerialNumber] == 0,
               "the eraser enters proximity as an eraser, a device of its own with no serial number");

        // The tool leaves with the window it was over.
        [view->events removeAllObjects];
        [window close];
        pump();
        events = [[view->events copy] autorelease];
        expect([events count] == 1 && [[events objectAtIndex: 0] type] == NSEventTypeTabletProximity &&
                       ![[events objectAtIndex: 0] isEnteringProximity] &&
                       [[events objectAtIndex: 0] pointingDeviceType] == NSPointingDeviceTypeEraser,
               "the tool leaves proximity when its window goes away");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
