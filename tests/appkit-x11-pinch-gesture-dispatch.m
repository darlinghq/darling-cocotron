/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// A touchpad pinch on the X11 backend (XInput 2.4 GesturePinchBegin, Update and End) becomes magnify and rotate
// CGEvents, which AppKit makes magnify and rotate events of. The test feeds the entry point of CoreGraphics' pointer
// decoder, -[CGSX11Pointer pinchEventType:window:x:y:rootX:rootY:scale:deltaAngle:cancelled:], takes the events AppKit
// makes of the CGEvents it posts and checks that NSWindow delivers them to the view under the pointer; the same checks as
// the Wayland backend's pinch-gesture-dispatch.m. XInput's pinch scale is absolute and its angle is in degrees clockwise since the
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
+ (id) _processPointer;
- (void) pinchEventType: (int) type
                 window: (unsigned long) window
                      x: (double) x
                      y: (double) y
                  rootX: (double) rootX
                  rootY: (double) rootY
                  scale: (double) scale
             deltaAngle: (double) degrees
              cancelled: (BOOL) cancelled;
- (void) cancelPinchOnWindow: (unsigned long) window;
@end

static NSMutableArray *events;
static id display, decoder;
static NSWindow *window;
static unsigned long xwindow;
static int failures, checks;

// The decoder is CoreGraphics': what it posts becomes events in AppKit's queue.
static void drain(void) {
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                          inMode: NSDefaultRunLoopMode
                                         dequeue: YES]) != nil)
        [events addObject: event];
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

static void feed(int type, double scale, double degrees, BOOL cancelled) {
    // The position in the window is the native location; the root position only has to be consistent.
    double rootX = 140, rootY = 130;
    [decoder pinchEventType: type window: xwindow x: 40 y: 30 rootX: rootX rootY: rootY scale: scale deltaAngle: degrees
                  cancelled: cancelled];
    drain();
}

static void begin(void) {
    feed(PinchBegin, 1, 0, NO);
}

static void update(double scale, double clockwiseDegrees) {
    feed(PinchUpdate, scale, clockwiseDegrees, NO);
}

static void end(BOOL cancelled) {
    feed(PinchEnd, 1, 0, cancelled);
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
    events = [NSMutableArray new];

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
    // The window going away: -[X11Window invalidate] and DestroyNotify say so.
    [decoder cancelPinchOnWindow: xwindow];
    drain();
    update(2, 5);
    end(NO);
    pinchCheck([events count] == 15 && isGesture(13, NSEventTypeMagnify, NSEventPhaseCancelled) &&
                   isGesture(14, NSEventTypeRotate, NSEventPhaseCancelled),
               "cancelling an active pinch ends it and drops the rest of it");

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
    Class connection = objc_getClass("CGSConnectionX11");
    decoder = connection != nil && class_getClassMethod(connection, @selector(_processPointer)) != NULL
                      ? [connection _processPointer] : nil;
    if (decoder == nil || ![decoder respondsToSelector: @selector(touchEventType:device:detail:window:x:y:rootX:rootY:)]) {
        printf("FAIL: no X11 pointer decoder in the process\n");
        return 1;
    }
    if (![decoder respondsToSelector: @selector(pinchEventType:window:x:y:rootX:rootY:scale:deltaAngle:cancelled:)]) {
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
