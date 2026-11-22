/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// Private-compositor regression fixture, like scroll-frame-dispatch.m: it drives the real
// WaylandDisplay protocol entry point and records the AppKit events it posts. It checks how
// wl_pointer axis events from a finger source become precise scroll events. Written from the
// Wayland core protocol, https://gitlab.freedesktop.org/wayland/wayland/-/blob/main/protocol/wayland.xml
// (wl_pointer.axis, axis_source, axis_stop, frame), and from the NSEvent documentation of
// hasPreciseScrollingDeltas, scrollingDeltaX/Y and phase. The began/changed/ended mapping and the
// sign and line deltas are marked GUESS in WaylandDisplay.m and tested here as the chosen behavior.
// Run it in a Darling guest with DARLING_APPKIT_BACKEND=wayland on a compositor whose seat has a pointer
// (a headless sway has none until a virtual pointer exists: keep tests/wayland-virtual-pointer.c running
// while it runs); the fixture's window must be on that compositor. Prints PASS/FAIL lines and RESULT.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (PreciseScrollFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) windowUnmapped: (id) window;
- (void) seatCapabilities: (uint32_t) capabilities;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
@end

static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;

static void capture(id self, SEL command, NSEvent *event, BOOL atStart) {
    [events addObject: event];
}

static void preciseCheck(BOOL passed, const char *description) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

enum { Axis = 4, Frame = 5, AxisSource = 6, AxisStop = 7 };
enum { Vertical = 0, Horizontal = 1 };
enum { Wheel = 0, Finger = 1 };

static void axis(uint32_t which, double value) {
    union Argument args[3] = {{.u = 0}, {.u = which}, {.i = (int32_t) (value * 256.0)}};
    [display pointerEvent: Axis arguments: args];
}

static void source(uint32_t kind) {
    union Argument args[1] = {{.u = kind}};
    [display pointerEvent: AxisSource arguments: args];
}

static void stop(uint32_t which) {
    union Argument args[2] = {{.u = 0}, {.u = which}};
    [display pointerEvent: AxisStop arguments: args];
}

static void frame(void) {
    [display pointerEvent: Frame arguments: NULL];
}

static NSEvent *last(void) {
    return [events lastObject];
}

@interface PreciseScrollApplication : NSApplication
@end

