/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSEvent's eventRef (Apple's NSEvent reference, macOS 10.5): the Carbon event
// that corresponds to the event, made once; synthesized events have one too, as on
// macOS 26.7.3 (see also appkit-carbon-event-queue.m).
// The private -_eventRef returns the same.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSEvent (Private)
- (void *) _eventRef;
@end

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSEvent *key = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0
                                       timestamp: 0 windowNumber: 0 context: nil characters: @"a"
                     charactersIgnoringModifiers: @"a" isARepeat: NO keyCode: 0];
        NSEvent *mouse = [NSEvent mouseEventWithType: NSEventTypeLeftMouseDown location: NSZeroPoint modifierFlags: 0
                                           timestamp: 0 windowNumber: 0 context: nil eventNumber: 0 clickCount: 1 pressure: 1];
        CHECK(key.eventRef != NULL && key.eventRef == key.eventRef, "a key event has a Carbon event, made once");
        CHECK(mouse.eventRef != NULL && mouse.eventRef == mouse.eventRef, "a mouse event has a Carbon event, made once");
        CHECK([key _eventRef] == key.eventRef && [mouse _eventRef] == mouse.eventRef, "-_eventRef returns the same");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
