/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSWindow trackEventsMatchingMask:timeout:mode:handler:] and the NSEvent
// monitors, driven with synthetic events posted by -postEvent:atStart:. Checks the order in
// which the handler sees the events, the stop flag (events not consumed stay queued),
// events that don't match the mask, the nil event of a timeout, local monitors
// (mask, replace, swallow, removal) and that a global monitor can be added and removed.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSEvent *click(NSWindow *window, NSEventType type, NSInteger number) {
    return [NSEvent mouseEventWithType: type
                              location: NSMakePoint(5, 5)
                         modifierFlags: 0
                             timestamp: 0
                          windowNumber: [window windowNumber]
                               context: nil
                           eventNumber: number
                            clickCount: 1
                              pressure: 1];
}

static NSEvent *poll(NSEventMask mask) {
    return [NSApp nextEventMatchingMask: mask
                              untilDate: [NSDate distantPast]
                                 inMode: NSEventTrackingRunLoopMode
                                dequeue: YES];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 50, 50)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];

        // Order: posted at the end in sequence, atStart: YES goes first.
        NSEvent *a = click(window, NSEventTypeLeftMouseDown, 1);
        NSEvent *b = click(window, NSEventTypeLeftMouseDown, 2);
        NSEvent *c = click(window, NSEventTypeLeftMouseDown, 3);
        NSEvent *other = click(window, NSEventTypeRightMouseDown, 4);
        [NSApp postEvent: a atStart: NO];
        [NSApp postEvent: other atStart: NO];
        [NSApp postEvent: b atStart: NO];
        [NSApp postEvent: c atStart: YES];

        __block NSMutableArray *seen = [NSMutableArray array];
        __block int calls = 0;
        [window trackEventsMatchingMask: NSEventMaskLeftMouseDown
                                timeout: 2
                                   mode: NSEventTrackingRunLoopMode
                                handler: ^(NSEvent *event, BOOL *stop) {
                                    calls++;
                                    [seen addObject: event ?: (id) [NSNull null]];
                                    // *stop is NO on entry.
                                    if (*stop)
                                        calls += 100;
                                    if (calls == 2)
                                        *stop = YES;
                                }];
        expect(calls == 2, "tracking ends when the handler sets stop");
        expect([seen count] == 2 && seen[0] == c && seen[1] == a,
               "matching events reach the handler in queue order, atStart first");

        // The event that wasn't consumed and the one that doesn't match are still queued.
        NSEvent *left = poll(NSEventMaskLeftMouseDown);
        expect(left == b, "an event after the stop is left in the queue");
        NSEvent *right = poll(NSEventMaskRightMouseDown);
        expect(right == other, "an event outside the mask is left in the queue");

        // Timeout: nil event, once per elapsed interval, until the handler stops.
        __block int nilCalls = 0;
        NSDate *start = [NSDate date];
        [window trackEventsMatchingMask: NSEventMaskLeftMouseDown
                                timeout: 0.15
                                   mode: NSEventTrackingRunLoopMode
                                handler: ^(NSEvent *event, BOOL *stop) {
                                    if (event == nil)
                                        nilCalls++;
                                    if (nilCalls == 2)
                                        *stop = YES;
                                }];
        NSTimeInterval elapsed = -[start timeIntervalSinceNow];
        expect(nilCalls == 2, "a timeout calls the handler with a nil event");
        expect(elapsed >= 0.25 && elapsed < 3, "each timeout waits for its interval");

        // An event posted before a timeout is delivered, not a nil event, and an event outside
        // the mask doesn't end the wait early.
        [NSApp postEvent: other atStart: NO];
        [NSApp postEvent: click(window, NSEventTypeLeftMouseDown, 5) atStart: NO];
        __block NSEvent *got = nil;
        [window trackEventsMatchingMask: NSEventMaskLeftMouseDown
                                timeout: 2
                                   mode: NSEventTrackingRunLoopMode
                                handler: ^(NSEvent *event, BOOL *stop) {
                                    got = event;
                                    *stop = YES;
                                }];
        expect(got != nil && [got eventNumber] == 5, "a queued event is delivered before any timeout");
        expect(poll(NSEventMaskRightMouseDown) == other, "the unmatched event is still queued");

        // Local monitors, through -[NSApplication sendEvent:].
        __block int leftSeen = 0, rightSeen = 0;
        id leftMonitor = [NSEvent addLocalMonitorForEventsMatchingMask: NSEventMaskLeftMouseDown
                                                               handler: ^NSEvent *(NSEvent *event) {
                                                                   leftSeen++;
                                                                   return event;
                                                               }];
        expect(leftMonitor != nil, "a local monitor is returned");
        id swallow = [NSEvent addLocalMonitorForEventsMatchingMask: NSEventMaskRightMouseDown
                                                           handler: ^NSEvent *(NSEvent *event) {
                                                               rightSeen++;
                                                               return nil;
                                                           }];
        [NSApp sendEvent: click(window, NSEventTypeLeftMouseDown, 6)];
        [NSApp sendEvent: click(window, NSEventTypeRightMouseDown, 7)];
        expect(leftSeen == 1, "a local monitor sees events of its mask");
        expect(rightSeen == 1, "a local monitor can swallow an event");
        [NSEvent removeMonitor: leftMonitor];
        [NSApp sendEvent: click(window, NSEventTypeLeftMouseDown, 8)];
        expect(leftSeen == 1, "a removed local monitor isn't called");
        [NSEvent removeMonitor: leftMonitor];
        [NSEvent removeMonitor: swallow];
        [NSEvent removeMonitor: nil];
        [NSApp sendEvent: click(window, NSEventTypeRightMouseDown, 9)];
        expect(rightSeen == 1, "removing twice and removing nil are harmless");

        // Global monitor: a token that can be removed. Events of this application are not
        // passed to it, as on macOS, and no event of another application can be seen here.
        __block int globalSeen = 0;
        id global = [NSEvent addGlobalMonitorForEventsMatchingMask: (NSEventMask) ~(NSEventMask) 0
                                                           handler: ^(NSEvent *event) {
                                                               globalSeen++;
                                                           }];
        expect(global != nil, "a global monitor is returned");
        [NSApp sendEvent: click(window, NSEventTypeLeftMouseDown, 10)];
        expect(globalSeen == 0, "events of this application don't reach a global monitor");
        [NSEvent removeMonitor: global];
        [NSEvent removeMonitor: global];
        expect(globalSeen == 0, "removing a global monitor is harmless");
        expect([NSEvent addGlobalMonitorForEventsMatchingMask: (NSEventMask) ~(NSEventMask) 0 handler: nil] == nil,
               "a global monitor needs a handler");
    }
    if (failures == 0)
        printf("event monitors tracking: PASS\n");
    return failures != 0;
}
