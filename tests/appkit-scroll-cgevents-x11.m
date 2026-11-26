// CFLAGS: -framework Foundation -framework AppKit -framework Carbon -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The scroll wheel of the X server reaches AppKit as scroll CGEvents: the event taps of the process see what
// CoreGraphics decodes from the wheel buttons (4 to 7) and the XInput2 smooth scrolling (line deltas of the wheel
// clicks, continuous point deltas of smooth scrolling, the fixed-point deltas, the modifier flags and the global
// location), a wheel does not make mouse events or change the click state, and the NSEvents AppKit makes are made
// from the CGEvents (scrollingDeltaX/Y, hasPreciseScrollingDeltas, and the Shift quirk). An X server in the test
// has no device with scroll valuators, so the smooth scrolling is tested with raw motion events made here and given
// to the decoder (the entry points the connection's own XInput2 handling feeds). Driven by
// appkit-scroll-cgevents-x11.sh (XTest): the program prints READY, then reads events until it sees the key "q" come
// up or 60 seconds have passed. The key "s" makes it feed the raw events (and print INJECTED when it is done).
// The harness does, with the pointer over the window at P:
//   a left click, the wheel buttons 4, 5, 6, 7, three times button 4, button 4 with Shift held, a left click, button 4
//   the key s; then, with the server times of the raw events known, two wheel presses sent as events (XSendEvent)
//   with the time of the last raw event (it must be dropped: the server emulates the buttons for a smooth scroll
//   and the raw event scrolled already) and with the next time (it scrolls)
//   the key q
// Usage: appkit-scroll-cgevents-x11 (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n. The "SCROLL" line tells the harness where the first wheel was.
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>

enum {
    DeviceLeftShift = 0x2,
};

typedef struct {
    int seq;
    CGEventType type;
    int click;
    double x, y;
    int d1, d2;
    double fx1, fx2, pt1, pt2;
    int continuous, phase, momentum;
    uint64_t flags;
    int64_t nativeWindow;
} Seen;

typedef struct {
    int seq;
    double dx, dy, sdx, sdy;
    int precise;
    int hasWindow;
    uint64_t flags;
    double wx, wy;
} NSSeen;

#define MAX 256
static Seen tapScroll[MAX];
static NSSeen nsScroll[MAX];
static int tapScrollCount, nsScrollCount, tapClicks, tapOtherMouse, sequence;
static int clickStates[8], clickStateCount;
static BOOL quit, inject;
static NSWindow *window;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (type == kCGEventScrollWheel) {
        if (tapScrollCount < MAX) {
            Seen *s = &tapScroll[tapScrollCount++];
            CGPoint location = CGEventGetLocation(event);
            s->seq = ++sequence;
            s->type = type;
            s->x = location.x;
            s->y = location.y;
            s->d1 = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
            s->d2 = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2);
            s->fx1 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
            s->fx2 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
            s->pt1 = CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1);
            s->pt2 = CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis2);
            s->continuous = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous);
            s->phase = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
            s->momentum = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventMomentumPhase);
            s->flags = CGEventGetFlags(event);
            s->nativeWindow = CGEventGetIntegerValueField(event, 182);
        }
    } else if (type == kCGEventLeftMouseDown) {
        tapClicks++;
        if (clickStateCount < 8)
            clickStates[clickStateCount++] = (int) CGEventGetIntegerValueField(event, kCGMouseEventClickState);
    } else if (type != kCGEventKeyDown && type != kCGEventKeyUp && type != kCGEventFlagsChanged && type != kCGEventLeftMouseUp &&
               type != kCGEventMouseMoved) {
        tapOtherMouse++;
    }
    return event;
}

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
// The mirror of CGSX11ScrollAxis
typedef struct {
    int sourceID;
    int valuator;
    int horizontal;
    double increment;
} ScrollAxis;

enum { SourceID = 10, HorizontalValuator = 2, VerticalValuator = 3 };

