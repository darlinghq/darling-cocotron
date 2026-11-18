/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#include <stdio.h>

// NSEventMaskAny is NSUIntegerMax: 0xffffffff in a 32-bit process, which has
// no bit for the event types from 32 up (direct touch is 37). Such a mask
// must still dequeue every event type, and a mask for other types must not.
// Runs on the real display queue; needs a display server.
static int failures, checks;

static void expect(BOOL ok, const char *what) {
    ++checks; if (!ok) ++failures;
    printf("%s %s\n", ok ? "PASS" : "FAIL", what); fflush(stdout);
}

static NSEvent *touchEvent(void) {
    return [NSEvent otherEventWithType:NSEventTypeDirectTouch location:NSZeroPoint modifierFlags:0
                             timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
}

static NSEvent *next(NSUInteger mask, BOOL dequeue) {
    return [NSApp nextEventMatchingMask:mask untilDate:[NSDate distantPast]
                                 inMode:NSDefaultRunLoopMode dequeue:dequeue];
}

static void expectDequeued(NSUInteger mask, const char *what) {
    NSEvent *posted = touchEvent();
    [NSApp postEvent:posted atStart:NO];
    NSEvent *got = next(mask, YES);
    char text[128];
    snprintf(text, sizeof text, "a type >= 32 event is dequeued with %s", what);
    expect(got == posted && [got type] == NSEventTypeDirectTouch, text);
    // Drain in case it was not taken.
    while (next(NSUIntegerMax, YES) != nil) {}
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        expect(NSEventTypeDirectTouch >= 32, "direct touch is an event type of 32 or more");
        expectDequeued(NSAnyEventMask, "NSAnyEventMask");
        expectDequeued(NSEventMaskAny, "NSEventMaskAny");
        // What 32-bit callers pass for "any". In a 64-bit process the same
        // value is just the low 32 event types, so only 32-bit processes ask.
        if (sizeof(NSUInteger) == 4)
            expectDequeued((NSUInteger)0xffffffffu, "the explicit mask 0xffffffff");

        NSEvent *posted = touchEvent();
        [NSApp postEvent:posted atStart:NO];
        expect(next(NSEventMaskLeftMouseDown, YES) == nil, "a mask for another type does not dequeue it");
        expect(next(NSEventMaskDirectTouch, YES) == posted || sizeof(NSUInteger) == 4,
               "the direct touch mask dequeues it (64-bit)");
        while (next(NSUIntegerMax, YES) != nil) {}
    }
    printf("RESULT checks=%d failures=%d\n", checks, failures);
    return failures != 0;
}
