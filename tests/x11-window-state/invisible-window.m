/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: a window with alpha 0 is invisible, as on macOS, also when no compositing manager is
// running to apply the opacity (documented NSWindow alphaValue): the window manager's frame is gone
// and nothing of the window is drawn, while the window stays ordered in, keeps the keyboard focus and
// stays the key window. Raising the alpha above 0 brings the frame back; partial alpha is left to a
// compositor. Run by x11-window-state/run.sh invisible (DARLING_APPKIT_BACKEND=x11 on Xvfb with a
// window manager but no compositor), which reads the state of each window from the X server with the
// host helper while this program idles.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
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

static int column;

static NSWindow *makeWindow(NSString *title, NSUInteger mask, CGFloat alpha) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(40 + 230 * (column % 5), 100 + 180 * (column / 5), 200, 120)
                                                   styleMask: mask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    column++;
    [window setTitle: title];
    [window setAlphaValue: alpha];
    return window;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;

        NSWindow *plain = makeWindow(@"inv-alpha1-titled", titled, 1.0);
        [plain orderFront: nil];
        NSWindow *borderless = makeWindow(@"inv-alpha0-borderless", NSWindowStyleMaskBorderless, 0.0);
        [borderless orderFront: nil];
        NSWindow *partial = makeWindow(@"inv-partial-titled", titled, 0.5);
        [partial orderFront: nil];
        NSWindow *restored = makeWindow(@"inv-restored-titled", titled, 1.0);
        [restored orderFront: nil];
        // the key window: titled, alpha 0, ordered in last
        NSWindow *invisible = makeWindow(@"inv-alpha0-titled", titled, 0.0);
        [invisible makeKeyAndOrderFront: nil];
        spin(1);

        // alpha 0, then back to 1: frame and contents return
        [restored setAlphaValue: 0.0];
        spin(0.5);
        [restored setAlphaValue: 1.0];
        spin(0.5);

        expect([invisible alphaValue] == 0.0, "alpha 0 is kept");
        expect([invisible isVisible], "the invisible window is still ordered in");
        expect([invisible isKeyWindow], "the invisible window is the key window");
        expect([invisible canBecomeKeyWindow], "the invisible window can be key");
        expect([restored alphaValue] == 1.0, "alpha 1 is kept");

        printf("READY\n");
        fflush(stdout);
        spin(12);
        expect([invisible isKeyWindow], "the invisible window is still the key window");
        printf(failures == 0 ? "DONE\n" : "FAILED\n");
    }
    return failures != 0;
}
