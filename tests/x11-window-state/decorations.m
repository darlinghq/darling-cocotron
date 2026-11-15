/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: the window manager frames a window that has a title bar, and
// only that. NSWindowStyleMaskTitled is the documented title bar bit; a mask
// without it asks for no frame, at creation and after -setStyleMask:. A
// titled window keeps its frame when its title bar is transparent and its
// title hidden (the title bar region stays, see the macOS note in run.sh).
// Run by x11-window-state/run.sh with DARLING_APPKIT_BACKEND=x11, which reads
// _MOTIF_WM_HINTS from the X server with the host helper.
#import <AppKit/AppKit.h>
#include <stdio.h>

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

static NSWindow *makeWindow(NSString *title, NSUInteger mask) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(40 + 230 * column++, 200, 200, 120)
                                                   styleMask: mask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window setTitle: title];
    [window orderFront: nil];
    return window;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
        NSUInteger untitled = NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;

        makeWindow(@"deco-titled", titled);
        makeWindow(@"deco-borderless", NSWindowStyleMaskBorderless);
        makeWindow(@"deco-untitled", untitled);

        NSWindow *toUntitled = makeWindow(@"deco-titled-to-untitled", titled);
        NSWindow *toTitled = makeWindow(@"deco-untitled-to-titled", untitled);
        NSWindow *transparent = makeWindow(@"deco-titled-transparent", titled);
        spin(1);

        [toUntitled setStyleMask: untitled];
        [toTitled setStyleMask: titled];
        [transparent setTitlebarAppearsTransparent: YES];
        [transparent setTitleVisibility: NSWindowTitleHidden];

        printf("READY\n");
        fflush(stdout);
        spin(12);
        printf("DONE\n");
    }
    return 0;
}
