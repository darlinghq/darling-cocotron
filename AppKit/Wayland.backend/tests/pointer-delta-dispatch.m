#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include "WaylandLibrary.h"
#include "WaylandProtocol.h"

// Private-compositor regression fixture, like scroll-frame-dispatch.m: it drives
// the backend's pointer entry point and records the AppKit events it posts.
// AppKit reports the delta of a mouse move with y growing downward, whatever
// the bottom-left origin of locations, and so does the X11 backend.
//
// Needs a Darling prefix and an isolated private Wayland compositor (build and
// run it like scroll-frame-dispatch.m, see SCROLL-FRAME-VALIDATION.md). It prints
// "SKIP" and exits 77 when the display is not the Wayland backend. The pointer
// coordinates are inside the content area of a titled window whether the
// compositor draws the decorations or the backend does (content offset 6,34), so
// the checks do not depend on xdg-decoration being offered. It has not been run
// yet: no guest was started when it was written.
union Argument { int32_t i; uint32_t u; const char *s; void *o; void *a; int h; };
@interface NSObject (PointerDeltaFixture)
+ (id) currentDisplay;
- (id) platformWindow;
- (void *) surface;
- (void) pointerEvent: (uint32_t) opcode arguments: (union Argument *) args;
@end

static NSMutableArray *events;
static id display;
static NSWindow *window;
static int failures, checks;

static void capture(id self, SEL command, NSEvent *event, BOOL atStart) {
    [events addObject: event];
}

static void deltaCheck(BOOL passed, const char *description) {
    checks++;
    if (!passed)
        failures++;
    printf("%s %s\n", passed ? "PASS" : "FAIL", description);
}

static void moveTo(double x, double y) {
    union Argument args[3] = {{.u = 0}, {.i = (int32_t) (x * 256.0)}, {.i = (int32_t) (y * 256.0)}};
    [display pointerEvent: 2 arguments: args];
}

@interface PointerDeltaApplication : NSApplication
@end

@implementation PointerDeltaApplication
- (void) test: (id) sender {
    display = [NSClassFromString(@"NSDisplay") currentDisplay];
    if (![NSStringFromClass(object_getClass(display)) hasPrefix: @"Wayland"]) {
        printf("SKIP the display is %s, not the Wayland backend\n",
               [NSStringFromClass(object_getClass(display)) UTF8String]);
        exit(77);
    }
    Class original = object_getClass(display);
    Class recorder = objc_allocateClassPair(original, "PointerDeltaRecordingDisplay", 0);
    Method method = class_getInstanceMethod(original, @selector(postEvent:atStart:));
    deltaCheck(method != NULL, "backend event method exists");
    class_addMethod(recorder, @selector(postEvent:atStart:), (IMP) capture,
                    method_getTypeEncoding(method));
    objc_registerClassPair(recorder);
    events = [NSMutableArray new];
    object_setClass(display, recorder);

    union Argument enter[4] = {{.u = 1},
        {.o = [[window platformWindow] surface]}, {.i = 100 * 256}, {.i = 100 * 256}};
    [display pointerEvent: 0 arguments: enter];

    moveTo(103, 97); // right and up on screen
    NSEvent *event = [events lastObject];
    deltaCheck([events count] == 1 && [event deltaX] == 3.0 && [event deltaY] == -3.0,
               "moving up reports a negative deltaY");
    moveTo(103, 107); // straight down
    event = [events lastObject];
    deltaCheck([events count] == 2 && [event deltaX] == 0.0 && [event deltaY] == 10.0,
               "moving down reports a positive deltaY");

    object_setClass(display, original);
    [events release];
    printf("RESULT checks=%d failures=%d\n", checks, failures);
    exit(failures ? 1 : 0);
}
@end

int main(void) {
    [NSAutoreleasePool new];
    [PointerDeltaApplication sharedApplication];
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 320, 240)
        styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
    [window setAcceptsMouseMovedEvents: YES];
    [window makeKeyAndOrderFront: nil];
    [NSTimer scheduledTimerWithTimeInterval: 0.25 target: NSApp
        selector: @selector(test:) userInfo: nil repeats: NO];
    [NSApp run];
    return 2;
}
