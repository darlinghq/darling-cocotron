/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// Private-compositor regression fixture. It drives the protocol entry point of CoreGraphics' pointer
// decoder (the process' wl_pointer) and takes the AppKit events made from the CGEvents it posts.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (ScrollFrameFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) windowUnmapped: (id) window;
- (void) seatCapabilities: (uint32_t) capabilities seat: (void *) seat;
@end


static id decoder;

// The decoder is CoreGraphics': what it posts becomes NSEvents in AppKit's queue
static void drain(NSMutableArray *events) {
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

static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;

static void scrollCheck(BOOL passed, const char *description) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

static NSEventType eventTypeAt(NSUInteger index) {
    return [(NSEvent *) [events objectAtIndex: index] type];
}

static void axis(uint32_t which, double value) {
    union Argument args[3] = {{.u = 0}, {.u = which},
                              {.i = (int32_t) (value * 256.0)}};
    [decoder pointerEvent: 4 arguments: args];
    drain(events);
}

static void frame(void) {
    [decoder pointerEvent: 5 arguments: NULL];
    drain(events);
}

@interface ScrollFrameApplication : NSApplication
@end

@implementation ScrollFrameApplication
- (void) test: (id) sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    decoder = ivarOf(_CGSConnectionForID(CGSMainConnectionID()), "_pointerDecoder");
    id connection = _CGSConnectionForID(CGSMainConnectionID());
    scrollCheck(decoder != nil, "CoreGraphics has the pointer decoder");
    events = [NSMutableArray new];
    drain(events);
    [events removeAllObjects];
    // A headless compositor has no pointer device: take the capability so the decoder has a wl_pointer
    [decoder seatCapabilities: 1 seat: (void *) ivarOf(connection, "_seat")];

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 20 * 256}, {.i = 30 * 256}};
    [decoder pointerEvent: 0 arguments: enter];

    axis(0, 20.0);
    axis(1, -10.0);
    scrollCheck([events count] == 0, "axis updates wait for wl_pointer.frame");
    frame();
    scrollCheck([events count] == 1, "one AppKit event represents one pointer frame");
    NSEvent *event = [events lastObject];
    scrollCheck([event deltaX] == 1.0 && [event deltaY] == -2.0,
                "frame combines horizontal and vertical deltas");

    axis(0, 5.0);
    axis(0, 7.0);
    frame();
    event = [events lastObject];
    scrollCheck([events count] == 2 && [event deltaX] == 0.0 &&
                    fabs([event deltaY] + 1.2) < 0.0001,
                "same-axis updates accumulate without extra events");
    frame();
    scrollCheck([events count] == 2, "empty pointer frames post no scroll event");

    axis(0, 10.0);
    union Argument button[4] = {{.u = 3}, {.u = 100}, {.u = 0x110}, {.u = 1}};
    [decoder pointerEvent: 3 arguments: button];
    drain(events);
    scrollCheck([events count] == 4 &&
                    eventTypeAt(2) == NSScrollWheel &&
                    eventTypeAt(3) == NSLeftMouseDown,
                "overtaking button is posted after the pending scroll");

    // (A seat older than version 5 sends no wl_pointer.frame and each axis event is a frame by itself: the
    // decoder reads the version of its own wl_pointer through CoreGraphics' own copy of the library shim, which
    // a program cannot replace, so that case is not driven here.)

    union Argument leave[2] = {{.u = 2},
                               {.o = [[window platformWindow] surface]}};
    [decoder pointerEvent: 1 arguments: leave];
    drain(events);
    frame();
    scrollCheck([events count] == 4,
                "pointer leave discards an unfinished scroll frame");

    [decoder pointerEvent: 0 arguments: enter];
    axis(0, 10.0);
    [decoder seatCapabilities: 0 seat: NULL];
    drain(events);
    frame();
    scrollCheck([events count] == 4,
                "pointer capability loss discards an unfinished scroll frame");
    [decoder seatCapabilities: 1 seat: (void *) ivarOf(connection, "_seat")];
    [decoder pointerEvent: 0 arguments: enter];
    axis(0, 10.0);
    frame();
    scrollCheck([events count] == 5,
                "pointer capability reacquisition resumes framed scrolling");

    axis(0, 10.0);
    [display windowUnmapped: [window platformWindow]];
    drain(events);
    frame();
    scrollCheck([events count] == 5,
                "window unmap discards an unfinished scroll frame");

    [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures);
    exit(failures ? 1 : 0);
}
@end

int main(void) {
    [NSAutoreleasePool new];
    [ScrollFrameApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 240)
        styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
    [window makeKeyAndOrderFront: nil];
    [NSTimer scheduledTimerWithTimeInterval: 0.25 target: NSApp
        selector: @selector(test:) userInfo: nil repeats: NO];
    [NSApp run];
    return 2;
}
