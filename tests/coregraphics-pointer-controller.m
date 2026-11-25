/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
// The pointer calls of CoreGraphics (CGDisplayHideCursor, CGWarpMouseCursorPosition,
// CGAssociateMouseAndMouseCursorPosition, CGGetLastMouseDelta, CGSForceShowCursor) reach what owns the
// pointer in the process through the controller registered with _CGSSetPointerController(): CoreGraphics
// does not find a framework above it by itself. The program links Foundation and CoreGraphics only.
//
// The documented parts: the pointer is warped to a point in the global space, clipped to the desktop;
// an invalid argument is refused with kCGErrorIllegalArgument. Without a controller a warp is done
// by the connection to the window system where it can (X11), else it fails with kCGErrorCannotComplete;
// the cursor calls have nothing to hide and succeed.
// Exit code 0 is success, otherwise the number of the failed check.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSPointerController.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <string.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

extern void CGSForceShowCursor(CGSConnectionID cid);

@interface Controller : NSObject <CGSPointerController> {
@public
    int hides, unhides, forces, associates, deltaTakes;
    BOOL associated;
    CGPoint warped;
    int warps;
}
@end
@implementation Controller
- (void) hideCursor { hides++; }
- (void) unhideCursor { unhides++; }
- (void) forceShowCursor { forces++; }
- (void) warpPointerToPoint: (CGPoint) point { warped = point; warps++; }
- (void) setMouseAssociatedWithCursor: (BOOL) a { associated = a; associates++; }
- (void) takeMouseDeltaX: (int32_t *) dx y: (int32_t *) dy { deltaTakes++; *dx = 3; *dy = -4; }
@end

static BOOL appKitLoaded(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "AppKit.framework"))
            return YES;
    }
    return NO;
}

int main(void) {
    @autoreleasepool {
        CGDirectDisplayID main = CGMainDisplayID();
        CHECK(1, main != kCGNullDirectDisplay);
        CGRect bounds = CGDisplayBounds(main);

        // Without a controller.
        CHECK(2, CGDisplayHideCursor(main) == kCGErrorSuccess);
        CHECK(3, CGDisplayShowCursor(main) == kCGErrorSuccess);
        CHECK(4, CGAssociateMouseAndMouseCursorPosition(false) == kCGErrorSuccess);
        CHECK(5, CGAssociateMouseAndMouseCursorPosition(true) == kCGErrorSuccess);
        int32_t dx = 9, dy = 9;
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(6, dx == 0 && dy == 0);
        CGPoint target = CGPointMake(CGRectGetMidX(bounds) + 5, CGRectGetMidY(bounds) + 7);
        CGError error = CGWarpMouseCursorPosition(target);
        // X11 warps through the connection of CoreGraphics itself; a Wayland client cannot move the pointer.
        BOOL x11 = getenv("DISPLAY") != NULL && getenv("WAYLAND_DISPLAY") == NULL;
        if (x11) {
            CHECK(7, error == kCGErrorSuccess);
            CGEventRef event = CGEventCreate(NULL);
            CGPoint at = CGEventGetLocation(event);
            CFRelease(event);
            CHECK(8, at.x == target.x && at.y == target.y);
        } else {
            CHECK(9, error == kCGErrorSuccess || error == kCGErrorCannotComplete);
        }
        // A coordinate that is not a finite number is taken as 0 and the warp goes on (the QUIRK of
        // CGWarpMouseCursorPosition, pinned by coregraphics-warp-mouse-glue): no illegal-argument error. Without a
        // surface to warp on the result is CannotComplete.
        error = CGWarpMouseCursorPosition(CGPointMake(INFINITY, 0));
        CHECK(10, error == kCGErrorSuccess || error == kCGErrorCannotComplete);

        // The X11 and Wayland connections keep the pointer state themselves and do not use a controller (the hide
        // count, the association, the deltas and the warp are covered by coregraphics-x11-relative-mouse and
        // appkit-wayland-relative-mouse).
        if (x11 || getenv("WAYLAND_DISPLAY") != NULL) {
            CHECK(28, !appKitLoaded());
            printf("PASS\n");
            return 0;
        }

        // With a controller.
        Controller *controller = [[Controller alloc] init];
        _CGSSetPointerController(controller);
        CHECK(11, CGDisplayHideCursor(main) == kCGErrorSuccess && CGDisplayHideCursor(main) == kCGErrorSuccess);
        CHECK(12, CGDisplayShowCursor(main) == kCGErrorSuccess);
        CHECK(13, controller->hides == 2 && controller->unhides == 1);
        CGSForceShowCursor(0);
        CHECK(14, controller->forces == 1);
        CHECK(15, CGAssociateMouseAndMouseCursorPosition(false) == kCGErrorSuccess && !controller->associated);
        CHECK(16, CGAssociateMouseAndMouseCursorPosition(true) == kCGErrorSuccess && controller->associated);
        CGGetLastMouseDelta(&dx, &dy);
        CHECK(17, dx == 3 && dy == -4 && controller->deltaTakes == 1);
        CGGetLastMouseDelta(NULL, NULL);
        CHECK(18, controller->deltaTakes == 2);

        // The point reaches the controller as it is when it is on the desktop, and clipped to the
        // desktop when it is not.
        CHECK(19, CGWarpMouseCursorPosition(target) == kCGErrorSuccess);
        CHECK(20, controller->warps == 1 && controller->warped.x == target.x && controller->warped.y == target.y);
        CHECK(21, CGWarpMouseCursorPosition(CGPointMake(-100000, -100000)) == kCGErrorSuccess);
        CHECK(22, controller->warps == 2 && controller->warped.x <= bounds.origin.x + bounds.size.width && controller->warped.y <= bounds.origin.y + bounds.size.height &&
          controller->warped.x > -100000 && controller->warped.y > -100000);
        CHECK(23, CGWarpMouseCursorPosition(CGPointMake(NAN, 1)) == kCGErrorIllegalArgument && controller->warps == 2);
        // The point is relative to the display's top-left corner.
        CHECK(24, CGDisplayMoveCursorToPoint(main, CGPointMake(10, 20)) == kCGErrorSuccess);
        CHECK(25, controller->warps == 3 && controller->warped.x == bounds.origin.x + 10 && controller->warped.y == bounds.origin.y + 20);
        CHECK(26, CGDisplayMoveCursorToPoint(0xdeadbeef, CGPointZero) == kCGErrorIllegalArgument);

        _CGSSetPointerController(nil);
        CHECK(27, CGDisplayHideCursor(main) == kCGErrorSuccess && controller->hides == 2);
        CHECK(28, !appKitLoaded());
        printf("PASS\n");
    }
    return 0;
}
