/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Windows of the kinds applications use next to a main window, for the window
// manager hints checkers (-x11.sh, -wayland.sh): what kind of window each one is
// to the window manager, where it was put, and whether it takes the focus.
//
//   wmh-main        500x350, titled, resizable; can become key and main (an application window,
//                   which has a task-bar presence)
//   wmh-chrome      210x140, borderless, resizable, miniaturizable, can become key and main (a window
//                   that draws its own chrome); an application window like the main one (the Dock lists a
//                   regular application's windows whether or not they have a title bar)
//   wmh-popup       160x120, borderless, normal level, can become key but not main, child of the main
//                   window; hidden and shown repeatedly at new positions (a pop-up window created
//                   hidden and reused)
//   wmh-popup-level 200x150, the same at the pop-up menu level, without a parent
//   wmh-loose       170x110, borderless, normal level, can become key but not main, no parent; a window of
//                   a regular application like any other, so an application window
//   wmh-child       150x100, borderless child of the main window with the default key/main answers
//   wmh-panel       180x130, NSPanel with the utility style
//   wmh-tooltip     120x40, borderless at the pop-up menu level, ignores the mouse, cannot become
//                   key, child of the main window
//
// The pop-up and tool tip style masks are Miniaturizable alone (no Titled, no Resizable), as
// toolkits that always allow miniaturizing create their pop-up windows. The chrome window is built
// for an SDK of 10.7 or later, for which a Resizable window without Titled has no title bar.
//
// Every window is positioned with -setFrameOrigin: or -setFrame:display: before it is
// ordered front. Prints "SCREEN <w> <h>", then for each window "WIN <name> <x> <y> <w>
// <h> <key> <main>" (frame in Cocoa coordinates, canBecomeKey, canBecomeMain), then READY.
// The argument is how long to keep running afterwards, in seconds.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface WMHWindow : NSWindow {
@public
    BOOL wmhKey, wmhMain;
}
@end
@implementation WMHWindow
- (BOOL) canBecomeKeyWindow { return wmhKey; }
- (BOOL) canBecomeMainWindow { return wmhMain; }
@end

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static WMHWindow *make(NSString *title, NSRect frame, NSUInteger mask, int level, BOOL key, BOOL main) {
    WMHWindow *w = [[WMHWindow alloc] initWithContentRect: frame styleMask: mask backing: NSBackingStoreBuffered defer: NO];
    w->wmhKey = key;
    w->wmhMain = main;
    [w setTitle: title];
    [w setReleasedWhenClosed: NO];
    [w setLevel: level];
    return w;
}

static void report(NSWindow *w, NSString *name) {
    NSRect f = [w frame];
    printf("WIN %s %g %g %g %g %d %d\n", [name UTF8String], f.origin.x, f.origin.y, f.size.width, f.size.height,
           [w canBecomeKeyWindow], [w canBecomeMainWindow]);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        double seconds = argc > 1 ? atof(argv[1]) : 0;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        CGFloat screenH = [[NSScreen mainScreen] frame].size.height;
        printf("SCREEN %g %g\n", [[NSScreen mainScreen] frame].size.width, screenH);

        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskClosable;
        WMHWindow *main = make(@"wmh-main", NSMakeRect(100, 500, 500, 350), titled, NSNormalWindowLevel, YES, YES);
        [main setFrameOrigin: NSMakePoint(100, 500)];
        [main makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        spin(1);

        // Each window has a size of its own, so that a protocol trace identifies it.
        // Created hidden and attached to the parent, the way a reused pop-up is.
        NSUInteger popupMask = NSWindowStyleMaskMiniaturizable;
        WMHWindow *popup = make(@"wmh-popup", NSMakeRect(0, 0, 160, 120), popupMask, NSNormalWindowLevel, YES, NO);
        [main addChildWindow: popup ordered: NSWindowAbove];
        [popup orderOut: nil];
        WMHWindow *level = make(@"wmh-popup-level", NSMakeRect(0, 0, 200, 150), popupMask, NSPopUpMenuWindowLevel, YES, NO);
        WMHWindow *loose = make(@"wmh-loose", NSMakeRect(0, 0, 170, 110), popupMask, NSNormalWindowLevel, YES, NO);
        WMHWindow *chrome = make(@"wmh-chrome", NSMakeRect(0, 0, 210, 140), NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable, NSNormalWindowLevel, YES, YES);
        WMHWindow *child = make(@"wmh-child", NSMakeRect(0, 0, 150, 100), NSWindowStyleMaskBorderless, NSNormalWindowLevel, NO, NO);
        NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 180, 130)
                                                    styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskClosable
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO];
        [panel setTitle: @"wmh-panel"];
        [panel setReleasedWhenClosed: NO];
        WMHWindow *tooltip = make(@"wmh-tooltip", NSMakeRect(0, 0, 120, 40), popupMask, NSPopUpMenuWindowLevel, NO, NO);
        [tooltip setIgnoresMouseEvents: YES];

        // Show and hide the pop-up repeatedly, at a new position each time, the position
        // set before the window is ordered in.
        NSPoint spots[3] = {{700, 700}, {760, 640}, {820, 560}};
        for (int i = 0; i < 3; i++) {
            [popup setFrameOrigin: spots[i]];
            [main addChildWindow: popup ordered: NSWindowAbove];
            [popup orderFront: nil];
            [popup makeKeyWindow];
            spin(0.4);
            if (i < 2) {
                [popup orderOut: nil];
                spin(0.3);
            }
        }
        [level setFrame: NSMakeRect(1100, 700, 200, 150) display: YES];
        [level orderFront: nil];
        [level setFrame: NSMakeRect(1100, 640, 200, 150) display: YES];
        [loose setFrameOrigin: NSMakePoint(1400, 700)];
        [loose orderFront: nil];
        [chrome setFrame: NSMakeRect(1400, 400, 210, 140) display: YES];
        [chrome orderFront: nil];
        // The pop-up was made key when it was shown; the application's own window takes the key
        // status back, as it does when a pop-up is dismissed.
        [main makeKeyAndOrderFront: nil];
        spin(0.5);
        [child setFrameOrigin: NSMakePoint(700, 300)];
        [main addChildWindow: child ordered: NSWindowAbove];
        [child orderFront: nil];
        [panel setFrameOrigin: NSMakePoint(1000, 300)];
        [panel orderFront: nil];
        [tooltip setFrameOrigin: NSMakePoint(300, 200)];
        [main addChildWindow: tooltip ordered: NSWindowAbove];
        [tooltip orderFront: nil];
        spin(1.5);

        report(main, @"wmh-main");
        report(popup, @"wmh-popup");
        report(level, @"wmh-popup-level");
        report(loose, @"wmh-loose");
        report(chrome, @"wmh-chrome");
        report(child, @"wmh-child");
        report(panel, @"wmh-panel");
        report(tooltip, @"wmh-tooltip");
        printf("KEY %s\n", [[[NSApp keyWindow] title] UTF8String] ?: "-");
        printf("READY\n");
        fflush(stdout);
        spin(seconds);
    }
    return 0;
}
