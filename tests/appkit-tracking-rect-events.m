// Copyright (C) 2026 Lubos Dolezel
//
// Events of tracking rectangles and areas. The events of a rectangle made with -addTrackingRect:owner:userData:
// assumeInside: carry its tag as -trackingNumber and have no -trackingArea; those of an NSTrackingArea have it. A
// rectangle added after a stale tag was handed to -removeTrackingRect: (twice) still gets its events. The pointer is
// moved with CGWarpMouseCursorPosition, which the X11 backend turns into XWarpPointer. Needs an X server with a
// window manager.
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

@interface Recorder : NSObject {
@public
    NSInteger enteredTag;
    NSInteger enteredCount;
    NSTrackingArea *enteredArea;
}
@end
@implementation Recorder
- (void) mouseEntered: (NSEvent *) event {
    enteredTag = [event trackingNumber];
    enteredArea = [event trackingArea];
    enteredCount++;
}
- (void) mouseExited: (NSEvent *) event {
}
@end

static NSWindow *window;
static CGFloat screenHeight;

static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y) toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        screenHeight = [[NSScreen mainScreen] frame].size.height;
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        [window setContentView: view];
        Recorder *recorder = [[Recorder alloc] init];

        // Tags are distinct, and the rectangles are told apart by them.
        NSInteger a = (NSInteger)[view addTrackingRect: NSMakeRect(0, 0, 100, 100) owner: recorder userData: NULL assumeInside: NO];
        NSInteger b = (NSInteger)[view addTrackingRect: NSMakeRect(200, 0, 100, 100) owner: recorder userData: NULL assumeInside: NO];
        NSInteger tip = (NSInteger)[view addToolTipRect: NSMakeRect(0, 200, 100, 100) owner: @"tip" userData: NULL];
        expect(a != b && a != tip && b != tip, "tags of different rectangles are distinct");

        // Stale tags are ignored (this crashed when a tag was a pointer to the rectangle).
        [view removeTrackingRect: (NSTrackingRectTag)a];
        [view removeTrackingRect: (NSTrackingRectTag)a];
        [view removeToolTip: (NSToolTipTag)tip];
        [view removeToolTip: (NSToolTipTag)tip];
        expect(YES, "removing a stale tag is harmless");

        // A new rectangle is not named by the tag of the removed one, even when the allocator reuses memory.
        NSInteger c = (NSInteger)[view addTrackingRect: NSMakeRect(0, 0, 100, 100) owner: recorder userData: NULL assumeInside: NO];
        expect(c != a && c != b, "a new tag differs from removed and live ones");
        [view removeTrackingRect: (NSTrackingRectTag)a];
        [view removeToolTip: (NSToolTipTag)a];

        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        BOOL visible = waitFor(^BOOL { return [window isVisible]; }, 5.0);
        expect(visible, "the window is visible");
        if (!visible) {
            printf("FAILED\n");
            return 1;
        }
        [window setAcceptsMouseMovedEvents: YES];
        movePointer(350, 250);
        waitFor(^BOOL { return NO; }, 0.5);
        movePointer(50, 50); // inside c
        BOOL entered = waitFor(^BOOL { return recorder->enteredCount > 0; }, 3.0);
        expect(entered, "the rectangle added after removing a tag twice still receives mouseEntered:");
        expect(recorder->enteredTag == c, "the event's trackingNumber is the tag the rectangle was created with");
        expect(recorder->enteredArea == nil, "the event of a tracking rectangle has no trackingArea");

        [view removeTrackingRect: (NSTrackingRectTag)c];
        [view removeTrackingRect: (NSTrackingRectTag)b];
        [view removeTrackingRect: (NSTrackingRectTag)c];

        // An area made with NSTrackingArea reports itself.
        NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect: NSMakeRect(200, 0, 100, 100)
                                                            options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                              owner: recorder
                                                           userInfo: nil];
        [view addTrackingArea: area];
        recorder->enteredCount = 0;
        movePointer(350, 250);
        waitFor(^BOOL { return NO; }, 0.3);
        movePointer(250, 50);
        entered = waitFor(^BOOL { return recorder->enteredCount > 0; }, 3.0);
        expect(entered, "an NSTrackingArea receives mouseEntered:");
        expect(recorder->enteredArea == area, "the event of an NSTrackingArea has it as trackingArea");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
