// Copyright (C) 2026 Lubos Dolezel
// Creating cursors from out-of-range input must neither crash nor fail; the
// pointer falls back to a usable cursor. Needs an X11 display (Xvfb :99).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(16, 16)];
        [image lockFocus];
        [[NSColor redColor] set];
        NSRectFill(NSMakeRect(0, 0, 16, 16));
        [image unlockFocus];

        // Hot spots outside the image and non-finite ones.
        NSPoint spots[] = {
            {-5, -5}, {100, 100}, {NAN, 3}, {3, INFINITY}, {8, 8},
        };
        for (size_t i = 0; i < sizeof(spots) / sizeof(*spots); i++) {
            NSCursor *c = [[NSCursor alloc] initWithImage: image hotSpot: spots[i]];
            CHECK(c != nil);
            [c set];
        }

        // Non-finite, empty and enormous images.
        NSSize sizes[] = {{NAN, 16}, {16, INFINITY}, {0, 0}, {1e9, 1e9}, {-4, 4}};
        for (size_t i = 0; i < sizeof(sizes) / sizeof(*sizes); i++) {
            NSImage *big = [[NSImage alloc] initWithSize: sizes[i]];
            NSCursor *c = [[NSCursor alloc] initWithImage: big hotSpot: NSMakePoint(1, 1)];
            CHECK(c != nil);
            [c set];
        }

        // The blank cursor used by -[NSCursor hide] must be defined.
        [NSCursor hide];
        [NSCursor unhide];

        // Legacy-named cursors resolve to something usable.
        [[NSCursor pointingHandCursor] set];
        [[NSCursor IBeamCursor] set];
        [[NSCursor openHandCursor] set];
        [[NSCursor closedHandCursor] set];
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
