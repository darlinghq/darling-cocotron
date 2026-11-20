// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// Mouse-dragged events an application posts with -[NSApplication
// postEvent:atStart:] are dequeued one by one, in order: the mouse coalescing
// NSEvent documents applies to the events of the input devices, not to these.
// Observed on macOS 26.7.3 and 10.14.4 (darling's tests/collection-view.md);
// the program passes unchanged on both.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    int failures = 0;
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 300)
                                                   styleMask: NSWindowStyleMaskBorderless
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window makeKeyAndOrderFront: nil];
    for (int i = 1; i <= 4; i++)
        [NSApp postEvent: [NSEvent mouseEventWithType: NSEventTypeLeftMouseDragged
                                             location: NSMakePoint(10 * i, 10 * i)
                                        modifierFlags: 0
                                            timestamp: 0
                                         windowNumber: [window windowNumber]
                                              context: nil
                                          eventNumber: 0
                                           clickCount: 1
                                             pressure: 1]
                 atStart: NO];
    [NSApp postEvent: [NSEvent mouseEventWithType: NSEventTypeLeftMouseUp
                                         location: NSMakePoint(50, 50)
                                    modifierFlags: 0
                                        timestamp: 0
                                     windowNumber: [window windowNumber]
                                          context: nil
                                          eventNumber: 0
                                       clickCount: 1
                                         pressure: 0]
             atStart: NO];

    NSMutableArray *got = [NSMutableArray array];
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask: NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged
                                       untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]
                                          inMode: NSEventTrackingRunLoopMode
                                         dequeue: YES])) {
        // The types only: macOS 26.7.3 moves the window once it is ordered in, which changes the locations
        [got addObject: [event type] == NSEventTypeLeftMouseUp ? @"up" : @"drag"];
        if ([event type] == NSEventTypeLeftMouseUp)
            break;
    }
    NSString *sequence = [got componentsJoinedByString: @", "];
    BOOL ok = [sequence isEqual: @"drag, drag, drag, drag, up"];
    printf("%s four posted drags and an up come out as posted (%s)\n", ok ? "PASS" : "FAIL", [sequence UTF8String]);
    if (!ok)
        failures++;

    [window release];
    [pool release];
    if (failures)
        printf("FAILED %d\n", failures);
    else
        printf("ALL PASSED\n");
    return failures != 0;
}
