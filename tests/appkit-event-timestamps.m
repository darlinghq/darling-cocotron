/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSEvent timestamps are seconds since the system started (the mach_absolute_time clock), an explicit timestamp is kept as given, and the CGEvent made from a mouse event carries
// that time in nanoseconds and a global location with the origin at the top-left of the main display. Prints PASS
// on success. Needs a window system session (X11 or Wayland). Build without ARC.
//
//   appkit-event-timestamps                  events made through the API
//   appkit-event-timestamps input X Y        ordered-in window that covers the global top-left point (X, Y); waits
//                                            for a real mouse click there and a key press, and checks the timestamp
//                                            and CGEvent of the events the window system delivered (see
//                                            appkit-event-timestamps-x11.sh and appkit-event-timestamps-wayland.sh)
#import <AppKit/AppKit.h>
#include <mach/mach_time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static double machUptime(void) {
    mach_timebase_info_data_t base;
    mach_timebase_info(&base);
    return (double) mach_absolute_time() * base.numer / base.denom / 1e9;
}

// Not in Apple's NSEvent.h: the window-based initializers every NSEvent subclass here builds on.
@interface NSEvent (Cocotron)
+ (NSEvent *) mouseEventWithType: (NSEventType) type
                        location: (NSPoint) location
                   modifierFlags: (NSEventModifierFlags) modifierFlags
                          window: (NSWindow *) window
                      clickCount: (NSInteger) clickCount
                          deltaX: (CGFloat) deltaX
                          deltaY: (CGFloat) deltaY;
@end

static void checkEventTime(NSEvent *event, const char *what) {
    double uptime = machUptime();
    char message[200];
    snprintf(message, sizeof message, "%s: timestamp %.3f is within 5 s before the system uptime %.3f", what,
             [event timestamp], uptime);
    expect([event timestamp] <= uptime + 0.01 && [event timestamp] > uptime - 5, message);
}

static void checkCGEventLocation(NSEvent *event, NSPoint expected, const char *what) {
    CGEventRef cg = [event CGEvent];
    expect(cg != NULL, "the mouse event has a CGEvent");
    if (cg == NULL)
        return;
    CGPoint location = CGEventGetLocation(cg);
    char message[200];
    snprintf(message, sizeof message, "%s: CGEvent location (%.1f, %.1f) is the global top-left point (%.1f, %.1f)",
             what, location.x, location.y, expected.x, expected.y);
    expect(fabs(location.x - expected.x) <= 2 && fabs(location.y - expected.y) <= 2, message);
    double ns = [event timestamp] * 1e9;
    uint64_t stamp = CGEventGetTimestamp(cg);
    snprintf(message, sizeof message, "%s: CGEvent timestamp %llu is the event time in nanoseconds", what,
             (unsigned long long) stamp);
    expect(fabs((double) stamp - ns) < 2000, message);
}

