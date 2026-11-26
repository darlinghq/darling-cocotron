// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit that has a Wayland window of its own (a CGS window) sees the touch screen fingers of that
// window as CGEvents: an event tap gets a gesture event (type 29) with the finger number, the phase and the position for
// each change of a finger, and the window and the position in it as the pointer events have them. A compositor in the
// test has no touch screen, so the wl_touch events are made here and given to CoreGraphics' touch decoder (the entry point
// the connection's own wl_touch dispatch feeds; the arguments are those of the wl_touch protocol,
// https://wayland.app/protocols/wayland#wl_touch). Needs a compositor (a headless sway is enough).
// Usage: coregraphics-wayland-touch-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>

// The private fields of the touch events (CoreGraphicsPrivate.h).
enum {
    FieldNativeWindow = 182,
    FieldNativeX = 185,
    FieldNativeY = 186,
    FieldPostedX = 187,
    FieldPostedY = 188,
    FieldTouchIdentifier = 194,
    FieldTouchPhase = 195,
    FieldLocationUnknown = 200,
    TypeGesture = 29,
};
enum { WlDown = 0, WlUp = 1, WlMotion = 2, WlCancel = 4 };
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int32_t f; int h; };

typedef struct {
    int type;
    int64_t identifier, phase, native, nativeX, nativeY, postedX, postedY, unknown;
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
    s->native = CGEventGetIntegerValueField(event, FieldNativeWindow);
    s->nativeX = CGEventGetIntegerValueField(event, FieldNativeX);
    s->nativeY = CGEventGetIntegerValueField(event, FieldNativeY);
    s->postedX = CGEventGetIntegerValueField(event, FieldPostedX);
    s->postedY = CGEventGetIntegerValueField(event, FieldPostedY);
    s->unknown = CGEventGetIntegerValueField(event, FieldLocationUnknown);
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

static id decoder;
static void *surface;

static void touchEvent(uint32_t opcode, union Argument *args) {
    ((void (*)(id, SEL, uint32_t, union Argument *)) objc_msgSend)(decoder, sel_registerName("touchEvent:arguments:"), opcode, args);
    pump();
}
static void down(int finger, double x, double y) {
    union Argument a[6] = {{.u = 1}, {.u = 0}, {.o = surface}, {.i = finger}, {.f = (int32_t) (x * 256)}, {.f = (int32_t) (y * 256)}};
    touchEvent(WlDown, a);
}
static void motion(int finger, double x, double y) {
    union Argument a[4] = {{.u = 0}, {.i = finger}, {.f = (int32_t) (x * 256)}, {.f = (int32_t) (y * 256)}};
    touchEvent(WlMotion, a);
}
static void up(int finger) {
    union Argument a[3] = {{.u = 1}, {.u = 0}, {.i = finger}};
    touchEvent(WlUp, a);
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
        surface = _CGSNativeWindowForID(cid, wid);

        id connection = (id) _CGSConnectionForID(cid);
        Ivar ivar = connection != nil ? class_getInstanceVariable(object_getClass(connection), "_touchDecoder") : NULL;
        decoder = ivar != NULL ? object_getIvar(connection, ivar) : nil;
        if (decoder == nil || surface == NULL ||
            !class_respondsToSelector(object_getClass(decoder), sel_registerName("touchEvent:arguments:"))) {
            printf("FAIL no Wayland touch decoder with the wl_touch entry point in the process\n");
            return 1;
        }
        CGEventMask mask = CGEventMaskBit(TypeGesture);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        down(7, 40, 30);
        motion(7, 60, 50);
        up(7);
        expect(count == 3, "the tap sees the three changes of the finger");
        expect(count > 0 && seen[0].type == TypeGesture && seen[0].phase == 1 && seen[0].identifier == 7,
               "the first is a gesture event of the began phase with the finger number");
        expect(count > 0 && seen[0].native == (int64_t) (intptr_t) surface && seen[0].nativeX == 40 * 1024 && seen[0].nativeY == 30 * 1024,
               "it names the surface and the position in it in 1/1024 points");
        expect(count > 0 && seen[0].postedX == llround(seen[0].x * 1024) && seen[0].postedY == llround(seen[0].y * 1024) &&
                       fabs(seen[0].x - 140) < 1 && fabs(seen[0].y - 130) < 1,
               "its location is the global one of the finger (the window's origin and the point), and the posted location agrees");
        expect(count > 1 && seen[1].phase == 2 && seen[1].nativeX == 60 * 1024 && seen[1].nativeY == 50 * 1024 && seen[1].unknown == 0,
               "the move has the moved phase and the new position");
        expect(count > 2 && seen[2].phase == 8 && seen[2].identifier == 7 && seen[2].native == (int64_t) (intptr_t) surface &&
                       seen[2].unknown == 1,
               "the up has the ended phase, the surface and no position");

        count = 0;
        motion(7, 70, 70);
        up(7);
        expect(count == 0, "the motion and the up of a finger that is not down are ignored");

        down(1, 10, 10);
        down(2, 20, 20);
        count = 0;
        union Argument none[1] = {{.u = 0}};
        touchEvent(WlCancel, none);
        expect(count == 2 && seen[0].phase == 16 && seen[1].phase == 16 && seen[0].unknown == 1 &&
                       ((seen[0].identifier == 1 && seen[1].identifier == 2) || (seen[0].identifier == 2 && seen[1].identifier == 1)),
               "a cancel of the compositor cancels every finger that is down, with no position");
        count = 0;
        up(1);
        expect(count == 0, "a finger that was cancelled is gone");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
