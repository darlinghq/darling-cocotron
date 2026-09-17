#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// Private-compositor regression fixture. It drives the real WaylandDisplay
// protocol entry point and records the AppKit events it posts.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (ScrollFrameFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
- (void) windowUnmapped: (id) window;
- (void) seatCapabilities: (uint32_t) capabilities;
- (void) keyboardEvent: (uint32_t) opcode arguments: (union Argument *) args;
@end

extern struct WaylandLibrary WL;

static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;
static uint32_t (*realProxyVersion)(struct wl_proxy *proxy);
static uint32_t forcedProxyVersion(struct wl_proxy *proxy) {
    return 4;
}

static void capture(id self, SEL command, NSEvent *event, BOOL atStart) {
    [events addObject: event];
}

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
    [display pointerEvent: 4 arguments: args];
}

static void frame(void) {
    [display pointerEvent: 5 arguments: NULL];
}

@interface ScrollFrameApplication : NSApplication
@end

@implementation ScrollFrameApplication
- (void) test: (id) sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "ScrollFrameRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    scrollCheck(method != NULL, "backend event method exists");
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP) capture,
                    method_getTypeEncoding(method));
    objc_registerClassPair(recorder);
    events = [NSMutableArray new];
    object_setClass(display, recorder);

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 20 * 256}, {.i = 30 * 256}};
    [display pointerEvent: 0 arguments: enter];

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
    [display pointerEvent: 3 arguments: button];
    scrollCheck([events count] == 4 &&
                    eventTypeAt(2) == NSScrollWheel &&
                    eventTypeAt(3) == NSLeftMouseDown,
                "overtaking button is posted after the pending scroll");

    realProxyVersion = WL.wl_proxy_get_version;
    WL.wl_proxy_get_version = forcedProxyVersion;
    axis(0, 10.0);
    scrollCheck([events count] == 5 &&
                    [(NSEvent *) [events lastObject] type] == NSScrollWheel,
                "pre-v5 axis delivery remains immediate");
    WL.wl_proxy_get_version = realProxyVersion;

    union Argument leave[2] = {{.u = 2},
                               {.o = [[window platformWindow] surface]}};
    [display pointerEvent: 1 arguments: leave];
    frame();
    scrollCheck([events count] == 5,
                "pointer leave discards an unfinished scroll frame");

    [display pointerEvent: 0 arguments: enter];
    axis(0, 10.0);
    [display seatCapabilities: 0];
    frame();
    scrollCheck([events count] == 5,
                "pointer capability loss discards an unfinished scroll frame");
    [display seatCapabilities: 1];
    [display pointerEvent: 0 arguments: enter];
    axis(0, 10.0);
    frame();
    scrollCheck([events count] == 6,
                "pointer capability reacquisition resumes framed scrolling");

    axis(0, 10.0);
    [display windowUnmapped: [window platformWindow]];
    frame();
    scrollCheck([events count] == 6,
                "window unmap discards an unfinished scroll frame");

    object_setClass(display, original);
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
