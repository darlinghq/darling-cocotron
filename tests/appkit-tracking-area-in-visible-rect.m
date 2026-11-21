// Copyright (C) 2026 Lubos Dolezel
//
// An area made with NSTrackingInVisibleRect stays in step with the view's visibleRect, and the rect it was created
// with is ignored (https://developer.apple.com/documentation/appkit/nstrackingarea/options-swift.struct/invisiblerect).
// So an area given an empty rect, or a small corner rect, still gets mouseEntered: and mouseExited: across the whole
// view. The view is smaller than the window's content view so the pointer can leave it and stay in the window. The
// pointer is moved with CGWarpMouseCursorPosition. Needs an X server with a window manager. Build without ARC.
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
    NSInteger entered, exited;
}
@end
@implementation Recorder
- (void) mouseEntered: (NSEvent *) event {
    entered++;
}
- (void) mouseExited: (NSEvent *) event {
    exited++;
}
@end

static NSWindow *window;
static CGFloat screenHeight;

static void movePointer(CGFloat x, CGFloat y) {
    NSPoint screen = [window convertBaseToScreen: [[window contentView] convertPoint: NSMakePoint(x, y) toView: nil]];
    CGWarpMouseCursorPosition(CGPointMake(screen.x, screenHeight - screen.y));
}

static void checkArea(NSView *view, NSRect rect, const char *name) {
    movePointer(350, 250); // start outside the view
    waitFor(^BOOL { return NO; }, 0.5);
    Recorder *recorder = [[Recorder alloc] init];
    NSTrackingArea *area = [[NSTrackingArea alloc]
            initWithRect: rect
                 options: NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                   owner: recorder
                userInfo: nil];
    [view addTrackingArea: area];
    char message[200];

    movePointer(150, 150); // inside the view, away from its corner
    snprintf(message, sizeof message, "%s: mouseEntered: arrives when the pointer is inside the visible rect", name);
    expect(waitFor(^BOOL { return recorder->entered > 0; }, 3.0), message);

    movePointer(350, 250); // inside the window, outside the view
    snprintf(message, sizeof message, "%s: mouseExited: arrives when the pointer leaves the visible rect", name);
    expect(waitFor(^BOOL { return recorder->exited > 0; }, 3.0), message);

    [view removeTrackingArea: area];
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        screenHeight = [[NSScreen mainScreen] frame].size.height;
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
        NSView *content = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        [content addSubview: view];
        [window setContentView: content];
        [NSApp activateIgnoringOtherApps: YES];
        [window makeKeyAndOrderFront: nil];
        if (!waitFor(^BOOL { return [window isVisible]; }, 5.0)) {
            printf("FAILED\n");
            return 1;
        }
        [window setAcceptsMouseMovedEvents: YES];

        checkArea(view, NSZeroRect, "empty rect");
        checkArea(view, NSMakeRect(0, 0, 10, 10), "small corner rect");
    }
    printf(failures ? "FAILED\n" : "OK\n");
    return failures != 0;
}
