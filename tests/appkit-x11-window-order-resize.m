/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: (1) moving a window posts no NSWindowDidResizeNotification, resizing posts one;
// (2) -[NSApplication orderedWindows] follows the X stacking order; (3) a non-Latin-1 title
// does not raise. Needs an X server with a window manager (Xvfb :99 and xfwm4).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures, resizes;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Counter : NSObject
@end
@implementation Counter
- (void) resized: (NSNotification *) note {
    resizes++;
}
@end

static void spin(void) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.7]];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *a = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 150)
                                                  styleMask: NSWindowStyleMaskBorderless
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        NSWindow *b = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 100, 200, 150)
                                                  styleMask: NSWindowStyleMaskBorderless
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        @try {
            [a setTitle: @"Titel äöü ☃ 中文"];
        } @catch (NSException *e) {
            expect(NO, "a title outside Latin-1 is accepted");
        }

        [a orderFront: nil];
        spin();
        [b orderFront: nil];
        spin();
        NSArray *order = [NSApp orderedWindows];
        expect([order count] >= 2 && [order objectAtIndex: 0] == b && [order objectAtIndex: 1] == a,
               "the window ordered front last comes first");
        [a orderFront: nil];
        spin();
        order = [NSApp orderedWindows];
        expect([order count] >= 2 && [order objectAtIndex: 0] == a, "ordering a window front puts it first");

        Counter *counter = [[Counter alloc] init];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(resized:)
                                                     name: NSWindowDidResizeNotification
                                                   object: a];
        resizes = 0;
        NSRect frame = [a frame];
        [a setFrameOrigin: NSMakePoint(frame.origin.x + 40, frame.origin.y + 20)];
        spin();
        expect(resizes == 0, "moving a window posts no resize notification");
        [a setFrame: NSMakeRect(frame.origin.x + 40, frame.origin.y + 20, 260, 180) display: YES];
        spin();
        expect(resizes >= 1, "resizing a window posts a resize notification");
        [a close];
        [b close];
    }
    if (failures == 0)
        printf("OK\n");
    return failures == 0 ? 0 : 1;
}
