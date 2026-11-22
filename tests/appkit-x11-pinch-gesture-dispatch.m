/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// A touchpad pinch on the X11 backend (XInput 2.4 GesturePinchBegin, Update and End) becomes AppKit magnify and
// rotate events. The test feeds the backend's own entry point, -[X11Display
// pinchEventType:window:x:y:scale:deltaAngle:cancelled:modifiers:], records the events it posts and checks that
// NSWindow delivers them to the view under the pointer; the same checks as the Wayland backend's
// pinch-gesture-dispatch.m. XInput's pinch scale is absolute and its angle is in degrees clockwise since the
// previous update (XI2proto.txt, GesturePinchEvent); AppKit's magnification is the change of scale
// (https://developer.apple.com/documentation/appkit/nsevent/magnification). Needs an X session; skipped on others.
// Build without ARC.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

// The event types of X11/extensions/XI2.h.
enum { PinchBegin = 27, PinchUpdate = 28, PinchEnd = 29 };

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

@interface NSObject (PinchFixture)
- (unsigned long) windowHandle;
- (void) pinchEventType: (int) type
                 window: (unsigned long) window
                      x: (double) x
                      y: (double) y
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled
              modifiers: (unsigned int) modifiers;
- (void) cancelPinch;
@end

static NSMutableArray *events;
static id display;
static NSWindow *window;
static unsigned long xwindow;
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

static void begin(void) {
    [display pinchEventType: PinchBegin window: xwindow x: 40 y: 30 scale: 1 deltaAngle: 0 cancelled: NO modifiers: 0];
}

static void update(double scale, double clockwiseDegrees) {
    [display pinchEventType: PinchUpdate window: xwindow x: 40 y: 30 scale: scale deltaAngle: clockwiseDegrees
                  cancelled: NO modifiers: 0];
}

static void end(BOOL cancelled) {
    [display pinchEventType: PinchEnd window: xwindow x: 40 y: 30 scale: 1 deltaAngle: 0 cancelled: cancelled modifiers: 0];
}

// The ivars are declared because the i386 slice uses the legacy runtime, which does not synthesize them.
@interface GestureView : NSView {
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
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "PinchRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP) capture, method_getTypeEncoding(method));
    objc_registerClassPair(recorder);
    events = [NSMutableArray new];
    object_setClass(display, recorder);

    begin();
    pinchCheck([events count] == 2 && isGesture(0, NSEventTypeMagnify, NSEventPhaseBegan) &&
                   isGesture(1, NSEventTypeRotate, NSEventPhaseBegan),
               "pinch begin posts began magnify and rotate events");
    update(1.5, 10);
    NSEvent *magnify = [events count] > 2 ? [events objectAtIndex: 2] : nil;
    NSEvent *rotate = [events count] > 3 ? [events objectAtIndex: 3] : nil;
    pinchCheck([events count] == 4 && isGesture(2, NSEventTypeMagnify, NSEventPhaseChanged) &&
                   fabs([magnify magnification] - 0.5) < 0.01 && isGesture(3, NSEventTypeRotate, NSEventPhaseChanged) &&
                   fabs([rotate rotation] + 10) < 0.01,
               "update posts the scale change and the counterclockwise rotation");
    pinchCheck(fabs([magnify locationInWindow].x - 40) < 1.5, "gesture events carry the position in the window");
    update(1.25, 0);
    pinchCheck([events count] == 5 && isGesture(4, NSEventTypeMagnify, NSEventPhaseChanged) &&
                   fabs([(NSEvent *) [events objectAtIndex: 4] magnification] + 0.25) < 0.01,
               "a pinch without rotation posts only a magnify change");
    update(1.25, 0);
    pinchCheck([events count] == 5, "an unchanged update posts nothing");
    end(NO);
    pinchCheck([events count] == 7 && isGesture(5, NSEventTypeMagnify, NSEventPhaseEnded) &&
                   isGesture(6, NSEventTypeRotate, NSEventPhaseEnded),
               "pinch end posts ended events");

    begin();
    end(YES);
    pinchCheck([events count] == 11 && isGesture(9, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(10, NSEventTypeRotate, NSEventPhaseCancelled),
               "a cancelled pinch posts cancelled events");

    update(2, 5);
    end(NO);
    pinchCheck([events count] == 11, "events outside a pinch are dropped");

    begin();
    [display cancelPinch];
    update(2, 5);
    end(NO);
    pinchCheck([events count] == 15 && isGesture(13, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(14, NSEventTypeRotate, NSEventPhaseCancelled),
               "cancelling an active pinch ends it and drops the rest of it");

    object_setClass(display, original);

    GestureView *view = [[GestureView alloc] initWithFrame: [[window contentView] bounds]];
    [window setContentView: view];
    for (NSEvent *event in events)
        [window sendEvent: event];
    pinchCheck(view.magnifications == 8 && view.rotations == 7 && fabs(view.totalMagnification - 0.25) < 0.01 &&
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
    display = [NSDisplay currentDisplay];
    if (![NSStringFromClass([display class]) hasPrefix: @"X11"]) {
        printf("SKIP: not the X11 backend\n");
        return 0;
    }
    if (![display respondsToSelector: @selector(pinchEventType:window:x:y:scale:deltaAngle:cancelled:modifiers:)]) {
        printf("SKIP: built without XInput 2.4 headers\n");
        return 0;
    }
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 240)
                                         styleMask: NSTitledWindowMask
                                           backing: NSBackingStoreBuffered
                                             defer: NO];
    [window makeKeyAndOrderFront: nil];
    xwindow = [[window platformWindow] windowHandle];
    [NSTimer scheduledTimerWithTimeInterval: 0.25 target: NSApp selector: @selector(test:) userInfo: nil repeats: NO];
    [NSApp run];
    return 2;
}
