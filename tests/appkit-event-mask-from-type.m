// Copyright (C) 2026 Lubos Dolezel
// NSEventMaskFromType() returns the one-bit mask of an event type, also for the types of 32 and
// up (the public NSEventType values go to 37 and beyond, and NSEventMask is 64 bits wide).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static void expect(NSEventType type, unsigned long long want, const char *name) {
    unsigned long long got = NSEventMaskFromType(type);
    int ok = got == want;
    printf("%s %s: %llx\n", ok ? "PASS" : "FAIL", name, got);
    if (!ok) failures++;
}

int main(void) {
    @autoreleasepool {
        expect(NSEventTypeLeftMouseDown, 1ULL << 1, "NSEventTypeLeftMouseDown (1)");
        expect(NSEventTypeApplicationDefined, 1ULL << 15, "NSEventTypeApplicationDefined (15)");
        expect((NSEventType) 32, 1ULL << 32, "NSEventTypeSmartMagnify (32)");
        expect((NSEventType) 34, 1ULL << 34, "NSEventTypePressure (34)");
        expect((NSEventType) 37, 1ULL << 37, "NSEventTypeDirectTouch (37)");
        expect(NSEventTypeMouseEntered, 1ULL << 8, "NSEventTypeMouseEntered (8)");
        printf("RESULT failures=%d\n", failures);
    }
    return failures != 0;
}
