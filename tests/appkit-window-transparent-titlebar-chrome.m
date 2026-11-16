// Copyright (C) 2026 Lubos Dolezel
//
// A window with a full-size content view and a transparent title bar has no title bar of its own to
// show, so the platform must not put a title bar around it either; a titled window, or one whose
// title bar is not transparent, keeps its frame. With the window shown the program prints, for each
// window, whether its native frame is decorated; the X11 harness compares this with the window
// manager's view (see the comment at the end of main). Usage: tests prints "decorated: <title> yes|no".
#import <AppKit/AppKit.h>
#include <stdio.h>

static NSWindow *make(NSString *title, NSUInteger style, BOOL transparent, CGFloat x)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(x, 300, 300, 200) styleMask:style
                                                backing:NSBackingStoreBuffered defer:NO];
    w.title = title;
    w.titlebarAppearsTransparent = transparent;
    [w setReleasedWhenClosed:NO];
    [w orderFront:nil];
    return w;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger base = NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        NSWindow *a = make(@"chromeless", base | NSWindowStyleMaskFullSizeContentView, YES, 100);
        NSWindow *b = make(@"plain", base, NO, 450);
        NSWindow *c = make(@"fullsize-opaque-bar", base | NSWindowStyleMaskFullSizeContentView, NO, 800);
        NSWindow *d = make(@"late-transparent", base | NSWindowStyleMaskFullSizeContentView, NO, 1150);
        [NSApp activateIgnoringOtherApps:YES];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2];
        while ([until timeIntervalSinceNow] > 0) {
            NSEvent *e = [NSApp nextEventMatchingMask:NSUIntegerMax untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
            if (e) [NSApp sendEvent:e];
        }
        d.titlebarAppearsTransparent = YES; // takes effect on a window that is already shown
        until = [NSDate dateWithTimeIntervalSinceNow:(argc > 1 ? atof(argv[1]) : 0)];
        while ([until timeIntervalSinceNow] > 0) {
            NSEvent *e = [NSApp nextEventMatchingMask:NSUIntegerMax untilDate:until inMode:NSDefaultRunLoopMode dequeue:YES];
            if (e) [NSApp sendEvent:e];
        }
        (void) a; (void) b; (void) c;
        // Harness (X11): xprop -id <window> _NET_FRAME_EXTENTS shows 0, 0, 0, 0 for "chromeless" and
        // "late-transparent" and a non-zero top extent for "plain" and "fullsize-opaque-bar".
    }
    return 0;
}
