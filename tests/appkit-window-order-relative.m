/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSWindow orderWindow:relativeTo:] with a window number orders the window directly above or below that
// window, also when a window manager has put the two windows in frames of their own: the stacking request
// must go to the windows the X server stacks together, not to the client windows inside the frames (which are
// not siblings, and the X server answers such a request with BadMatch). The -x11.sh harness runs this on a
// display with a window manager and fails when the application reports an X error.
// Prints PASS/FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static NSWindow *makeWindow(NSString *title, CGFloat x) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(x, 200, 200, 150)
                                              styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    [w setReleasedWhenClosed: NO];
    [w setTitle: title];
    return w;
}

static NSInteger indexOf(NSWindow *w) {
    return [[NSApp orderedWindows] indexOfObjectIdenticalTo: w];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        NSWindow *a = makeWindow(@"order-a", 100);
        NSWindow *b = makeWindow(@"order-b", 350);
        NSWindow *c = makeWindow(@"order-c", 600);
        [a orderFront: nil];
        spin(0.7);
        [b orderFront: nil];
        spin(0.7);
        [c orderFront: nil];
        spin(0.7);
        // front to back: c, b, a

        [a orderWindow: NSWindowAbove relativeTo: [b windowNumber]];
        spin(0.7);
        CHECK(indexOf(a) == indexOf(b) - 1, "a ordered above b sits directly above it");
        CHECK(indexOf(c) < indexOf(a), "c stays in front of a");

        [c orderWindow: NSWindowBelow relativeTo: [a windowNumber]];
        spin(0.7);
        CHECK(indexOf(c) == indexOf(a) + 1, "c ordered below a sits directly below it");
        CHECK(indexOf(c) < indexOf(b), "c stays in front of b");

        [a close];
        [b close];
        [c close];
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
