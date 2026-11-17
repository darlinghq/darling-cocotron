// Copyright (C) 2026 Lubos Dolezel
//
// Buttons and pop-up buttons are flipped views on macOS 10.14.4 and 26.7.3. Custom button cells draw
// their bezel and title in the coordinates of a flipped view, so a button that is not flipped puts them
// at the wrong edge and clips them.
//
// Build: clang -fobjc-arc -framework AppKit appkit-button-is-flipped.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 100, 40);
        CHECK([[[NSButton alloc] initWithFrame:frame] isFlipped]);
        CHECK([[[NSPopUpButton alloc] initWithFrame:frame] isFlipped]);
        NSButton *check = [[NSButton alloc] initWithFrame:frame];
        [check setButtonType:NSButtonTypeSwitch];
        CHECK([check isFlipped]);
        // Views that are not buttons are not affected.
        CHECK(![[[NSView alloc] initWithFrame:frame] isFlipped]);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