@implementation PreciseScrollApplication
- (void) test: (id) sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "PreciseScrollRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    preciseCheck(method != NULL, "backend event method exists");
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP) capture,
                    method_getTypeEncoding(method));
    objc_registerClassPair(recorder);
    events = [NSMutableArray new];
    object_setClass(display, recorder);

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 20 * 256}, {.i = 30 * 256}};
    [display pointerEvent: 0 arguments: enter];

    // A finger sequence: began, changed, ended.
    source(Finger);
    axis(Vertical, 20.0);
    frame();
    preciseCheck([events count] == 1 && [last() type] == NSScrollWheel, "finger frame posts one scroll event");
    preciseCheck([last() hasPreciseScrollingDeltas], "finger scroll has precise deltas");
    preciseCheck(fabs([last() scrollingDeltaY] + 20.0) < 0.0001 && [last() scrollingDeltaX] == 0.0,
          "precise deltas are the axis value in points, with the wheel sign");
    preciseCheck([last() phase] == NSEventPhaseBegan, "first frame of a finger sequence is began");
    preciseCheck(fabs([last() deltaY] + 2.0) < 0.0001, "line deltas keep the wheel-notch equivalent");

    source(Finger);
    axis(Vertical, 5.0);
    axis(Horizontal, -10.0);
    frame();
    preciseCheck([events count] == 2 && [last() phase] == NSEventPhaseChanged, "next frame is changed");
    preciseCheck([last() scrollingDeltaY] == -5.0 && [last() scrollingDeltaX] == 10.0,
          "both axes of a frame are combined");

    source(Finger);
    stop(Vertical);
    stop(Horizontal);
    frame();
    preciseCheck([events count] == 3 && [last() phase] == NSEventPhaseEnded &&
              [last() hasPreciseScrollingDeltas] && [last() scrollingDeltaY] == 0.0,
          "axis_stop frames without motion end the sequence");

    source(Finger);
    stop(Vertical);
    frame();
    preciseCheck([events count] == 3, "axis_stop outside a sequence posts nothing");

    source(Finger);
    axis(Vertical, 3.0);
    frame();
    preciseCheck([events count] == 4 && [last() phase] == NSEventPhaseBegan, "a new sequence begins again");

    source(Finger);
    axis(Vertical, 2.0);
    stop(Horizontal);
    frame();
    preciseCheck([events count] == 5 && [last() phase] == NSEventPhaseChanged,
          "an axis_stop beside motion on the other axis does not end the sequence");

    // Leaving in the middle of a sequence cancels it.
    union Argument leave[2] = {{.u = 2}, {.o = [[window platformWindow] surface]}};
    [display pointerEvent: 1 arguments: leave];
    preciseCheck([events count] == 6 && [last() phase] == NSEventPhaseCancelled &&
              [last() hasPreciseScrollingDeltas],
          "pointer leave cancels a sequence in progress");
    [display pointerEvent: 0 arguments: enter];
    source(Finger);
    axis(Vertical, 4.0);
    frame();
    preciseCheck([events count] == 7 && [last() phase] == NSEventPhaseBegan, "a sequence after the cancel begins again");
    source(Finger);
    stop(Vertical);
    frame();
    preciseCheck([events count] == 8 && [last() phase] == NSEventPhaseEnded, "and ends normally");

    // The source is optional in a frame: a sequence goes on and ends in frames that name none.
    NSUInteger base = [events count];
    source(Finger);
    axis(Vertical, 1.0);
    frame();
    axis(Vertical, 6.5);
    frame();
    preciseCheck([events count] == base + 2 && [last() phase] == NSEventPhaseChanged &&
              [last() hasPreciseScrollingDeltas] && [last() scrollingDeltaY] == -6.5,
          "motion in a frame without a source continues the sequence");
    stop(Vertical);
    frame();
    preciseCheck([events count] == base + 3 && [last() phase] == NSEventPhaseEnded,
          "an axis_stop alone, without a source, ends the sequence");

    // axis and axis_stop for the same axis in one frame end the sequence with that motion.
    source(Finger);
    axis(Vertical, 2.0);
    frame();
    source(Finger);
    axis(Vertical, 3.0);
    stop(Vertical);
    frame();
    preciseCheck([events count] == base + 5 && [last() phase] == NSEventPhaseEnded &&
              [last() scrollingDeltaY] == -3.0,
          "axis and axis_stop for the same axis end the sequence");

    // An axis_stop alone ends a sequence whatever source it names.
    source(Finger);
    axis(Vertical, 2.0);
    frame();
    source(Wheel);
    stop(Vertical);
    frame();
    preciseCheck([events count] == base + 7 && [last() phase] == NSEventPhaseEnded,
          "an axis_stop alone with another source still ends the sequence");

    // Losing the pointer in the middle of a sequence cancels it.
    source(Finger);
    axis(Vertical, 2.0);
    frame();
    [display seatCapabilities: 0];
    preciseCheck([events count] == base + 9 && [last() phase] == NSEventPhaseCancelled &&
              [last() hasPreciseScrollingDeltas],
          "seat pointer loss cancels a sequence in progress");
    [display seatCapabilities: 1];
    [display pointerEvent: 0 arguments: enter];

    // Other sources and seats without a source stay legacy wheel events.
    base = [events count];
    source(Wheel);
    axis(Vertical, 20.0);
    frame();
    preciseCheck([events count] == base + 1 && ![last() hasPreciseScrollingDeltas] &&
              [last() phase] == NSEventPhaseNone && fabs([last() deltaY] + 2.0) < 0.0001,
          "wheel source stays a legacy wheel event");
    axis(Vertical, 20.0);
    frame();
    preciseCheck([events count] == base + 2 && ![last() hasPreciseScrollingDeltas] &&
              [last() phase] == NSEventPhaseNone,
          "a frame with no source stays a legacy wheel event");
    source(Wheel);
    stop(Vertical);
    frame();
    preciseCheck([events count] == base + 2, "axis_stop for a wheel source posts nothing");

    // A window that goes away in the middle of a sequence cancels it.
    source(Finger);
    axis(Vertical, 2.0);
    frame();
    [display windowUnmapped: [window platformWindow]];
    preciseCheck([events count] == base + 4 && [last() phase] == NSEventPhaseCancelled &&
              [last() hasPreciseScrollingDeltas],
          "window unmap cancels a sequence in progress");

    object_setClass(display, original);
    [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures);
    exit(failures ? 1 : 0);
}
@end

int main(void) {
    [NSAutoreleasePool new];
    [PreciseScrollApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 240)
        styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
    [window makeKeyAndOrderFront: nil];
    [NSTimer scheduledTimerWithTimeInterval: 0.25 target: NSApp
        selector: @selector(test:) userInfo: nil repeats: NO];
    [NSApp run];
    return 2;
}
