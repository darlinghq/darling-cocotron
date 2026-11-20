/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A mouse press that comes from the window system carries whether its window was
// key when the press arrived: the window system may activate the window for the
// same click before the press is taken from the event queue, and the press is
// still the one that activates the window, so a view that does not accept
// first mouse does not get it. Events without that state (events made by the
// application) are judged by the window's state when they are sent.
// Darling-specific: the arrival state is set through the private
// -[NSEvent_mouse _setWindowWasKeyOnArrival:] that the display backends use.
// Needs a display.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

@interface ProbeView : NSView {
@public
    BOOL accepts;
    int downs;
}
@end
@implementation ProbeView
- (BOOL) acceptsFirstMouse: (NSEvent *) event { return accepts; }
- (void) mouseDown: (NSEvent *) event { downs++; }
@end

static NSEvent *press(NSWindow *window, int arrival) {
    NSEvent *event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown location: NSMakePoint(50, 50) modifierFlags: 0
                                       timestamp: [NSDate timeIntervalSinceReferenceDate] windowNumber: [window windowNumber]
                                         context: nil eventNumber: 1 clickCount: 1 pressure: 1];
    SEL setter = NSSelectorFromString(@"_setWindowWasKeyOnArrival:");
    if (arrival >= 0 && [event respondsToSelector: setter])
        ((void (*)(id, SEL, BOOL)) objc_msgSend)(event, setter, arrival != 0);
    return event;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *other = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 200) styleMask: NSWindowStyleMaskTitled
                                                        backing: NSBackingStoreBuffered defer: NO];
        NSWindow *target = [[NSWindow alloc] initWithContentRect: NSMakeRect(400, 100, 200, 200) styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered defer: NO];
        ProbeView *probe = [[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [[target contentView] addSubview: probe];
        [other orderFront: nil];
        [target orderFront: nil];
        spin(0.3);
        NSEvent *probeEvent = press(target, 0);
        if (NSClassFromString(@"NSEvent_mouse") == nil) {
            printf("SKIP not Darling\n");
            return 0;
        }
        expect([probeEvent respondsToSelector: NSSelectorFromString(@"_setWindowWasKeyOnArrival:")],
               "mouse events carry the window's key state on arrival");

        // The target window is key by the time the press is sent, but it was not when the press arrived.
        [target makeKeyAndOrderFront: nil];
        spin(0.3);
        if (![target isKeyWindow])
            [target becomeKeyWindow];
        expect([target isKeyWindow], "setup: the target window is key");
        probe->accepts = NO;
        probe->downs = 0;
        [target sendEvent: press(target, 0)];
        expect(probe->downs == 0, "key now, not key on arrival, NO view: not delivered");
        probe->accepts = YES;
        [target sendEvent: press(target, 0)];
        expect(probe->downs == 1, "key now, not key on arrival, YES view: delivered");

        // The other way round: not key now, key when the press arrived.
        [other makeKeyAndOrderFront: nil];
        spin(0.3);
        if ([target isKeyWindow])
            [other becomeKeyWindow];
        expect(![target isKeyWindow], "setup: the target window is not key");
        probe->accepts = NO;
        probe->downs = 0;
        [target sendEvent: press(target, 1)];
        expect(probe->downs == 1, "not key now, key on arrival, NO view: delivered");

        // Without arrival state the window's state when the event is sent decides. The
        // delivered press above made the target key.
        [other makeKeyAndOrderFront: nil];
        spin(0.3);
        if ([target isKeyWindow])
            [other becomeKeyWindow];
        expect(![target isKeyWindow], "setup: the target window is not key again");
        probe->downs = 0;
        [target sendEvent: press(target, -1)];
        expect(probe->downs == 0, "no arrival state, window not key, NO view: not delivered");
        [other makeKeyAndOrderFront: nil];
        spin(0.3);
        if ([target isKeyWindow])
            [other becomeKeyWindow];
        [target makeKeyAndOrderFront: nil];
        spin(0.3);
        if (![target isKeyWindow])
            [target becomeKeyWindow];
        probe->downs = 0;
        [target sendEvent: press(target, -1)];
        expect(probe->downs == 1, "no arrival state, window key, NO view: delivered");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
