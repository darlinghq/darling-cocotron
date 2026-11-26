/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Direct touch dispatch of the windowing backends, run on a real display
// server or compositor. The fingers reach AppKit as touch CGEvents (E1 of
// darlinghq/darling#937). Neither Xvfb nor a headless compositor has a touch
// device, so the touch decoders of CoreGraphics' backends are fed the events a
// device would produce: XI_TouchBegin/Update/End for the X11 backend (build with
// -DTOUCH_X11) and wl_touch down/motion/up/cancel for the Wayland backend.
// The test captures what the display is asked to post, hands it to the window
// as the event loop would, and checks the NSEvents and NSTouch objects.
// Both backends must give the same results.
#ifdef TOUCH_X11
@interface NSObject (TouchFixture)
+ (id)currentDisplay;
+ (id)_processPointer;
- (id)platformWindow;
- (unsigned long)windowHandle;
- (void)touchEventType:(int)type device:(int)deviceID detail:(unsigned int)detail window:(unsigned long)w
                     x:(double)x y:(double)y rootX:(double)rx rootY:(double)ry;
@end
enum { XI_TouchBegin = 18, XI_TouchUpdate = 19, XI_TouchEnd = 20 };
#else
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int32_t f; int h; };
@interface NSObject (TouchFixture)
+ (id)currentDisplay;
- (id)platformWindow;
- (void *)surface;
- (void)touchEvent:(uint32_t)opcode arguments:(union Argument *)args;
- (void)processPendingEvents;
@end
enum { WL_DOWN = 0, WL_UP = 1, WL_MOTION = 2, WL_CANCEL = 4 };
#endif
// Private; looked up so that the test also runs (and fails) without it.
static void (*cancelAll)(NSWindow *);

static NSMutableArray *events;
static id display, decoder;
static NSWindow *window;
static int failures, checks;
static const CGFloat height = 200;

static void capture(id self, SEL cmd, NSEvent *event, BOOL atStart) { [events addObject:event]; }
// The backends report fingers as touch CGEvents in the event stream: what AppKit makes of them is read from
// the event queue (a cancel by a closing window is posted through the display, which the recorder has).
static void pump(void) {
    NSEvent *e;
    while ((e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                                      inMode:NSDefaultRunLoopMode dequeue:YES]) != nil)
        if ([e type] == NSEventTypeDirectTouch || [e type] == NSEventTypeLeftMouseDown ||
            [e type] == NSEventTypeLeftMouseDragged || [e type] == NSEventTypeLeftMouseUp)
            [events addObject:e];
}
static void expect(BOOL ok, const char *what) {
    ++checks; if (!ok) ++failures;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what); fflush(stdout);
}

// Fingers are given in the backend's own coordinates: from the top left.
static void fingerDown(int finger, double x, double y) {
#ifdef TOUCH_X11
    [decoder touchEventType:XI_TouchBegin device:11 detail:finger window:[[window platformWindow] windowHandle]
                          x:x y:y rootX:x rootY:y];
#else
    union Argument a[6] = {{.u = 1}, {.u = 0}, {.o = [[window platformWindow] surface]}, {.i = finger},
                           {.f = (int32_t)(x * 256)}, {.f = (int32_t)(y * 256)}};
    [decoder touchEvent:WL_DOWN arguments:a];
#endif
    pump();
}
static void fingerMove(int finger, double x, double y) {
#ifdef TOUCH_X11
    [decoder touchEventType:XI_TouchUpdate device:11 detail:finger window:[[window platformWindow] windowHandle]
                          x:x y:y rootX:x rootY:y];
#else
    union Argument a[4] = {{.u = 0}, {.i = finger}, {.f = (int32_t)(x * 256)}, {.f = (int32_t)(y * 256)}};
    [decoder touchEvent:WL_MOTION arguments:a];
#endif
    pump();
}
static void fingerUp(int finger, double x, double y) {
#ifdef TOUCH_X11
    [decoder touchEventType:XI_TouchEnd device:11 detail:finger window:[[window platformWindow] windowHandle]
                          x:x y:y rootX:x rootY:y];
#else
    union Argument a[3] = {{.u = 1}, {.u = 0}, {.i = finger}};
    [decoder touchEvent:WL_UP arguments:a];
#endif
    pump();
}

