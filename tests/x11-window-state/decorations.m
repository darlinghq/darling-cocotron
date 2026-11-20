/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// X11 backend: the window manager frames a window that has a title bar: one
// whose style mask has NSWindowStyleMaskTitled, or Resizable in a program
// built against an SDK older than 10.7 (as on Mac OS X 10.14.4 and macOS
// 26.7.3); other masks ask for no frame, at creation and after -setStyleMask:.
// A titled window keeps its frame when its title bar is transparent and its
// title hidden. The program prints "old-sdk 1" when it was built against an
// SDK older than 10.7, else "old-sdk 0".
// Run by x11-window-state/run.sh with DARLING_APPKIT_BACKEND=x11, which reads
// _MOTIF_WM_HINTS from the X server with the host helper.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdint.h>

extern uint32_t dyld_get_program_sdk_version(void);

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

        printf("old-sdk %d\n", dyld_get_program_sdk_version() < 0x000a0700);
        printf("READY\n");
        fflush(stdout);
        spin(12);
        printf("DONE\n");
    }
    return 0;
}
