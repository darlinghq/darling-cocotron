/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Child windows (-addChildWindow:ordered:), as on Mac OS X 10.14.4 and macOS
// 26.7.3 (black-box observation):
//   - adding a child twice lists it once; adding it does not make it key;
//   - a child of a window on screen is shown; a child of a hidden window stays
//     hidden, also when the parent is shown (10.14.4);
//   - moving the parent moves its attached children by as much (also when the
//     parent is moved and resized at once, and when the window system moves
//     the parent: the -x11.sh harness moves "child-parent" with the window
//     manager and checks the child's X window);
//   - a child that is ordered out leaves its parent: it is no longer listed,
//     does not move with it and does not come back when the parent is ordered
//     in again (a transparent window kept attached would otherwise reappear);
//   - adding a child to another parent takes it from the first.
// Prints PASS/FAIL lines, then "child <x> <y>" (the child's frame origin,
// Cocoa coordinates) and READY; after the harness moved the parent, it prints
// "moved <dx> <dy>" for the parent and "child <x> <y>" again when it sees the
// move. The argument is how long to wait for that, in seconds (0: no wait).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

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

static NSWindow *make(NSString *title, NSRect frame, NSUInteger mask) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    [w setTitle: title];
    [w setReleasedWhenClosed: NO];
    return w;
}

static BOOL at(NSWindow *w, CGFloat x, CGFloat y) {
    return fabs([w frame].origin.x - x) < 0.5 && fabs([w frame].origin.y - y) < 0.5;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 0;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable;

        NSWindow *parent = make(@"child-parent", NSMakeRect(200, 300, 400, 300), titled);
        [parent makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        spin(1);

        // The window manager may have placed the parent elsewhere: put the
        // children relative to where it is.
        NSPoint p0 = [parent frame].origin;
        NSWindow *child = make(@"child-attached", NSMakeRect(p0.x + 50, p0.y + 50, 120, 80), NSWindowStyleMaskBorderless);
        [parent addChildWindow: child ordered: NSWindowAbove];
        [parent addChildWindow: child ordered: NSWindowAbove];
        spin(0.5);
        CHECK([[parent childWindows] count] == 1, "added twice, listed %lu time(s)", (unsigned long) [[parent childWindows] count]);
        CHECK([child parentWindow] == parent, "the child knows its parent");
        CHECK([child isVisible], "a child of a visible window is shown");
        CHECK(![child isKeyWindow], "adding a child does not make it key");

        NSWindow *hidden = make(@"child-hidden", NSMakeRect(p0.x + 80, p0.y + 80, 60, 40), NSWindowStyleMaskBorderless);
        [parent addChildWindow: hidden ordered: NSWindowAbove];
        [hidden orderOut: nil];
        CHECK([hidden parentWindow] == nil && ![[parent childWindows] containsObject: hidden],
              "an ordered-out child leaves its parent");

        [parent setFrameOrigin: NSMakePoint(p0.x + 60, p0.y - 40)];
        spin(0.3);
        CHECK(at(child, p0.x + 110, p0.y + 10), "the child moved with the parent (by %g,%g)",
              [child frame].origin.x - p0.x - 50, [child frame].origin.y - p0.y - 50);
        CHECK(at(hidden, p0.x + 80, p0.y + 80), "the ordered-out child stayed (moved by %g,%g)",
              [hidden frame].origin.x - p0.x - 80, [hidden frame].origin.y - p0.y - 80);

        [parent setFrame: NSMakeRect(p0.x + 30, p0.y - 70, 500, 400) display: YES];
        spin(0.3);
        CHECK(at(child, p0.x + 80, p0.y - 20), "moved and resized parent: the child moved by the origin (by %g,%g)",
              [child frame].origin.x - p0.x - 50, [child frame].origin.y - p0.y - 50);

        [parent orderOut: nil];
        spin(0.3);
        [parent makeKeyAndOrderFront: nil];
        spin(0.5);
        CHECK(![hidden isVisible], "the ordered-out child does not come back with its parent");

        NSWindow *hiddenParent = make(@"child-hidden-parent", NSMakeRect(900, 300, 200, 200), titled);
        NSWindow *late = make(@"child-late", NSMakeRect(920, 320, 50, 50), NSWindowStyleMaskBorderless);
        [hiddenParent addChildWindow: late ordered: NSWindowAbove];
        spin(0.3);
        CHECK(![late isVisible], "a child of a hidden window is not shown");

        NSWindow *moving = make(@"child-moving", NSMakeRect(p0.x + 10, p0.y + 10, 40, 40), NSWindowStyleMaskBorderless);
        [parent addChildWindow: moving ordered: NSWindowAbove];
        [hiddenParent addChildWindow: moving ordered: NSWindowAbove];
        CHECK(![[parent childWindows] containsObject: moving] && [[hiddenParent childWindows] containsObject: moving] &&
                      [moving parentWindow] == hiddenParent,
              "a child added to another parent leaves the first");

        printf("child %.0f %.0f\n", [child frame].origin.x, [child frame].origin.y);
        printf("READY %d\n", failures);
        fflush(stdout);

        // The harness moves the parent with the window manager.
        NSPoint start = [parent frame].origin;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
        while ([deadline timeIntervalSinceNow] > 0 && NSEqualPoints([parent frame].origin, start))
            spin(0.1);
        if (!NSEqualPoints([parent frame].origin, start)) {
            spin(0.5);
            printf("moved %.0f %.0f\n", [parent frame].origin.x - start.x, [parent frame].origin.y - start.y);
            printf("child %.0f %.0f\n", [child frame].origin.x, [child frame].origin.y);
            fflush(stdout);
            // Stay on screen while the harness reads the child's X window.
            spin(5);
        }
        printf("DONE\n");
    }
    return failures != 0;
}
