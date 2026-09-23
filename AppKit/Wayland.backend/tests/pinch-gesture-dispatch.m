#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Private-compositor regression fixture. It drives the real WaylandDisplay
// pinch-gesture entry point, records the AppKit events it posts, and checks
// that NSWindow delivers them to the view under the pointer.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (PinchFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) pinchEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) windowUnmapped: (id) window;
- (void) seatCapabilities: (uint32_t) capabilities;
@end

static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;

static void capture(id self, SEL command, NSEvent *event, BOOL atStart) {
    [events addObject: event];
}

static void pinchCheck(BOOL passed, const char *description) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

static BOOL isGesture(NSUInteger index, NSEventType type, NSEventPhase phase) {
    if (index >= [events count])
        return NO;
    NSEvent *event = [events objectAtIndex: index];
    return [event type] == type && [event phase] == phase && [event window] == window;
}

static void *pinchProxy(void) {
    Ivar ivar = class_getInstanceVariable(object_getClass(display), "_pinchGesture");
    return *(void **) ((char *) display + ivar_getOffset(ivar));
}

static void begin(void) {
    union Argument args[4] = {{.u = 7}, {.u = 100}, {.o = [[window platformWindow] surface]}, {.u = 2}};
    [display pinchEvent: 0 arguments: args];
}

static void update(double scale, double clockwiseDegrees) {
    union Argument args[5] = {{.u = 101}, {.i = 0}, {.i = 0},
                              {.i = (int32_t) (scale * 256.0)}, {.i = (int32_t) (clockwiseDegrees * 256.0)}};
    [display pinchEvent: 1 arguments: args];
}

static void end(int cancelled) {
    union Argument args[3] = {{.u = 8}, {.u = 102}, {.i = cancelled}};
    [display pinchEvent: 2 arguments: args];
}

@interface GestureView : NSView
@property NSInteger magnifications, rotations;
@property CGFloat totalMagnification;
@property float totalRotation;
@end

@implementation GestureView
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
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "PinchRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP) capture,
                    method_getTypeEncoding(method));
    objc_registerClassPair(recorder);
    events = [NSMutableArray new];
    object_setClass(display, recorder);

    // A headless compositor has no pointer device; take the capability so the
    // backend requests its pinch object for real.
    [display seatCapabilities: 1];
    pinchCheck(pinchProxy() != NULL, "a pointer gets a pinch gesture object");

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 40 * 256}, {.i = 30 * 256}};
    [display pointerEvent: 0 arguments: enter];

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
    update(2, 5);
    end(0);
    pinchCheck([events count] == 15 && isGesture(13, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(14, NSEventTypeRotate, NSEventPhaseCancelled),
               "window unmap cancels an active pinch and drops the rest of it");

    [display pointerEvent: 0 arguments: enter];
    begin();
    [display seatCapabilities: 0];
    pinchCheck(pinchProxy() == NULL && [events count] == 19 &&
                   isGesture(17, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(18, NSEventTypeRotate, NSEventPhaseCancelled),
               "losing the pointer cancels an active pinch and destroys its object");

    object_setClass(display, original);

    GestureView *view = [[GestureView alloc] initWithFrame: [[window contentView] bounds]];
    [window setContentView: view];
    for (NSEvent *event in events)
        [window sendEvent: event];
    pinchCheck(view.magnifications == 10 && view.rotations == 9 && fabs(view.totalMagnification - 0.25) < 0.01 &&
              fabs(view.totalRotation + 10) < 0.01,
          "NSWindow sends magnify and rotate events to the view under the pointer");

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
