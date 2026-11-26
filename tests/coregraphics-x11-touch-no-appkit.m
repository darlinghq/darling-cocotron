// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit that has an X11 window of its own (a CGS window) sees the touch screen fingers and the
// touchpad pinch gestures of that window as CGEvents: an event tap gets a gesture event (type 29) with the finger
// number, the phase and the position for each change of a finger, and magnify and rotate events for a pinch, with the
// window and the position in it as the pointer events have them. A server in the test has no touch device, so the XInput2
// events are made here and given to CoreGraphics' decoder (the entry points the connection's own XInput2 handling feeds).
// Needs an X display (an Xvfb is enough). Usage: coregraphics-x11-touch-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>

// The private fields of the touch and gesture events (CoreGraphicsPrivate.h), and the XInput2 event types.
enum {
    FieldNativeWindow = 182,
    FieldNativeX = 185,
    FieldNativeY = 186,
    FieldPostedX = 187,
    FieldPostedY = 188,
    FieldGesturePhase = 191,
    FieldMagnification = 192,
    FieldRotation = 193,
    FieldTouchIdentifier = 194,
    FieldTouchPhase = 195,
    FieldLocationUnknown = 200,
    TypeGesture = 29,
    TypeRotate = 18,
    TypeMagnify = 30,
    XITouchBegin = 18,
    XITouchUpdate = 19,
    XITouchEnd = 20,
    XIPinchBegin = 27,
    XIPinchUpdate = 28,
    XIPinchEnd = 29,
};

typedef struct {
    int type;
    int64_t identifier, phase, gesturePhase, native, nativeX, nativeY, postedX, postedY, unknown, magnification, rotation;
    double x, y;
} Seen;

#define MAX 64
static Seen seen[MAX];
static int count;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    if (count >= MAX)
        return event;
    Seen *s = &seen[count++];
    CGPoint location = CGEventGetLocation(event);
    s->type = type;
    s->x = location.x;
    s->y = location.y;
    s->identifier = CGEventGetIntegerValueField(event, FieldTouchIdentifier);
    s->phase = CGEventGetIntegerValueField(event, FieldTouchPhase);
    s->gesturePhase = CGEventGetIntegerValueField(event, FieldGesturePhase);
    s->native = CGEventGetIntegerValueField(event, FieldNativeWindow);
    s->nativeX = CGEventGetIntegerValueField(event, FieldNativeX);
    s->nativeY = CGEventGetIntegerValueField(event, FieldNativeY);
    s->postedX = CGEventGetIntegerValueField(event, FieldPostedX);
    s->postedY = CGEventGetIntegerValueField(event, FieldPostedY);
    s->unknown = CGEventGetIntegerValueField(event, FieldLocationUnknown);
    s->magnification = CGEventGetIntegerValueField(event, FieldMagnification);
    s->rotation = CGEventGetIntegerValueField(event, FieldRotation);
    return event;
}

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static void pump(void) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.15, false);
}