@interface TouchView : NSView {
@public
    int began, moved, ended, cancelled;
}
@end
@implementation TouchView
- (void)touchesBeganWithEvent:(NSEvent *)e { began++; }
- (void)touchesMovedWithEvent:(NSEvent *)e { moved++; }
- (void)touchesEndedWithEvent:(NSEvent *)e { ended++; }
- (void)touchesCancelledWithEvent:(NSEvent *)e { cancelled++; }
@end

static TouchView *touchView;
static NSView *plainView;

static NSTouch *touchWithPhase(NSEvent *e, NSTouchPhase phase) {
    for (NSTouch *t in [e allTouches]) if ([t phase] == phase) return t;
    return nil;
}
static BOOL near(NSPoint p, double x, double y) { return fabs(p.x - x) < 0.01 && fabs(p.y - y) < 0.01; }
// Hand the captured events to the window, as the event loop does.
static void deliver(void) {
    for (NSEvent *e in [events copy]) if ([e type] == NSEventTypeDirectTouch) [window sendEvent:e];
}

@interface TouchApplication : NSApplication
@end
@implementation TouchApplication
- (void)test:(id)sender {
    cancelAll = dlsym(RTLD_DEFAULT, "NSTouchCancelAll");
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
#ifdef TOUCH_X11
    Class connection = NSClassFromString(@"CGSConnectionX11");
    decoder = connection != nil && [connection respondsToSelector:@selector(_processPointer)]
                      ? [connection _processPointer] : nil;
    SEL feed = @selector(touchEventType:device:detail:window:x:y:rootX:rootY:);
#else
    Ivar decoderIvar = class_getInstanceVariable(object_getClass(_CGSConnectionForID(CGSMainConnectionID())), "_touchDecoder");
    decoder = decoderIvar ? object_getIvar(_CGSConnectionForID(CGSMainConnectionID()), decoderIvar) : nil;
    SEL feed = @selector(touchEvent:arguments:);
#endif
    if (![decoder respondsToSelector:feed] || cancelAll == NULL) {
        expect(NO, "the backend handles touch events");
        printf("RESULT checks=%d failures=%d\n", checks, failures); fflush(stdout);
        exit(1);
    }
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "TouchRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    expect(method != NULL, "backend event method exists");
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP)capture, method_getTypeEncoding(method));
    objc_registerClassPair(recorder); events = [NSMutableArray new]; object_setClass(display, recorder);

    expect([plainView allowedTouchTypes] == NSTouchTypeMaskDirect, "a view allows direct touches by default");
    expect(NSEventTypeDirectTouch == 37, "direct touch is event type 37");

    // A view that handles touches: direct touch events, all fingers in each.
    fingerDown(1, 50, 50);
    NSEvent *e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect(e != nil && [e type] == NSEventTypeDirectTouch, "touch screen finger on a touch view posts a direct touch event");
    NSTouch *t = e ? touchWithPhase(e, NSTouchPhaseBegan) : nil;
    expect([[e allTouches] count] == 1 && t != nil, "one touch in the Began phase");
    expect(t != nil && [t type] == NSTouchTypeDirect && [t identity] != nil, "direct type, identity present");
    expect(t != nil && near([t locationInView:touchView], 50, height - 50), "location in the view, bottom left origin");
    expect(t != nil && near([t locationInView:nil], 50, height - 50), "location in window base coordinates");
    id identity1 = [t identity];
    deliver();
    expect(touchView->began == 1, "touchesBeganWithEvent: reached the view once");
    expect(e != nil && [[e touchesMatchingPhase:NSTouchPhaseBegan inView:touchView] count] == 1,
          "touchesMatchingPhase:inView: finds the touch");

    [events removeAllObjects];
    fingerMove(1, 60, 60);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    t = e ? touchWithPhase(e, NSTouchPhaseMoved) : nil;
    expect(t != nil && near([t locationInView:touchView], 60, height - 60) &&
          near([t previousLocationInView:touchView], 50, height - 50), "move: Moved phase, location and previous location");
    expect(t != nil && [[t identity] isEqual:identity1], "the identity stays with the finger");
    deliver();
    expect(touchView->moved == 1, "touchesMovedWithEvent: reached the view");

    [events removeAllObjects];
    fingerDown(2, 100, 100);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect([[e allTouches] count] == 2 && touchWithPhase(e, NSTouchPhaseBegan) != nil &&
          touchWithPhase(e, NSTouchPhaseStationary) != nil, "second finger: both fingers in the event, the first Stationary");
    expect(touchWithPhase(e, NSTouchPhaseStationary) != nil &&
          [[touchWithPhase(e, NSTouchPhaseStationary) identity] isEqual:identity1], "stationary one is the first finger");
    id identity2 = [touchWithPhase(e, NSTouchPhaseBegan) identity];
    expect(![identity2 isEqual:identity1], "fingers have distinct identities");
    deliver();

    [events removeAllObjects];
    fingerUp(1, 60, 60);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    t = e ? touchWithPhase(e, NSTouchPhaseEnded) : nil;
    expect(t != nil && near([t locationInView:touchView], 60, height - 60), "end: Ended phase at the last location");
    expect([[e allTouches] count] == 2, "the other finger is still in the event");
    deliver();
    expect(touchView->ended == 1, "touchesEndedWithEvent: reached the view");

    [events removeAllObjects];
    fingerUp(2, 100, 100);
    expect([events count] == 1 && touchWithPhase([events objectAtIndex:0], NSTouchPhaseEnded) != nil &&
          [[events objectAtIndex:0] allTouches].count == 1, "last finger ends alone");

    // A finger number is reusable and a new finger gets a new identity.
    [events removeAllObjects];
    fingerDown(1, 70, 70);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    t = e ? touchWithPhase(e, NSTouchPhaseBegan) : nil;
    expect(t != nil && ![[t identity] isEqual:identity1], "a reused finger number is a new touch");

    // Cancel: through the window closing and, on Wayland, wl_touch.cancel.
    [events removeAllObjects];
