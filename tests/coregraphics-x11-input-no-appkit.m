// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit that has an X11 window of its own (a CGS window) receives the keyboard, the pointer and
// the scroll wheel of that window as CGEvents together: an event tap sees the key down and up with their characters, a
// click, the wheel buttons and the smooth scroll of XInput2 (as raw motion events made here and given to the
// decoder: a test X server has no device with scroll valuators), in the order they were made, with the native window
// of the CGS window. Driven by coregraphics-x11-input-no-appkit.sh (XTest): the program prints "READY <window>"
// with the X window id, then runs its run loop until it sees the key "q" come up or 30 seconds have passed. The
// harness does:
//   the key a, a move over the window, a left click, the wheel buttons 4, 5, 6 and 7
//   the key s (the program feeds the raw events and prints INJECTED), two wheel presses sent as events with the time of
//   the last raw event (dropped) and the next one, the key q
// Usage: coregraphics-x11-input-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n. The "SCROLL" line tells the harness where the first wheel was.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern void *_CGSNativeDisplay(CGSConnectionID cid);

typedef struct {
    int seq;
    CGEventType type;
    int d1, d2;
    double fx1, fx2, pt1, pt2;
    int continuous;
    double x, y;
    int64_t native;
    UniChar character;
    int click;
} Seen;

