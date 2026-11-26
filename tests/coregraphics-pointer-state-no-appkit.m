// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process that links Foundation and CoreGraphics only (no AppKit) uses the pointer functions of
// CoreGraphics through its own connection to the window system: the hide count, the mouse association, the mouse
// delta and the warp need no framework above CoreGraphics. Run with DARLING_APPKIT_BACKEND=wayland and
// WAYLAND_DISPLAY set (the Wayland connection of CoreGraphics keeps the state), or on X11. It has no window, so the
// pointer is never over one of its surfaces: the calls succeed, the delta is zero, a warp has no surface to put the
// cursor in and says so (kCGErrorCannotComplete) instead of reporting a move that did not happen, and AppKit is not
// loaded by any of them.
// Usage: coregraphics-pointer-state-no-appkit (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

static BOOL appKitLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name != NULL && strstr(name, "AppKit.framework") != NULL)
            return YES;
    }
    return NO;
}

int main(void) {
    @autoreleasepool {
        CGDirectDisplayID display = CGMainDisplayID();
        expect(display != 0, @"there is a main display");

        expect(CGDisplayHideCursor(display) == kCGErrorSuccess, @"CGDisplayHideCursor succeeds");
        expect(CGDisplayHideCursor(display) == kCGErrorSuccess, @"a second hide succeeds");
        expect(CGDisplayShowCursor(display) == kCGErrorSuccess, @"CGDisplayShowCursor succeeds");
        expect(CGDisplayShowCursor(display) == kCGErrorSuccess, @"the second show succeeds");
        expect(CGDisplayShowCursor(display) == kCGErrorSuccess, @"a show with nothing hidden succeeds");
        CGSForceShowCursor(0);

        int32_t dx = 5, dy = 5;
        CGGetLastMouseDelta(&dx, &dy);
        expect(dx == 0 && dy == 0, @"no mouse motion, no delta");

        expect(CGAssociateMouseAndMouseCursorPosition(false) == kCGErrorSuccess, @"the mouse can be disconnected from the cursor");
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
        CGEventRef event = CGEventCreate(source);
        CGPoint where = CGEventGetLocation(event);
        CFRelease(event);
        CFRelease(source);
        CGError warp = CGWarpMouseCursorPosition(CGPointMake(where.x + 10, where.y + 10));
        expect(warp == kCGErrorCannotComplete || warp == kCGErrorSuccess, @"a warp without a surface under the pointer reports its outcome");
        expect(CGAssociateMouseAndMouseCursorPosition(true) == kCGErrorSuccess, @"the mouse can be connected again");
        // A non-finite coordinate is taken as 0 (the quirk pinned by coregraphics-warp-mouse-glue), so the warp is
        // an ordinary one: not an illegal argument.
        CGError nanWarp = CGWarpMouseCursorPosition(CGPointMake(NAN, 0));
        expect(nanWarp == kCGErrorCannotComplete || nanWarp == kCGErrorSuccess, @"a warp to NaN is an ordinary warp, not an illegal argument");

        expect(!appKitLoaded(), @"AppKit is not loaded by any of it");
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
