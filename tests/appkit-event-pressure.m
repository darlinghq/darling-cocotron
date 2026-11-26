/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSEvent's pressure, stage and stageTransition (Apple's NSEvent reference):
// a device that is not pressure-sensitive gives a pressure of 0 or 1, and
// stage 0 means no pressure stage. The pressure event types keep their public
// values.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

static NSEvent *mouse(NSEventType type, float pressure) {
    return [NSEvent mouseEventWithType: type location: NSZeroPoint modifierFlags: 0 timestamp: 0
                          windowNumber: 0 context: nil eventNumber: 0 clickCount: 1 pressure: pressure];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        CHECK(NSEventTypePressure == 34 && NSEventTypeSmartMagnify == 32 && NSEventTypeQuickLook == 33
              && NSEventTypeGesture == 29 && NSEventTypeSwipe == 31
              && NSEventTypeBeginGesture == 19 && NSEventTypeEndGesture == 20,
              "event types keep their public values");
        CHECK(NSEventMaskPressure == (1ULL << 34), "the pressure mask is built from its type");

        NSEvent *down = mouse(NSEventTypeLeftMouseDown, 0.5f);
        CHECK(down.pressure == 0.5f, "a mouse event keeps the pressure it was made with");
        CHECK(down.stage == 0 && down.stageTransition == 0, "a mouse event has no pressure stage");

        NSEvent *key = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0
                                       timestamp: 0 windowNumber: 0 context: nil characters: @"a"
                     charactersIgnoringModifiers: @"a" isARepeat: NO keyCode: 0];
        CHECK(key.pressure == 0 && key.stage == 0, "a key event has no pressure");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