#define MAX 256
static Seen seen[MAX];
static int count, sequence;
static BOOL quit, inject;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (count >= MAX)
        return event;
    Seen *s = &seen[count++];
    CGPoint location = CGEventGetLocation(event);
    memset(s, 0, sizeof(*s));
    s->seq = ++sequence;
    s->type = type;
    s->x = location.x;
    s->y = location.y;
    s->native = CGEventGetIntegerValueField(event, 182);
    if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        UniCharCount length = 0;
        CGEventKeyboardGetUnicodeString(event, 1, &length, &s->character);
        if (type == kCGEventKeyUp && length == 1 && s->character == 'q')
            quit = YES;
        if (type == kCGEventKeyUp && length == 1 && s->character == 's')
            inject = YES;
    } else if (type == kCGEventScrollWheel) {
        s->d1 = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1);
        s->d2 = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2);
        s->fx1 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
        s->fx2 = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
        s->pt1 = CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis1);
        s->pt2 = CGEventGetDoubleValueField(event, kCGScrollWheelEventPointDeltaAxis2);
        s->continuous = (int) CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous);
    } else {
        s->click = (int) CGEventGetIntegerValueField(event, kCGMouseEventClickState);
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

enum { SourceID = 10, VerticalValuator = 3, LastRawTime = 7000 };

static void feed(id pointer, unsigned long time, double vertical) {
    unsigned char mask[1] = {1 << VerticalValuator};
    double values[1] = {vertical};
    RawEvent raw;
    memset(&raw, 0, sizeof(raw));
    raw.type = 35; // GenericEvent
    raw.evtype = 17; // XI_RawMotion
    raw.time = time;
    raw.deviceid = 2;
    raw.sourceid = SourceID;
    raw.valuators.mask_len = 1;
    raw.valuators.mask = mask;
    raw.valuators.values = values;
    raw.raw_values = values;
    ((void (*)(id, SEL, const RawEvent *)) objc_msgSend)(pointer, sel_registerName("rawMotionEvent:"), &raw);
}

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
    ScrollAxis axes[1] = {{SourceID, VerticalValuator, 0, 10.0}};
    ((void (*)(id, SEL, const ScrollAxis *, int)) objc_msgSend)(pointer, sel_registerName("setScrollAxes:count:"), axes, 1);
    feed(pointer, 1001, 5);              // half a notch down: -5 points
    feed(pointer, LastRawTime, -10);     // one whole notch up: one line
    printf("INJECTED\n");
    fflush(stdout);
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static BOOL near(double a, double b) {
    return fabs(a - b) < 0.01;
}

static int nth(CGEventType type, int n) {
    for (int i = 0; i < count; i++) {
        if (seen[i].type == type && n-- == 0)
            return i;
    }
    return -1;
}

int main(void) {
    @autoreleasepool {
        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        CGRect frame = CGRectMake(100, 100, 400, 300);
        RegionRef region = NULL;
        CGSWindowID wid = 0;
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        if (CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL cannot order the window in\n");
            return 1;
        }
        int64_t native = (int64_t) (intptr_t) _CGSNativeWindowForID(cid, wid);

        CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventLeftMouseDown) |
                           CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventScrollWheel);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        printf("READY %lu\n", (unsigned long) (uintptr_t) native);
        fflush(stdout);

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 30];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.2, false);
            if (inject) {
                inject = NO;
                injectRawEvents();
            }
        }

        printf("tap events %d, native window %lld\n", count, (long long) native);
        for (int i = 0; i < count; i++)
            printf("  tap %3d: type %2d char %c lines %d,%d fixed %.2f,%.2f points %.1f,%.1f continuous %d click %d at %.1f,%.1f native %lld\n", seen[i].seq,
                   (int) seen[i].type, seen[i].character ? (char) seen[i].character : '-', seen[i].d1, seen[i].d2, seen[i].fx1, seen[i].fx2, seen[i].pt1,
                   seen[i].pt2, seen[i].continuous, seen[i].click, seen[i].x, seen[i].y, (long long) seen[i].native);

        int kd = nth(kCGEventKeyDown, 0), ku = nth(kCGEventKeyUp, 0), ld = nth(kCGEventLeftMouseDown, 0), lu = nth(kCGEventLeftMouseUp, 0);
        expect(kd >= 0 && ku > kd && seen[kd].character == 'a' && seen[ku].character == 'a', "the key a: a key down and up with the character a");
        expect(ld > ku && lu > ld && seen[ld].click == 1 && seen[ld].native == native, "a left click: down and up after the key, click state 1, the native window of the CGS window");
        int w[6];
        for (int i = 0; i < 6; i++)
            w[i] = nth(kCGEventScrollWheel, i);
        if (w[5] < 0 || w[0] < lu) {
            printf("FAIL the tap sees fewer than 6 scroll events after the click\nFAILED %d\n", failures + 1);
            return 1;
        }
        printf("SCROLL %.0f %.0f\n", seen[w[0]].x, seen[w[0]].y);
        expect(seen[w[0]].d1 == 1 && seen[w[0]].d2 == 0 && near(seen[w[0]].fx1, 1) && near(seen[w[0]].pt1, 10) && !seen[w[0]].continuous && seen[w[0]].native == native,
               "button 4: one line up, not continuous, the native window of the CGS window");
        expect(seen[w[1]].d1 == -1 && seen[w[1]].d2 == 0, "button 5: one line down");
        expect(seen[w[2]].d1 == 0 && seen[w[2]].d2 == -1, "button 6: one line left");
        expect(seen[w[3]].d1 == 0 && seen[w[3]].d2 == 1, "button 7: one line right");
        expect(seen[w[4]].continuous == 1 && near(seen[w[4]].pt1, -5) && near(seen[w[4]].fx1, -0.5) && seen[w[4]].d1 == -1 && seen[w[4]].native == native,
               "smooth scrolling: half a notch down is -5 points, continuous");
        expect(!seen[w[5]].continuous && seen[w[5]].d1 == 1 && near(seen[w[5]].pt1, 10), "a whole notch in a raw event is a line");
        expect(nth(kCGEventScrollWheel, 6) >= 0 && nth(kCGEventScrollWheel, 7) < 0 && seen[nth(kCGEventScrollWheel, 6)].d1 == 1 && !seen[nth(kCGEventScrollWheel, 6)].continuous,
               "of the two wheel presses sent as events, the one with the time of the raw event is dropped, the other scrolls: 7 scroll events");
        expect(seen[w[1]].seq > seen[w[0]].seq && seen[w[3]].seq > seen[w[2]].seq && seen[w[5]].seq > seen[w[4]].seq, "the events come in the order they were made");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
