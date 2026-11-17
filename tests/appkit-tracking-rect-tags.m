// Copyright (C) 2026 Lubos Dolezel
//
// The tags returned by -addTrackingRect:owner:userData:assumeInside: and -addToolTipRect:owner:userData: are
// opaque numbers (NSTrackingRectTag, NSToolTipTag: NSInteger; the casts keep the file valid for SDKs that declare
// them differently). Applications keep a tag in an instance variable and hand it to -removeTrackingRect: or
// -removeToolTip: possibly after the rectangle is gone, e.g. a view that replaces its rectangle when it moves to
// another window. A tag that does not name a rectangle of the view (removed already) is ignored, and tags of
// different rectangles differ. Needs no pointer events, runs on a Mac too.
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

        [window makeKeyAndOrderFront: nil];
        waitFor(^BOOL { return NO; }, 0.5);
        [view removeTrackingRect: (NSTrackingRectTag)c];
        [view removeTrackingRect: (NSTrackingRectTag)b];
        [view removeTrackingRect: (NSTrackingRectTag)c];
        expect(YES, "the window with the remaining rectangles shows and the rectangles are removed");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
