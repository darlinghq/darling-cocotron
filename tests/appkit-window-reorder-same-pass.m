/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Ordering a window out and in again within one pass of the run loop changes nothing that anyone can
// see: the window stays on screen, keeps the focus and the application stays active. User interface
// toolkits re-order their windows like that on every pass of a frame loop, with a key window request
// each time. A window system backend that unmaps the window and maps it again for each pass hands the
// window manager a new window every time (a new xdg_toplevel on Wayland, an unmap and map on X11),
// which it may place and focus anew.
//
// The fixture prints markers, for the checkers (appkit-window-reorder-same-pass-wayland.sh and
// -x11.sh) to cut the window system trace into sections:
//   READY       the windows are on screen
//   LOOP-BEGIN  the toolkit windows are re-ordered every 0.1 s
//   LOOP-END    ... and the pass count with the number of times the application resigned active
//   HIDE-BEGIN  one toolkit window is ordered out for good; HIDE-END it must be gone by then
//   SHOW-BEGIN  and ordered in again, SHOW-END
//   DONE
// There are no command line arguments: the application would take them for files to open.
#import <AppKit/AppKit.h>
#include <stdio.h>

static void say(const char *what) {
    printf("%s\n", what);
    fflush(stdout);
}

@interface TKWindow : NSWindow
@end
@implementation TKWindow
- (BOOL) canBecomeKeyWindow {
    return YES;
}
- (BOOL) canBecomeMainWindow {
    return NO;
}
@end

@interface Driver : NSObject <NSApplicationDelegate> {
    NSWindow *mainWindow;
    NSMutableArray *toolkitWindows;
    int passes;
    int resigns;
    int failures;
}
@end

@implementation Driver
- (NSWindow *) makeToolkitWindow: (NSString *) title at: (NSPoint) origin {
    NSWindow *w = [[TKWindow alloc] initWithContentRect: NSMakeRect(origin.x, origin.y, 80, 50)
                                              styleMask: NSWindowStyleMaskBorderless
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    [w setTitle: title];
    [w setReleasedWhenClosed: NO];
    return w;
}

- (void) applicationDidFinishLaunching: (NSNotification *) note {
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(didResign:)
                                                 name: NSApplicationDidResignActiveNotification
                                               object: NSApp];
    mainWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 400, 320, 200)
                                             styleMask: NSWindowStyleMaskTitled
                                               backing: NSBackingStoreBuffered
                                                 defer: NO];
    [mainWindow setTitle: @"reorder-main"];
    [mainWindow setReleasedWhenClosed: NO];
    toolkitWindows = [NSMutableArray new];
    [toolkitWindows addObject: [self makeToolkitWindow: @"reorder-tk1" at: NSMakePoint(600, 400)]];
    [toolkitWindows addObject: [self makeToolkitWindow: @"reorder-tk2" at: NSMakePoint(700, 400)]];
    [mainWindow makeKeyAndOrderFront: nil];
    for (NSWindow *w in toolkitWindows)
        [w orderFront: nil];
    [NSApp activateIgnoringOtherApps: YES];
    [self performSelector: @selector(startLoop) withObject: nil afterDelay: 2.0];
    say("READY");
}

- (void) didResign: (NSNotification *) note {
    resigns++;
}

- (void) startLoop {
    resigns = 0;
    say("LOOP-BEGIN");
    [NSTimer scheduledTimerWithTimeInterval: 0.1 target: self selector: @selector(tick:) userInfo: nil repeats: YES];
}

- (void) tick: (NSTimer *) timer {
    if (passes++ >= 30) {
        [timer invalidate];
        printf("LOOP-END passes=%d resigns=%d\n", passes - 1, resigns);
        fflush(stdout);
        if (resigns != 0) {
            printf("FAIL: the application resigned active %d times while its windows were re-ordered\n", resigns);
            failures++;
        }
        [self performSelector: @selector(hideOne) withObject: nil afterDelay: 1.0];
        return;
    }
    // Out and in again within this pass, with the key window request that follows.
    for (NSWindow *w in toolkitWindows) {
        [w orderOut: nil];
        [w makeKeyAndOrderFront: nil];
    }
}

- (void) hideOne {
    say("HIDE-BEGIN");
    [[toolkitWindows objectAtIndex: 0] orderOut: nil];
    [self performSelector: @selector(hideDone) withObject: nil afterDelay: 1.0];
}

- (void) hideDone {
    if ([[toolkitWindows objectAtIndex: 0] isVisible]) {
        say("FAIL: the window ordered out is still visible");
        failures++;
    }
    say("HIDE-END");
    say("SHOW-BEGIN");
    [[toolkitWindows objectAtIndex: 0] orderFront: nil];
    [self performSelector: @selector(showDone) withObject: nil afterDelay: 1.0];
}

- (void) showDone {
    if (![[toolkitWindows objectAtIndex: 0] isVisible]) {
        say("FAIL: the window ordered in again is not visible");
        failures++;
    }
    say("SHOW-END");
    say("DONE");
    printf("%s\n", failures ? "FAIL" : "PASS");
    fflush(stdout);
    _exit(failures ? 1 : 0);
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        [NSApp setDelegate: [Driver new]];
        [NSApp run];
    }
    return 0;
}
