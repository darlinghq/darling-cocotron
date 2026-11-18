/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Who becomes the key window. The application has a fully transparent window "kw-a" that is key
// (makeKeyAndOrderFront:); then a visible window "kw-b" is shown in the way the mode names. On
// macOS only makeKeyAndOrderFront:, makeKeyWindow, a modal session and a click make a window key;
// -orderFront: does not, and neither does a window system that moves its focus to the new window.
// argv[1]:
//   orderfront  kw-b orderFront: -> kw-a stays key and gets the typed keys (the host types)
//   makekey     kw-b orderFront:, later makeKeyWindow -> kw-b is key
//   makefront   kw-b makeKeyAndOrderFront: -> kw-b is key
//   modal       kw-b runModalForWindow: -> key during the session, kw-a key again afterwards
//   nokey       a window with canBecomeKeyWindow NO is asked to be key -> kw-a stays key
//   click       kw-b orderFront:, then the host clicks into it -> kw-b is key
// argv[2]: seconds to wait for the host (orderfront, click). Run by run.sh (X11, xdotool) and by
// ../wayland-window-state/key-window.sh (sway). Prints READY when the host may act, then DONE or FAILED.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static int keysA, keysB;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface KWWindow : NSWindow {
@public
    int *counter;
    BOOL canBeKey;
}
@end

@implementation KWWindow
- (void) keyDown: (NSEvent *) event { (*counter)++; }
- (BOOL) canBecomeKeyWindow { return canBeKey; }
@end

static KWWindow *makeWindow(NSString *title, CGFloat alpha, NSRect frame, int *counter, BOOL canBeKey) {
    KWWindow *window = [[KWWindow alloc] initWithContentRect: frame
                                                   styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    window->counter = counter;
    window->canBeKey = canBeKey;
    [window setTitle: title];
    [window setAlphaValue: alpha];
    return window;
}

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static void spinUntilKey(NSWindow *window, NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while (![window isKeyWindow] && [deadline timeIntervalSinceNow] > 0)
        spin(0.1);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        const char *mode = argc > 1 ? argv[1] : "orderfront";
        NSTimeInterval wait = argc > 2 ? atof(argv[2]) : 12;
        BOOL isNoKey = !strcmp(mode, "nokey");

        KWWindow *a = makeWindow(@"kw-a", 0.0, NSMakeRect(100, 100, 300, 200), &keysA, YES);
        [a makeKeyAndOrderFront: nil];
        spin(2);
        expect([a isKeyWindow], "the alpha-0 window is key");
        KWWindow *b = makeWindow(@"kw-b", 1.0, NSMakeRect(500, 300, 300, 200), &keysB, !isNoKey);

        if (!strcmp(mode, "orderfront")) {
            [b orderFront: nil];
            spin(2);
            expect(![b isKeyWindow], "orderFront: did not make the window key");
            expect([a isKeyWindow], "the alpha-0 window stayed key after orderFront:");
            printf("READY\n");
            fflush(stdout);
            spin(wait);
            expect([a isKeyWindow] && ![b isKeyWindow], "the key status did not move while keys were typed");
            expect(keysA > 0, "typed keys reached the key window");
            expect(keysB == 0, "typed keys did not stop at the window that has the window system's focus");
            printf("KEYS a=%d b=%d\n", keysA, keysB);
        } else if (!strcmp(mode, "makekey")) {
            [b orderFront: nil];
            spin(2);
            expect(![b isKeyWindow] && [a isKeyWindow], "orderFront: left kw-a key");
            [b makeKeyWindow];
            spinUntilKey(b, 3);
            expect([b isKeyWindow], "makeKeyWindow made the ordered-in window key");
            expect(![a isKeyWindow], "kw-a is no longer key");
        } else if (!strcmp(mode, "makefront")) {
            [b makeKeyAndOrderFront: nil];
            spinUntilKey(b, 3);
            expect([b isKeyWindow], "makeKeyAndOrderFront: made the window key");
            expect(![a isKeyWindow], "kw-a is no longer key");
        } else if (!strcmp(mode, "modal")) {
            NSTimer *stop = [NSTimer timerWithTimeInterval: 2 repeats: NO block: ^(NSTimer *timer) {
                expect([b isKeyWindow], "the modal window is key during the session");
                [NSApp stopModal];
            }];
            [[NSRunLoop currentRunLoop] addTimer: stop forMode: NSRunLoopCommonModes];
            [NSApp runModalForWindow: b];
            [b orderOut: nil];
            spinUntilKey(a, 3);
            expect([a isKeyWindow], "kw-a is key again after the modal session");
        } else if (isNoKey) {
            [b makeKeyAndOrderFront: nil];
            spin(2);
            expect(![b isKeyWindow], "a window that cannot become key did not");
            expect([a isKeyWindow], "kw-a stayed key");
        } else if (!strcmp(mode, "click")) {
            [b orderFront: nil];
            spin(2);
            expect(![b isKeyWindow] && [a isKeyWindow], "orderFront: left kw-a key");
            printf("READY\n");
            fflush(stdout);
            spinUntilKey(b, wait);
            expect([b isKeyWindow], "a click into the window made it key");
            expect(![a isKeyWindow], "kw-a is no longer key");
        } else {
            fprintf(stderr, "unknown mode %s\n", mode);
            return 2;
        }
        if (strcmp(mode, "orderfront") && strcmp(mode, "click"))
            printf("READY\n");
        printf("KEY a=%d b=%d\n", [a isKeyWindow], [b isKeyWindow]);
        printf(failures ? "FAILED\n" : "DONE\n");
    }
    return failures != 0;
}
