/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Wayland backend: a window with alpha 0 is invisible, as on macOS (documented NSWindow alphaValue),
// while it stays ordered in and stays the key window; keys go to the key window even though the
// compositor gives the keyboard focus to another window of the application (documented: key events
// are delivered to the key window). Run by run.sh (headless sway), which reads the compositor's
// window tree and types keys with wtype while this program idles.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static int hiddenKeys, visibleKeys, dialogKeys;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface CountingWindow : NSWindow {
    int *counter;
@public
    BOOL canBeKey;
}
- (void) setCounter: (int *) value;
@end

@implementation CountingWindow
- (void) setCounter: (int *) value { counter = value; }
- (void) keyDown: (NSEvent *) event {
    (*counter)++;
}
- (BOOL) canBecomeKeyWindow { return canBeKey; }
@end

static NSWindow *makeWindow(NSString *title, CGFloat alpha, int *counter) {
    CountingWindow *window = [[CountingWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                                 backing: NSBackingStoreBuffered
                                                                   defer: NO];
    [window setCounter: counter];
    window->canBeKey = YES;
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

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTimeInterval wait = argc > 1 ? atof(argv[1]) : 12;

        NSWindow *visible = makeWindow(@"tw-visible", 1.0, &visibleKeys);
        // Like the main window of a game: it never becomes key, so the key status stays with the
        // alpha-0 window and returns to it when a dialog goes away.
        ((CountingWindow *) visible)->canBeKey = NO;
        [visible orderFront: nil];
        NSWindow *hidden = makeWindow(@"tw-hidden", 0.0, &hiddenKeys);
        [hidden makeKeyAndOrderFront: nil];
        spin(2);
        expect([hidden isVisible], "the alpha-0 window is ordered in");
        expect([hidden isKeyWindow], "the alpha-0 window is the key window");

        // A modal dialog the application asks to be key takes the key status; when it is ordered out
        // the key status goes back to the alpha-0 window, which is still on screen as far as the
        // window order is concerned.
        NSWindow *dialog = makeWindow(@"tw-dialog", 1.0, &dialogKeys);
        NSTimer *stop = [NSTimer timerWithTimeInterval: 2 repeats: NO block: ^(NSTimer *timer) {
            expect([dialog isKeyWindow], "the modal dialog is the key window");
            [NSApp stopModal];
        }];
        [[NSRunLoop currentRunLoop] addTimer: stop forMode: NSRunLoopCommonModes];
        [NSApp runModalForWindow: dialog];
        [dialog orderOut: nil];
        spin(1);
        expect([hidden isKeyWindow], "the alpha-0 window is key again after the modal dialog");
        printf("READY\n");
        fflush(stdout);

        // The host types keys while the compositor's focus is on tw-visible.
        spin(wait);
        expect([hidden isKeyWindow], "the alpha-0 window is still the key window after the focus moved");
        expect(![visible isKeyWindow], "the visible window did not take the key status");
        expect(hiddenKeys > 0, "typed keys reached the key window");
        expect(visibleKeys == 0, "typed keys did not stop at the window that has the compositor's focus");
        printf("KEYS hidden=%d visible=%d\n", hiddenKeys, visibleKeys);
        printf(failures ? "FAILED\n" : "DONE\n");
    }
    return failures != 0;
}
