// CFLAGS: -framework Foundation -framework ApplicationServices
// Copyright (C) 2026 Lubos Dolezel
//
// The state queries of CoreGraphics follow the window system's input: the location of CGEventCreate(NULL) is
// where the pointer is, CGEventSourceFlagsState() the modifiers that are held and CGEventSourceButtonState() the
// buttons, for the combined session state and the HID system state alike. The process has no window and no
// AppKit, so the answers are the window system's, not a record of the process' own events. Driven by
// coregraphics-state-queries-x11.sh (XTest): the program prints READY, PHASE2 once the pointer is at its place and
// PHASE3 once Shift and the left button are down and have been checked; it waits at most 40 seconds in all.
//
// Usage: coregraphics-state-queries
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>

static int failures;
static void expect(int ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

static CGPoint pointerLocation(void) {
    CGEventRef event = CGEventCreate(NULL);
    CGPoint point = CGEventGetLocation(event);
    CFRelease(event);
    return point;
}

static void waitUntil(double seconds, int (^done)(void)) {
    for (int i = 0; i < seconds * 20 && !done(); i++)
        usleep(50000);
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        // Nothing is held: the window system says so before any event of the process exists.
        const CGEventFlags modifiers = kCGEventFlagMaskShift | kCGEventFlagMaskControl | kCGEventFlagMaskAlternate |
                                       kCGEventFlagMaskCommand;
        expect((CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & modifiers) == 0,
               @"no modifier is held at the start");
        printf("READY\n");

        // The pointer is moved to (300, 200).
        waitUntil(20, ^int { CGPoint p = pointerLocation(); return fabs(p.x - 300) <= 1 && fabs(p.y - 200) <= 1; });
        CGPoint p = pointerLocation();
        expect(fabs(p.x - 300) <= 1 && fabs(p.y - 200) <= 1,
               [NSString stringWithFormat: @"CGEventCreate(NULL) has the pointer's location (%.0f, %.0f)", p.x, p.y]);
        printf("PHASE2\n");

        // Shift and the left button are held.
        waitUntil(20, ^int { return CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft) &&
                                    (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kCGEventFlagMaskShift); });
        CGEventSourceStateID states[2] = {kCGEventSourceStateCombinedSessionState, kCGEventSourceStateHIDSystemState};
        for (int i = 0; i < 2; i++) {
            NSString *name = i == 0 ? @"combined" : @"HID";
            expect((CGEventSourceFlagsState(states[i]) & kCGEventFlagMaskShift) != 0,
                   [NSString stringWithFormat: @"CGEventSourceFlagsState() has Shift (%@ state)", name]);
            expect(CGEventSourceButtonState(states[i], kCGMouseButtonLeft),
                   [NSString stringWithFormat: @"CGEventSourceButtonState() has the left button (%@ state)", name]);
            expect(!CGEventSourceButtonState(states[i], kCGMouseButtonRight) &&
                   !CGEventSourceButtonState(states[i], kCGMouseButtonCenter),
                   [NSString stringWithFormat: @"  and not the others (%@ state)", name]);
        }
        expect((CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & (modifiers & ~kCGEventFlagMaskShift)) == 0,
               @"  and no other modifier");
        printf("PHASE3\n");

        // They are let go.
        waitUntil(20, ^int { return !CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft) &&
                                    !(CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & kCGEventFlagMaskShift); });
        expect((CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & modifiers) == 0 &&
               !CGEventSourceButtonState(kCGEventSourceStateCombinedSessionState, kCGMouseButtonLeft),
               @"Shift and the button are released");
    }
    if (failures == 0)
        printf("ALL PASSED\n");
    else
        printf("FAILED %d\n", failures);
    return failures != 0;
}
