// Copyright (C) 2026 Lubos Dolezel
//
// A titled window whose title bar is transparent and holds nothing to show (title and close,
// miniaturize and zoom buttons hidden) shows no title bar of its own, so the window system must not
// put a frame around it either; it also stays where the application put it. A window that keeps
// its title or a button, or whose title bar is not transparent, stays framed. Windows:
//   hidden-all       transparent title bar, hidden title, hidden buttons      no frame
//   hidden-title     transparent title bar, hidden title, buttons shown        frame
//   transparent      transparent title bar only                                frame
//   opaque-hidden    hidden title and buttons, title bar not transparent      frame
//   late-hidden      transparent title bar and hidden buttons; the title is
//                    hidden after the window is shown                          frame, then none
// The program prints "win <name> <x> <y> <width> <height>" (the frame AppKit reports, Cocoa screen
// coordinates) for each window, then "shown"; after the late change the same lines and "changed";
// then it holds the windows for <seconds> (the first argument). The harnesses
// appkit-window-hidden-title-chrome-x11.sh and -wayland.sh read the window system's view at "shown"
// and "changed".
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

static void spin(NSTimeInterval seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([until timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.02]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event)
            [NSApp sendEvent: event];
    }
}

static void report(NSArray<NSWindow *> *windows, const char *phase) {
    for (NSWindow *w in windows)
        printf("win %s %.0f %.0f %.0f %.0f\n", [w.title UTF8String], w.frame.origin.x, w.frame.origin.y,
               w.frame.size.width, w.frame.size.height);
    printf("%s\n", phase);
    fflush(stdout);
}

static NSWindow *make(NSString *title, CGFloat x, BOOL transparent, BOOL hideTitle, BOOL hideButtons) {
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable |
                       NSWindowStyleMaskResizable;
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(x, 500, 300, 200)
                                              styleMask: style
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    w.title = title;
    w.titlebarAppearsTransparent = transparent;
    if (hideTitle)
        w.titleVisibility = NSWindowTitleHidden;
    if (hideButtons)
        for (NSWindowButton b = NSWindowCloseButton; b <= NSWindowZoomButton; b++)
            [[w standardWindowButton: b] setHidden: YES];
    [w setReleasedWhenClosed: NO];
    [w orderFront: nil];
    return w;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSArray<NSWindow *> *windows = @[
            make(@"hidden-all", 60, YES, YES, YES),
            make(@"hidden-title", 420, YES, YES, NO),
            make(@"transparent", 780, YES, NO, NO),
            make(@"opaque-hidden", 1140, NO, YES, YES),
            make(@"late-hidden", 1500, YES, NO, YES),
        ];
        [NSApp activateIgnoringOtherApps: YES];
        spin(3);
        report(windows, "shown");
        spin(3);
        windows[4].titleVisibility = NSWindowTitleHidden;
        spin(2);
        report(windows, "changed");
        spin(argc > 1 ? atof(argv[1]) : 0);
    }
    return 0;
}
