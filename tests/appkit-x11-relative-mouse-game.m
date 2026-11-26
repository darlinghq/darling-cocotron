// CFLAGS: -framework Foundation -framework AppKit -framework CoreGraphics
// Copyright (C) 2026 Lubos Dolezel
//
// What a game does with the mouse: hide the cursor (NSCursor hide, or hidden until the mouse moves), disconnect the
// mouse from the cursor with CGAssociateMouseAndMouseCursorPosition(false) and read the motion from the mouse
// moved events (deltaX, deltaY) and CGGetLastMouseDelta(), while +[NSEvent mouseLocation] stays where the cursor
// froze; then give the cursor back. On X11 the pointer state is CoreGraphics', and the NSEvents come from its
// CGEvents. Driven by appkit-x11-relative-mouse-game.sh (XTest), which gives the commands as keys in the window
// "relative-mouse-game":
//   h NSCursor hide, s NSCursor unhide (CGCursorIsVisible follows the hide count)
//   u hidden until the mouse moves (the cursor is hidden, and the first motion shows it)
//   t check that the motion showed it
//   d disassociate and hide, e reset the counters, c check: the mouse moved events add up to (25, 5), the frozen
//     cursor did not move, CGGetLastMouseDelta() is (25, 5)
//   a associate and unhide again, q quit
// Usage: appkit-x11-relative-mouse-game (no arguments)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <math.h>

// Deprecated, so not in the SDK's headers
extern boolean_t CGCursorIsVisible(void);

static int failures;
static void expect(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 400, 300)
                                                       styleMask: NSTitledWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"relative-mouse-game"];
        [window setAcceptsMouseMovedEvents: YES];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        expect(CGCursorIsVisible(), "the cursor starts visible");

        printf("READY\n");
        fflush(stdout);

        NSPoint frozen = NSZeroPoint;
        double sumX = 0, sumY = 0;
        int moves = 0, movedOff = 0;
        BOOL quit = NO;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!quit && [deadline timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]
                                                   inMode: NSDefaultRunLoopMode dequeue: YES];
            if (event == nil)
                continue;
            if ([event type] == NSMouseMoved) {
                moves++;
                sumX += [event deltaX];
                sumY += [event deltaY];
                NSPoint now = [NSEvent mouseLocation];
                if (fabs(now.x - frozen.x) > 1 || fabs(now.y - frozen.y) > 1)
                    movedOff++;
            } else if ([event type] == NSKeyUp) {
                switch ([[event characters] length] ? [[event characters] characterAtIndex: 0] : 0) {
                case 'h':
                    [NSCursor hide];
                    expect(!CGCursorIsVisible(), "+[NSCursor hide] hides the cursor in CoreGraphics' count");
                    break;
                case 's':
                    [NSCursor unhide];
                    expect(CGCursorIsVisible(), "+[NSCursor unhide] shows it again");
                    break;
                case 'u':
                    [NSCursor setHiddenUntilMouseMoves: YES];
                    expect(!CGCursorIsVisible(), "hidden until the mouse moves: the cursor is hidden");
                    break;
                case 't':
                    expect(CGCursorIsVisible(), "the motion of the mouse showed the cursor");
                    break;
                case 'd':
                    frozen = [NSEvent mouseLocation];
                    CGAssociateMouseAndMouseCursorPosition(false);
                    [NSCursor hide];
                    break;
                case 'e': {
                    int32_t dx, dy;
                    CGGetLastMouseDelta(&dx, &dy);
                    sumX = sumY = 0;
                    moves = movedOff = 0;
                    break;
                }
                case 'c': {
                    int32_t dx = 0, dy = 0;
                    CGGetLastMouseDelta(&dx, &dy);
                    printf("INFO %d mouse moved events, deltas %.1f,%.1f, CGGetLastMouseDelta %d,%d, moved off %d\n", moves, sumX, sumY, dx, dy, movedOff);
                    expect(moves >= 3 && fabs(sumX - 25) < 0.01 && fabs(sumY - 5) < 0.01, "the mouse moved events carry the deltas of the motion (25, 5)");
                    expect(movedOff == 0, "+[NSEvent mouseLocation] stays at the frozen cursor");
                    expect(dx == 25 && dy == 5, "CGGetLastMouseDelta() reports the motion (25, 5)");
                    break;
                }
                case 'a':
                    CGAssociateMouseAndMouseCursorPosition(true);
                    [NSCursor unhide];
                    expect(CGCursorIsVisible(), "associated again and unhidden: the cursor is visible");
                    break;
                case 'q':
                    quit = YES;
                    break;
                }
                fflush(stdout);
            }
            [NSApp sendEvent: event];
        }
        printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
    }
    return failures != 0;
}