int main(void) {
    @autoreleasepool {
        expect(objc_getClass("NSApplication") == nil, "the process does not have AppKit");
        CGSConnectionID cid = CGSMainConnectionID();
        if (cid == 0 || _CGSNativeDisplay(cid) == NULL) {
            printf("FAIL no connection to the window system\n");
            return 1;
        }
        CGRect frame = CGRectMake(100, 100, 400, 300);
        CGSRegionRef region = NULL;
        CGSWindowID wid = 0;
        if (CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess || CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess ||
            CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        unsigned long native = (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid);

        CGEventMask mask = CGEventMaskBit(TypeGesture) | CGEventMaskBit(TypeMagnify) | CGEventMaskBit(TypeRotate);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        Class connection = objc_getClass("CGSConnectionX11");
        id decoder = connection != nil && class_getClassMethod(connection, sel_registerName("_processPointer")) != NULL
                             ? ((id (*)(id, SEL)) objc_msgSend)(connection, sel_registerName("_processPointer"))
                             : nil;
        SEL touchSel = sel_registerName("touchEventType:device:detail:window:x:y:rootX:rootY:");
        SEL pinchSel = sel_registerName("pinchEventType:window:x:y:rootX:rootY:scale:deltaAngle:cancelled:");
        if (decoder == nil || !class_respondsToSelector(object_getClass(decoder), touchSel)) {
            printf("FAIL no X11 pointer decoder with the touch entry point in the process\n");
            return 1;
        }
        void (*touch)(id, SEL, int, int, unsigned, unsigned long, double, double, double, double) =
                (void (*)(id, SEL, int, int, unsigned, unsigned long, double, double, double, double)) objc_msgSend;
        void (*pinch)(id, SEL, int, unsigned long, double, double, double, double, double, double, BOOL) =
                (void (*)(id, SEL, int, unsigned long, double, double, double, double, double, double, BOOL)) objc_msgSend;

        // A finger of device 11, finger 3.
        touch(decoder, touchSel, XITouchBegin, 11, 3, native, 40, 30, 140, 130);
        touch(decoder, touchSel, XITouchUpdate, 11, 3, native, 60, 50, 160, 150);
        touch(decoder, touchSel, XITouchEnd, 11, 3, native, 60, 50, 160, 150);
        pump();
        expect(count == 3, "the tap sees the three changes of the finger");
        int64_t identifier = (11LL << 32) | 3;
        expect(count > 0 && seen[0].type == TypeGesture && seen[0].phase == 1 && seen[0].identifier == identifier,
               "the first is a gesture event of the began phase with the device and finger number");
        expect(count > 0 && seen[0].native == (int64_t) native && seen[0].nativeX == 40 && seen[0].nativeY == 30,
               "it names the window and the position in it in device pixels");
        expect(count > 0 && fabs(seen[0].x - 140) < 1 && fabs(seen[0].y - 130) < 1 &&
                       seen[0].postedX == llround(seen[0].x * 1024) && seen[0].postedY == llround(seen[0].y * 1024),
               "its location is the global one of the finger, and the posted location agrees with it");
        expect(count > 1 && seen[1].phase == 2 && seen[1].nativeX == 60 && seen[1].nativeY == 50 && seen[1].unknown == 0,
               "the move has the moved phase and the new position");
        expect(count > 2 && seen[2].phase == 8 && seen[2].identifier == identifier && seen[2].native == (int64_t) native &&
                       seen[2].unknown == 1,
               "the end has the ended phase, the window and no position");

        count = 0;
        // Fingers of other devices have numbers of their own.
        touch(decoder, touchSel, XITouchBegin, 12, 3, native, 10, 10, 110, 110);
        pump();
        expect(count == 1 && seen[0].identifier == ((12LL << 32) | 3), "the finger number is per device");

        if (class_respondsToSelector(object_getClass(decoder), pinchSel)) {
            count = 0;
            pinch(decoder, pinchSel, XIPinchBegin, native, 40, 30, 140, 130, 1, 0, NO);
            pinch(decoder, pinchSel, XIPinchUpdate, native, 40, 30, 140, 130, 1.5, 10, NO);
            pinch(decoder, pinchSel, XIPinchEnd, native, 40, 30, 140, 130, 1.5, 0, NO);
            pump();
            expect(count == 6, "a pinch makes magnify and rotate events for its begin, update and end");
            expect(count > 3 && seen[0].type == TypeMagnify && seen[0].gesturePhase == 1 && seen[1].type == TypeRotate &&
                           seen[2].type == TypeMagnify && seen[2].gesturePhase == 4 && seen[2].magnification == 500000 &&
                           seen[3].type == TypeRotate && seen[3].rotation == -10000000,
                   "the update has the change of scale and the rotation counterclockwise in millionths");
            expect(count > 5 && seen[5].type == TypeRotate && seen[5].gesturePhase == 8 && seen[4].gesturePhase == 8 &&
                           seen[4].native == (int64_t) native && seen[4].nativeX == 40,
                   "the end has the ended phase and still names the window");
        } else {
            printf("SKIP the pinch (built without XInput 2.4 headers)\n");
        }
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