#ifdef TOUCH_X11
    if (cancelAll) cancelAll(window);
#else
    union Argument none[1] = {{.u = 0}};
    [decoder touchEvent:WL_CANCEL arguments:none];
#endif
    pump();
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect(e != nil && touchWithPhase(e, NSTouchPhaseCancelled) != nil, "cancel: Cancelled phase");
    deliver();
    expect(touchView->cancelled == 1, "touchesCancelledWithEvent: reached the view");
    [events removeAllObjects];
    fingerUp(1, 70, 70);
    expect([events count] == 0, "no events for a finger that was cancelled");

    // A view that does not handle touches: the finger moves the mouse.
    [events removeAllObjects];
    fingerDown(3, 200, 100);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect(e != nil && [e type] == NSEventTypeLeftMouseDown && [e clickCount] == 1 && near([e locationInWindow], 200, height - 100),
          "finger on a plain view: left mouse down at its location");
    [events removeAllObjects];
    fingerMove(3, 210, 110);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect(e != nil && [e type] == NSEventTypeLeftMouseDragged && near([e locationInWindow], 210, height - 110),
          "move: left mouse dragged");
    [events removeAllObjects];
    fingerUp(3, 210, 110);
    e = [events count] == 1 ? [events objectAtIndex:0] : nil;
    expect(e != nil && [e type] == NSEventTypeLeftMouseUp && near([e locationInWindow], 210, height - 110),
          "end: left mouse up at the last location");

    // An unknown finger is ignored.
    [events removeAllObjects];
    fingerMove(9, 20, 20); fingerUp(9, 20, 20);
    expect([events count] == 0, "motion and end of an unknown finger are ignored");

    object_setClass(display, original); [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures); fflush(stdout);
    exit(failures ? 1 : 0);
}
@end

int main(void) {
    [NSAutoreleasePool new]; [TouchApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, height)
                                         styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
    touchView = [[TouchView alloc] initWithFrame:NSMakeRect(0, 0, 150, height)];
    plainView = [[NSView alloc] initWithFrame:NSMakeRect(150, 0, 150, height)];
    [[window contentView] addSubview:touchView];
    [[window contentView] addSubview:plainView];
    [window makeKeyAndOrderFront:nil];
    [NSTimer scheduledTimerWithTimeInterval:3 target:NSApp selector:@selector(test:) userInfo:nil repeats:NO];
    puts("READY"); fflush(stdout); [NSApp run]; return 2;
}
