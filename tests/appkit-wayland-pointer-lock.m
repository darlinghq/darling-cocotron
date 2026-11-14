/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Relative mouse mode on the Wayland backend (zwp_pointer_constraints_v1 and
// zwp_relative_pointer_v1), seen through the CoreGraphics and AppKit API. Needs a compositor
// that grants the lock to a focused window: run with DARLING_APPKIT_BACKEND=wayland and
// WAYLAND_DISPLAY set. Prints SKIP when the backend is not selected or when the lock is
// never granted (no focus, or the compositor offers no constraint protocols), because a
// warp without a lock does nothing by design.
// While the mouse is disassociated from the cursor, CGWarpMouseCursorPosition (CoreGraphics
// global space, y down) moves the cursor the application sees, and +[NSEvent mouseLocation]
// (y up) reports exactly that point, so the two are inverses of each other.
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void pump(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

int main(void) {
    const char *backend = getenv("DARLING_APPKIT_BACKEND");
    if (backend == NULL || strcasecmp(backend, "wayland") != 0 || getenv("WAYLAND_DISPLAY") == NULL) {
        printf("SKIP: needs DARLING_APPKIT_BACKEND=wayland and WAYLAND_DISPLAY\n");
        return 0;
    }
    int failures = 0;
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSBorderlessWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window makeKeyAndOrderFront: nil];
        pump(0.5);

        CGAssociateMouseAndMouseCursorPosition(false);
        pump(1.0);

        NSRect frame = [window frame];
        CGFloat primaryHeight = NSHeight([[[NSScreen screens] objectAtIndex: 0] frame]);
        // A point inside the window, in CoreGraphics global space (y down).
        CGPoint target = CGPointMake(NSMinX(frame) + 120, primaryHeight - (NSMinY(frame) + 80));
        NSPoint before = [NSEvent mouseLocation];
        CGWarpMouseCursorPosition(target);
        pump(0.2);
        NSPoint after = [NSEvent mouseLocation];

        if (fabs(after.x - before.x) < 0.5 && fabs(after.y - before.y) < 0.5 &&
            fabs(after.x - target.x) > 0.5) {
            printf("SKIP: the compositor did not lock the pointer\n");
            CGAssociateMouseAndMouseCursorPosition(true);
            return 0;
        }
        if (fabs(after.x - target.x) > 0.5 || fabs(after.y - (primaryHeight - target.y)) > 0.5) {
            fprintf(stderr, "FAIL: warped to (%g, %g) in CoreGraphics space, mouseLocation is (%g, %g)\n",
                    target.x, target.y, after.x, after.y);
            failures++;
        }
        CGAssociateMouseAndMouseCursorPosition(true);
        [window orderOut: nil];
        [window release];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures ? 1 : 0;
}
