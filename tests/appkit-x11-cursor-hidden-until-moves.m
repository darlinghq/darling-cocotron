/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
// +[NSCursor setHiddenUntilMouseMoves:YES] on the X11 backend: the cursor comes back when the pointer moves over
// a window of the application, also when no window accepts mouse-moved events (the default), because the backend
// then asks the server for the motion itself (X11PointerMotion.h). The pointer is moved with
// CGWarpMouseCursorPosition, which the X11 backend turns into XWarpPointer, so the window gets real MotionNotify
// events. The cursor calls the backend receives are counted by replacing -hideCursor and -unhideCursor on the
// running display's class. Needs an X session; skipped on others. Build without ARC.
// Documented contract: https://developer.apple.com/documentation/appkit/nscursor/sethiddenuntilmousemoves(_:)
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

// NSDisplay is AppKit's private backend class; only what the test calls is declared.
@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

static int hides, unhides, failures;

static void countHide(id self, SEL _cmd) { hides++; }
static void countUnhide(id self, SEL _cmd) { unhides++; }

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static void pump(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: timeout];
    while (!condition()) {
        if ([end timeIntervalSinceNow] <= 0)
            return NO;
        pump(0.05);
    }
    return YES;
}

static NSWindow *window;
static CGFloat screenHeight;

// A point of the content view, as a pointer position in the global CoreGraphics space (y down).
static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y) toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        id display = [NSDisplay currentDisplay];
        if (![NSStringFromClass([display class]) hasPrefix: @"X11"]) {
            printf("SKIP: not the X11 backend\n");
            return 0;
        }
        screenHeight = [[NSScreen mainScreen] frame].size.height;
        Class cls = [display class];
        class_replaceMethod(cls, @selector(hideCursor), (IMP) countHide, "v@:");
        class_replaceMethod(cls, @selector(unhideCursor), (IMP) countUnhide, "v@:");

        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        expect(![window acceptsMouseMovedEvents], "the window does not accept mouse-moved events");
        [window orderFront: nil];
        pump(0.5);

        movePointer(50, 50);
        pump(0.3);
        hides = unhides = 0;
        [NSCursor setHiddenUntilMouseMoves: YES];
        expect(hides == 1 && unhides == 0, "the cursor is hidden");
        movePointer(200, 150);
        expect(waitFor(^BOOL { return unhides == 1; }, 3.0), "motion over the window brings the cursor back");

        // The wait is over, so the next motion changes nothing.
        movePointer(250, 120);
        pump(0.5);
        expect(hides == 1 && unhides == 1, "later motion does nothing");

        // A second wait works the same way.
        [NSCursor setHiddenUntilMouseMoves: YES];
        movePointer(60, 60);
        expect(waitFor(^BOOL { return unhides == 2; }, 3.0), "a second wait ends on motion as well");

        // An explicit hide outlives the motion.
        hides = unhides = 0;
        [NSCursor hide];
        [NSCursor setHiddenUntilMouseMoves: YES];
        movePointer(300, 200);
        pump(0.5);
        expect(hides == 1 && unhides == 0, "motion does not undo an explicit hide");
        [NSCursor unhide];
        expect(unhides == 1, "the matching unhide shows the cursor");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures ? 1 : 0;
}
