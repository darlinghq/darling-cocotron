// Copyright (C) 2026 Lubos Dolezel
// Cursor updates from tracking areas and cursor rects: the pointer entering an
// area with NSTrackingCursorUpdate (an explicit tracking area or a cursor rect)
// sends -cursorUpdate: to the owner, which sets the cursor; the cursor returns
// to the arrow when the pointer leaves all such areas; and when the pointer
// leaves an area nested in a larger cursor area it is still inside, the larger
// area decides the cursor again. The pointer is moved with
// CGWarpMouseCursorPosition, which the X11 backend turns into XWarpPointer, so
// the window gets real MotionNotify events. Needs an X server with a window
// manager, e.g. Xvfb :99 with xfwm4 (the window must become key).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static BOOL waitFor(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: timeout];
    while (!condition()) {
        if ([end timeIntervalSinceNow] <= 0)
            return NO;
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    }
    return YES;
}

// A view with a cursor rect over all of it (legacy cursor rects are cursor-update
// tracking areas owned by the view).
@interface RectView : NSView
@end
@implementation RectView
- (void) resetCursorRects {
    [self addCursorRect: [self bounds] cursor: [NSCursor crosshairCursor]];
}
@end

// A view whose own tracking area has the cursor-update option.
@interface AreaView : NSView {
@public
    int cursorUpdates;
}
@end
@implementation AreaView
- (void) updateTrackingAreas {
    for (NSTrackingArea *area in [self trackingAreas])
        [self removeTrackingArea: area];
    [self addTrackingArea: [[NSTrackingArea alloc]
            initWithRect: [self bounds]
                 options: NSTrackingCursorUpdate | NSTrackingActiveInKeyWindow
                   owner: self
                userInfo: nil]];
    [super updateTrackingAreas];
}
- (void) cursorUpdate: (NSEvent *) event {
    cursorUpdates++;
    [[NSCursor pointingHandCursor] set];
}
@end

static NSWindow *window;
static CGFloat screenHeight;

// A point of the content view to the global CoreGraphics space (y down from the
// top of the main screen), where the pointer is moved.
static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y)
                                                                            toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

static BOOL cursorBecomes(NSCursor *cursor) {
    return waitFor(^BOOL { return [NSCursor currentCursor] == cursor; }, 3.0);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        screenHeight = [[NSScreen mainScreen] frame].size.height;

        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSView *content = [window contentView];
        NSRect bounds = [content bounds];
        RectView *left = [[RectView alloc] initWithFrame: NSMakeRect(0, 0, bounds.size.width / 2, bounds.size.height)];
        AreaView *inner = [[AreaView alloc] initWithFrame: NSMakeRect(50, 100, 100, 100)];
        [left addSubview: inner];
        [content addSubview: left];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        BOOL key = waitFor(^BOOL { return [window isKeyWindow]; }, 5.0);
        expect(key, "the window becomes key");
        if (!key) {
            printf("FAILED\n");
            return 1;
        }
        [window setAcceptsMouseMovedEvents: YES];
        // Coordinates below are those of the content view.
        movePointer(300, 150); // right half, no cursor area
        [[NSCursor arrowCursor] set];
        waitFor(^BOOL { return NO; }, 0.5);

        movePointer(20, 50); // inside the left view, outside the inner view
        expect(cursorBecomes([NSCursor crosshairCursor]), "entering a cursor rect sets its cursor");

        movePointer(100, 150); // inside the inner view
        expect(cursorBecomes([NSCursor pointingHandCursor]), "entering the nested tracking area sets its cursor");
        expect(inner->cursorUpdates == 1, "cursorUpdate: is sent once on entry");

        movePointer(105, 155); // still inside
        waitFor(^BOOL { return NO; }, 0.5);
        expect(inner->cursorUpdates == 1, "moving inside the area does not send cursorUpdate: again");

        movePointer(20, 50); // back out of the inner view, still in the left view
        expect(cursorBecomes([NSCursor crosshairCursor]),
               "leaving the nested area returns to the enclosing area's cursor");

        movePointer(300, 150); // out of all cursor areas
        expect(cursorBecomes([NSCursor arrowCursor]), "leaving all cursor areas restores the arrow");

        movePointer(100, 150); // straight into the nested area
        expect(cursorBecomes([NSCursor pointingHandCursor]), "entering the nested area again sets its cursor");
        expect(inner->cursorUpdates == 2, "cursorUpdate: is sent again on re-entry");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