static void apiChecks(void) {
    // An explicit timestamp is kept as given, zero included.
    NSEvent *event = [NSEvent otherEventWithType: NSEventTypeApplicationDefined
                                        location: NSZeroPoint
                                   modifierFlags: 0
                                       timestamp: 12.5
                                    windowNumber: 0
                                         context: nil
                                         subtype: 0
                                           data1: 0
                                           data2: 0];
    expect([event timestamp] == 12.5, "an other event keeps its timestamp");
    event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                               location: NSMakePoint(10, 20)
                          modifierFlags: 0
                              timestamp: 7.25
                           windowNumber: 0
                                context: nil
                            eventNumber: 1
                             clickCount: 1
                               pressure: 1];
    expect([event timestamp] == 7.25, "a mouse event keeps its timestamp");
    event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                               location: NSMakePoint(10, 20)
                          modifierFlags: 0
                              timestamp: 0
                           windowNumber: 0
                                context: nil
                            eventNumber: 1
                             clickCount: 1
                               pressure: 1];
    expect([event timestamp] == 0, "a mouse event keeps a timestamp of zero");
    event = [NSEvent keyEventWithType: NSEventTypeKeyDown
                             location: NSZeroPoint
                        modifierFlags: 0
                            timestamp: 3.5
                         windowNumber: 0
                              context: nil
                           characters: @"a"
          charactersIgnoringModifiers: @"a"
                            isARepeat: NO
                              keyCode: 0];
    expect([event timestamp] == 3.5, "a key event keeps its timestamp");
    event = [NSEvent enterExitEventWithType: NSEventTypeMouseEntered
                                   location: NSZeroPoint
                              modifierFlags: 0
                                  timestamp: 9.75
                               windowNumber: 0
                                    context: nil
                                eventNumber: 1
                             trackingNumber: 1
                                   userData: NULL];
    expect([event timestamp] == 9.75, "an enter/exit event keeps its timestamp");

    // Without a timestamp the time is the current system uptime, not seconds since 2001.
    event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                               location: NSMakePoint(10, 20)
                          modifierFlags: 0
                                 window: nil
                             clickCount: 1
                                 deltaX: 0
                                 deltaY: 0];
    checkEventTime(event, "a mouse event made without a timestamp");

    // The CGEvent of a window-less mouse event: the location is in screen coordinates, so it is only flipped.
    NSArray *screens = [NSScreen screens];
    expect([screens count] > 0, "there is a screen");
    if ([screens count] == 0)
        return;
    CGFloat mainHeight = NSHeight([[screens objectAtIndex: 0] frame]);
    event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                               location: NSMakePoint(10, 20)
                          modifierFlags: 0
                              timestamp: 1.5
                           windowNumber: 0
                                context: nil
                            eventNumber: 1
                             clickCount: 1
                               pressure: 1];
    checkCGEventLocation(event, NSMakePoint(10, mainHeight - 20), "window-less mouse event");

    // With a window the location is window-local, bottom-left, and becomes global top-left.
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 200, 300, 150)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSRect frame = [window frame];
    event = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown
                               location: NSMakePoint(30, 40)
                          modifierFlags: 0
                              timestamp: 2.5
                           windowNumber: [window windowNumber]
                                context: nil
                            eventNumber: 1
                             clickCount: 1
                               pressure: 1];
    checkCGEventLocation(event, NSMakePoint(NSMinX(frame) + 30, mainHeight - (NSMinY(frame) + 40)),
                         "mouse event in a window");
    [window release];
}

static void inputChecks(double x, double y) {
    CGFloat mainHeight = NSHeight([[[NSScreen screens] objectAtIndex: 0] frame]);
    // A window whose content is around the point, in bottom-left screen coordinates. It is titled, so it can
    // become the key window and receive the key press.
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(x - 250, mainHeight - y - 150, 500, 300)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setAcceptsMouseMovedEvents: YES];
    [NSApp activateIgnoringOtherApps: YES];
    [window makeKeyAndOrderFront: nil];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 1.0]];
    printf("READY\n");
    fflush(stdout);

    BOOL gotMouse = NO, gotKey = NO;
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: 25];
    while ((!gotMouse || !gotKey) && [end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event == nil)
            continue;
        if ([event type] == NSEventTypeLeftMouseDown && !gotMouse) {
            gotMouse = YES;
            checkEventTime(event, "a delivered mouse click");
            checkCGEventLocation(event, NSMakePoint(x, y), "a delivered mouse click");
        } else if ([event type] == NSEventTypeKeyDown && !gotKey) {
            gotKey = YES;
            checkEventTime(event, "a delivered key press");
        }
        [NSApp sendEvent: event];
    }
    expect(gotMouse, "a mouse click was delivered");
    expect(gotKey, "a key press was delivered");
    [window release];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (argc > 3 && strcmp(argv[1], "input") == 0)
            inputChecks(atof(argv[2]), atof(argv[3]));
        else
            apiChecks();
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
