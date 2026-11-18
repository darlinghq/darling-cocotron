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
static int hiddenKeys, visibleKeys;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface CountingWindow : NSWindow {
    int *counter;
}
- (void) setCounter: (int *) value;
@end

@implementation CountingWindow
- (void) setCounter: (int *) value { counter = value; }
- (void) keyDown: (NSEvent *) event {
    (*counter)++;
}
- (BOOL) canBecomeKeyWindow { return YES; }
@end

static NSWindow *makeWindow(NSString *title, CGFloat alpha, int *counter) {
    CountingWindow *window = [[CountingWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
                                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                                 backing: NSBackingStoreBuffered
                                                                   defer: NO];
    [window setCounter: counter];
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
        [visible orderFront: nil];
        NSWindow *hidden = makeWindow(@"tw-hidden", 0.0, &hiddenKeys);
        [hidden makeKeyAndOrderFront: nil];
        spin(2);
        expect([hidden isVisible], "the alpha-0 window is ordered in");
        expect([hidden isKeyWindow], "the alpha-0 window is the key window");
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