// A raw motion event of the device with the two scroll valuators changed by the values (0 leaves one out)
static void feed(id pointer, unsigned long time, int sourceid, double vertical, double horizontal) {
    unsigned char mask[1] = {0};
    double values[2];
    int n = 0;
    if (horizontal != 0) {
        mask[0] |= 1 << HorizontalValuator;
        values[n++] = horizontal;
    }
    if (vertical != 0) {
        mask[0] |= 1 << VerticalValuator;
        values[n++] = vertical;
    }
    RawEvent raw;
    memset(&raw, 0, sizeof(raw));
    raw.type = 35; // GenericEvent
    raw.evtype = 17; // XI_RawMotion
    raw.time = time;
    raw.deviceid = 2;
    raw.sourceid = sourceid;
    raw.valuators.mask_len = 1;
    raw.valuators.mask = mask;
    raw.valuators.values = values;
    raw.raw_values = values;
    ((void (*)(id, SEL, const RawEvent *)) objc_msgSend)(pointer, sel_registerName("rawMotionEvent:"), &raw);
}

enum { LastRawTime = 7000 };

static void injectRawEvents(void) {
    Class connection = objc_getClass("CGSConnectionX11");
    id pointer = connection != nil && class_getClassMethod(connection, sel_registerName("_processPointer")) != NULL
                         ? ((id (*)(id, SEL)) objc_msgSend)(connection, sel_registerName("_processPointer"))
                         : nil;
    if (pointer == nil || class_getInstanceMethod(object_getClass(pointer), sel_registerName("rawMotionEvent:")) == NULL) {
        printf("FAIL no X11 pointer decoder with the raw motion entry point in the process\nINJECTED\n");
        fflush(stdout);
        return;
    }
    ScrollAxis axes[2] = {{SourceID, HorizontalValuator, 1, 10.0}, {SourceID, VerticalValuator, 0, 10.0}};
    ((void (*)(id, SEL, const ScrollAxis *, int)) objc_msgSend)(pointer, sel_registerName("setScrollAxes:count:"), axes, 2);
    feed(pointer, 1001, SourceID, 5, 0);        // 1/2 notch down: -5 points
    feed(pointer, 1002, SourceID, 0, -7);       // 0.7 notch left: -7 points
    feed(pointer, 1003, SourceID, 2.5, 2.5);    // a quarter notch down and right: -2 and 2 points, the halves carried
    feed(pointer, 1004, SourceID, 2.5, 0);      // -3 (the carried -0.5 added), 0
    feed(pointer, 1005, 99, 20, 0);             // a device that has no scroll axis: nothing
    feed(pointer, 1006, 0, 5, 0);               // a raw event with no source (old libXi): the axes of the first device
    feed(pointer, LastRawTime, SourceID, -20, 0); // two whole notches up: a wheel of two lines
    printf("INJECTED\n");
    fflush(stdout);
}

@interface ScrollApplication : NSApplication
@end

@implementation ScrollApplication
- (void) sendEvent: (NSEvent *) event {
    NSEventType type = [event type];
    if (type == NSEventTypeKeyUp && [[event characters] isEqualToString: @"q"])
        quit = YES;
    if (type == NSEventTypeKeyUp && [[event characters] isEqualToString: @"s"])
        inject = YES;
    if (type == NSEventTypeScrollWheel && nsScrollCount < MAX) {
        NSSeen *s = &nsScroll[nsScrollCount++];
        s->seq = ++sequence;
        s->dx = [event deltaX];
        s->dy = [event deltaY];
        s->sdx = [event scrollingDeltaX];
        s->sdy = [event scrollingDeltaY];
        s->precise = [event hasPreciseScrollingDeltas];
        s->hasWindow = [event window] == window;
        s->flags = [event modifierFlags];
        NSPoint where = [event locationInWindow];
        s->wx = where.x;
        s->wy = where.y;
    }
    [super sendEvent: event];
}
@end

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

static BOOL near(double a, double b) {
    return fabs(a - b) < 0.01;
}

// Whether the nth scroll CGEvent has the line form: the deltas are whole lines, not continuous, with the fixed
// point equal to the lines and the points equal to ten per line (what CGEventCreateScrollWheelEvent2 gives)
static BOOL isLines(int n, int vertical, int horizontal) {
    if (n >= tapScrollCount)
        return NO;
    Seen *s = &tapScroll[n];
    return s->d1 == vertical && s->d2 == horizontal && near(s->fx1, vertical) && near(s->fx2, horizontal) &&
           near(s->pt1, vertical * 10) && near(s->pt2, horizontal * 10) && !s->continuous && s->phase == 0 && s->momentum == 0;
}

