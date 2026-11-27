/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Private-compositor regression fixture. It drives the pinch-gesture entry point of CoreGraphics' pointer
// decoder (the process' wl_pointer), takes the AppKit events made from the CGEvents it posts, and checks
// that NSWindow delivers them to the view under the pointer.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (PinchFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) pinchEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) holdEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) windowUnmapped: (id) window;
- (void) seatCapabilities: (uint32_t) capabilities seat: (void *) seat;
@end


static NSMutableArray *events;
static id display, decoder, connection;
static NSWindow *window;
static int failures, checks;

// The decoder is CoreGraphics': what it posts becomes NSEvents in AppKit's queue
static void drain(void) {
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil)
        [events addObject: event];
}

static id ivarOf(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static void pinchCheck(BOOL passed, const char *description) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

static BOOL isGesture(NSUInteger index, NSEventType type, NSEventPhase phase) {
    drain();
    if (index >= [events count])
        return NO;
    NSEvent *event = [events objectAtIndex: index];
    return [event type] == type && [event phase] == phase && [event window] == window;
}

static void *pinchProxy(void) {
    Ivar ivar = class_getInstanceVariable(object_getClass(decoder), "_pinch");
    return *(void **) ((char *) decoder + ivar_getOffset(ivar));
}

static void begin(void) {
    union Argument args[4] = {{.u = 7}, {.u = 100}, {.o = [[window platformWindow] surface]}, {.u = 2}};
    [decoder pinchEvent: 0 arguments: args];
    drain();
}

static void update(double scale, double clockwiseDegrees) {
    union Argument args[5] = {{.u = 101}, {.i = 0}, {.i = 0},
                              {.i = (int32_t) (scale * 256.0)}, {.i = (int32_t) (clockwiseDegrees * 256.0)}};
    [decoder pinchEvent: 1 arguments: args];
    drain();
}

static void end(int cancelled) {
    union Argument args[3] = {{.u = 8}, {.u = 102}, {.i = cancelled}};
    [decoder pinchEvent: 2 arguments: args];
    drain();
}

// pointer-gestures v3's hold has a begin and an end, with no update stage.
static void holdBegin(void) {
    union Argument args[3] = {{.u = 9}, {.u = 103}, {.o = [[window platformWindow] surface]}};
    [decoder holdEvent: 0 arguments: args];
    drain();
}

static void holdEnd(int cancelled) {
    union Argument args[3] = {{.u = 10}, {.u = 104}, {.i = cancelled}};
    [decoder holdEvent: 1 arguments: args];
    drain();
}

@interface GestureView : NSView {
    // Declared and synthesized here: the i386 slice has the legacy Objective-C ABI, which has no automatic synthesis.
    NSInteger _magnifications, _rotations;
    CGFloat _totalMagnification;
    float _totalRotation;
}
@property NSInteger magnifications, rotations;
@property CGFloat totalMagnification;
@property float totalRotation;
@end

@implementation GestureView
@synthesize magnifications = _magnifications, rotations = _rotations;
@synthesize totalMagnification = _totalMagnification, totalRotation = _totalRotation;
- (void) magnifyWithEvent: (NSEvent *) event {
    self.magnifications++;
    self.totalMagnification += [event magnification];
}
- (void) rotateWithEvent: (NSEvent *) event {
    self.rotations++;
    self.totalRotation += [event rotation];
}
@end

@interface PinchApplication : NSApplication
@end

@implementation PinchApplication
- (void) test: (id) sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    if (![NSStringFromClass(object_getClass(display)) hasPrefix: @"Wayland"]) {
        printf("SKIP the display is %s, not the Wayland backend\n", [NSStringFromClass(object_getClass(display)) UTF8String]);
        exit(77);
    }
    connection = _CGSConnectionForID(CGSMainConnectionID());
    decoder = ivarOf(connection, "_pointerDecoder");
    events = [NSMutableArray new];
    drain();
    [events removeAllObjects];

    // A headless compositor has no pointer device; take the capability so the decoder requests its pinch
    // object for real.
    [decoder seatCapabilities: 1 seat: (void *) ivarOf(connection, "_seat")];
    pinchCheck(pinchProxy() != NULL, "a pointer gets a pinch gesture object");

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 40 * 256}, {.i = 30 * 256}};
    [decoder pointerEvent: 0 arguments: enter];

    begin();
    pinchCheck([events count] == 2 && isGesture(0, NSEventTypeMagnify, NSEventPhaseBegan) &&
              isGesture(1, NSEventTypeRotate, NSEventPhaseBegan),
          "pinch begin posts began magnify and rotate events");
    update(1.5, 10);
    NSEvent *magnify = [events count] > 2 ? [events objectAtIndex: 2] : nil;
    NSEvent *rotate = [events count] > 3 ? [events objectAtIndex: 3] : nil;
    pinchCheck([events count] == 4 && isGesture(2, NSEventTypeMagnify, NSEventPhaseChanged) &&
              fabs([magnify magnification] - 0.5) < 0.01 &&
              isGesture(3, NSEventTypeRotate, NSEventPhaseChanged) && fabs([rotate rotation] + 10) < 0.01,
          "update posts the scale change and counterclockwise rotation");
    drain();
    pinchCheck(NSEqualPoints([magnify locationInWindow], [window mouseLocationOutsideOfEventStream]),
          "gesture events carry the pointer location");
    update(1.25, 0);
    pinchCheck([events count] == 5 && isGesture(4, NSEventTypeMagnify, NSEventPhaseChanged) &&
              fabs([(NSEvent *) [events objectAtIndex: 4] magnification] + 0.25) < 0.01,
          "a pinch without rotation posts only a magnify change");
    update(1.25, 0);
    pinchCheck([events count] == 5, "an unchanged update posts nothing");
    end(0);
    pinchCheck([events count] == 7 && isGesture(5, NSEventTypeMagnify, NSEventPhaseEnded) &&
              isGesture(6, NSEventTypeRotate, NSEventPhaseEnded),
          "pinch end posts ended events");

    begin();
    end(1);
    pinchCheck([events count] == 11 && isGesture(9, NSEventTypeMagnify, NSEventPhaseCancelled) &&
              isGesture(10, NSEventTypeRotate, NSEventPhaseCancelled),
          "a cancelled pinch posts cancelled events");

    begin();
    [display windowUnmapped: [window platformWindow]];
    drain();
    update(2, 5);
    end(0);
    pinchCheck([events count] == 15 && isGesture(13, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(14, NSEventTypeRotate, NSEventPhaseCancelled),
               "window unmap cancels an active pinch and drops the rest of it");

    [decoder pointerEvent: 0 arguments: enter];
    begin();
    [decoder seatCapabilities: 0 seat: NULL];
    drain();
    pinchCheck(pinchProxy() == NULL && [events count] == 19 &&
                   isGesture(17, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(18, NSEventTypeRotate, NSEventPhaseCancelled),
               "losing the pointer cancels an active pinch and destroys its object");

    drain();

    GestureView *view = [[GestureView alloc] initWithFrame: [[window contentView] bounds]];
    [window setContentView: view];
    for (NSEvent *event in events)
        [window sendEvent: event];
    pinchCheck(view.magnifications == 10 && view.rotations == 9 && fabs(view.totalMagnification - 0.25) < 0.01 &&
              fabs(view.totalRotation + 10) < 0.01,
          "NSWindow sends magnify and rotate events to the view under the pointer");

    holdBegin();
    pinchCheck([events count] == 20 && isGesture(19, NSEventTypeScrollWheel, NSEventPhaseBegan),
           "a hold begin posts a zero-delta scroll began event");
    holdEnd(0);
    pinchCheck([events count] == 21 && isGesture(20, NSEventTypeScrollWheel, NSEventPhaseEnded),
           "a hold end posts a zero-delta scroll ended event");
    holdBegin();
    holdEnd(1);
    pinchCheck([events count] == 23 && isGesture(22, NSEventTypeScrollWheel, NSEventPhaseCancelled),
           "a cancelled hold posts a zero-delta scroll cancelled event");

    [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures);
    exit(failures ? 1 : 0);
}
@end

int main(void) {
    [NSAutoreleasePool new];
    [PinchApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 240)
        styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
    [window makeKeyAndOrderFront: nil];
    [NSTimer scheduledTimerWithTimeInterval: 0.25 target: NSApp
        selector: @selector(test:) userInfo: nil repeats: NO];
    [NSApp run];
    return 2;
}
