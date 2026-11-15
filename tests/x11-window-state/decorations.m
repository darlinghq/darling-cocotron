/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: the window manager frames a window whose style mask has a
// title bar (NSWindowStyleMaskTitled) or Resizable; a mask with neither bit
// asks for no frame, at creation and after -setStyleMask:. Resizable without
// Titled gets the full frame because Mac OS X 10.14 gives such a window a
// title bar (macOS 26 does not). A titled window keeps its frame when its
// title bar is transparent and its title hidden.
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(40 + 230 * (column % 5), 100 + 180 * (column / 5), 200, 120)
                                                   styleMask: mask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    column++;
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
        makeWindow(@"deco-untitled-fixed", NSWindowStyleMaskClosable);
        makeWindow(@"deco-borderless-resizable", NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable);

        NSWindow *toUntitled = makeWindow(@"deco-titled-to-untitled", titled);
        NSWindow *toFixed = makeWindow(@"deco-untitled-to-fixed", untitled);
        NSWindow *toTitled = makeWindow(@"deco-untitled-to-titled", untitled);
        NSWindow *transparent = makeWindow(@"deco-titled-transparent", titled);
        spin(1);

        [toUntitled setStyleMask: untitled];
        [toFixed setStyleMask: NSWindowStyleMaskClosable];
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