// The continuous form: the points are the delta, the fixed point is a tenth of them, the line count at least one
// line of the sign of the movement
static BOOL isPoints(int n, int vertical, int horizontal) {
    if (n >= tapScrollCount)
        return NO;
    Seen *s = &tapScroll[n];
    int lines1 = vertical == 0 ? 0 : (abs(vertical) < 10 ? (vertical < 0 ? -1 : 1) : vertical / 10);
    int lines2 = horizontal == 0 ? 0 : (abs(horizontal) < 10 ? (horizontal < 0 ? -1 : 1) : horizontal / 10);
    return near(s->pt1, vertical) && near(s->pt2, horizontal) && near(s->fx1, vertical / 10.0) && near(s->fx2, horizontal / 10.0) &&
           s->d1 == lines1 && s->d2 == lines2 && s->continuous == 1 && s->phase == 0 && s->momentum == 0;
}

int main(void) {
    @autoreleasepool {
        ScrollApplication *app = (ScrollApplication *) [ScrollApplication sharedApplication];
        [app setActivationPolicy: NSApplicationActivationPolicyRegular];

        CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel) | CGEventMaskBit(kCGEventLeftMouseDown);
        for (CGEventType t = kCGEventRightMouseDown; t <= kCGEventOtherMouseDragged; t++)
            if (t != kCGEventScrollWheel && t != kCGEventKeyDown && t != kCGEventKeyUp && t != kCGEventFlagsChanged &&
                t != kCGEventLeftMouseUp && t != kCGEventMouseMoved && t != kCGEventLeftMouseDragged)
                mask |= CGEventMaskBit(t);
        mask |= CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask,
                                             tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 500, 400)
                                             styleMask: NSTitledWindowMask
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        [window setTitle: @"scroll-cgevents-x11"];
        [window makeKeyAndOrderFront: nil];
        [app finishLaunching];
        printf("READY\n");
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [app nextEventMatchingMask: NSEventMaskAny
                                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
            if (event != nil)
                [app sendEvent: event];
            if (inject) {
                inject = NO;
                injectRawEvents();
            }
        }
        printf("tap scroll events %d, NSEvents %d\n", tapScrollCount, nsScrollCount);
        for (int i = 0; i < tapScrollCount; i++) {
            Seen *s = &tapScroll[i];
            printf("  tap %3d: lines %d,%d fixed %.3f,%.3f points %.1f,%.1f continuous %d phase %d,%d flags %#llx at %.1f,%.1f window %lld\n", s->seq, s->d1,
                   s->d2, s->fx1, s->fx2, s->pt1, s->pt2, s->continuous, s->phase, s->momentum, (unsigned long long) s->flags, s->x, s->y,
                   (long long) s->nativeWindow);
        }
        for (int i = 0; i < nsScrollCount; i++) {
            NSSeen *s = &nsScroll[i];
            printf("  ns  %3d: delta %.3f,%.3f scrolling %.1f,%.1f precise %d window %d flags %#llx at %.1f,%.1f\n", s->seq, s->dx, s->dy, s->sdx,
                   s->sdy, s->precise, s->hasWindow, (unsigned long long) s->flags, s->wx, s->wy);
        }
        if (tapScrollCount > 0)
            printf("SCROLL %.0f %.0f\n", tapScroll[0].x, tapScroll[0].y);

        // The order of the events: 0 to 8 are the wheel buttons, 9 to 14 the raw events, 15 the sent press
        expect(tapScrollCount == 16, [NSString stringWithFormat: @"the tap sees 16 scroll events (%d)", tapScrollCount]);
        expect(isLines(0, 1, 0), @"button 4 is one line up: lines (1, 0), fixed-point 1, points 10, not continuous");
        expect(isLines(1, -1, 0), @"button 5 is one line down: lines (-1, 0)");
        expect(isLines(2, 0, -1), @"button 6 is one line left: lines (0, -1)");
        expect(isLines(3, 0, 1), @"button 7 is one line right: lines (0, 1)");
        expect(isLines(4, 1, 0) && isLines(5, 1, 0) && isLines(6, 1, 0), @"three notches of button 4 are three events");
        expect(isLines(7, 1, 0) && (tapScroll[7].flags & kCGEventFlagMaskShift) && (tapScroll[7].flags & DeviceLeftShift),
               @"button 4 with Shift held: the CGEvent keeps the line deltas and has the Shift flag with the left device bit");
        expect(isLines(8, 1, 0) && !(tapScroll[8].flags & kCGEventFlagMaskShift), @"button 4 after the Shift is released has no Shift flag");
        expect(tapClicks == 2 && clickStateCount == 2 && clickStates[0] == 1 && clickStates[1] == 2 && tapOtherMouse == 0,
               [NSString stringWithFormat: @"the wheel makes no mouse events and does not touch the click state: two clicks around wheel notches are click states 1 and 2 (%d clicks, %d,%d, other mouse events %d)",
                                           tapClicks, clickStateCount > 0 ? clickStates[0] : -1, clickStateCount > 1 ? clickStates[1] : -1, tapOtherMouse]);
        expect(tapScrollCount > 0 && tapScroll[0].nativeWindow != 0, @"the scroll event names the window system window it is for");

        // The raw events of the smooth scrolling
        expect(isPoints(9, -5, 0), @"half a notch down is a continuous scroll of -5 points: points (-5, 0), fixed-point -0.5, one line");
        expect(isPoints(10, 0, -7), @"0.7 notch left is -7 points on the horizontal axis");
        expect(isPoints(11, -2, 2), @"both axes in one event: -2 and 2 points, the halves carried to the next event");
        expect(isPoints(12, -3, 0), @"the carried half and the next quarter notch make -3 points");
        expect(isPoints(13, -5, 0), @"a raw event with the source 0 (some libXi versions) scrolls by the axes of the first device that has the valuator");
        expect(isLines(14, 2, 0), @"two whole notches up in a raw event are a wheel of two lines (not continuous)");
        expect(isLines(15, 1, 0), @"the wheel press with the time of the raw event was dropped (the server emulated it), the press with the next time scrolls");

        // The NSEvents made from the CGEvents
        expect(nsScrollCount == 16, [NSString stringWithFormat: @"AppKit gets 16 scroll events (%d)", nsScrollCount]);
        if (nsScrollCount == 16) {
            NSSeen *n = nsScroll;
            expect(n[0].dx == 0 && near(n[0].dy, 1) && near(n[0].sdy, 1) && !n[0].precise && n[0].hasWindow, @"button 4: deltaY 1, scrollingDeltaY 1, not precise, the window");
            expect(near(n[1].dy, -1) && near(n[2].dx, -1) && near(n[3].dx, 1), @"buttons 5, 6, 7: deltaY -1, deltaX -1, deltaX 1");
            expect(n[0].wx > 0 && n[0].wx < 500 && n[0].wy > 0 && n[0].wy < 400, @"the location in the window is inside it");
            expect(near(n[7].dx, 1) && near(n[7].dy, 0) && (n[7].flags & NSEventModifierFlagShift) && near(n[8].dy, 1) && near(n[8].dx, 0),
                   @"QUIRK (Shift): the NSEvent of a wheel line with Shift held scrolls sideways: deltaX 1, deltaY 0; without Shift it is deltaY again");
            expect(n[9].precise && near(n[9].sdy, -5) && near(n[9].sdx, 0) && near(n[9].dy, -0.5) && n[9].hasWindow,
                   @"continuous: hasPreciseScrollingDeltas, scrollingDeltaY -5 points, deltaY -0.5");
            expect(n[11].precise && near(n[11].sdy, -2) && near(n[11].sdx, 2) && near(n[11].dx, 0.2), @"both axes: scrollingDelta (2, -2)");
            expect(!n[14].precise && near(n[14].dy, 2) && near(n[14].sdy, 2), @"two wheel lines: not precise, deltaY 2");
        }
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
