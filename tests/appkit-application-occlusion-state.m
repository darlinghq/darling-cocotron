/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSApplication occlusionState: NSApplicationOcclusionStateVisible while a window is visible, not
// while there is none, and not while the application is hidden. Prints PASS on success. Needs a window
// system session (X11, Wayland or a logged-in Mac session).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application without windows is not visible");

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 120)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application with only an unshown window is not visible");
        [window orderFront: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) != 0,
               "an application with a visible window is visible");
        [app hide: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "a hidden application is not visible");
        [app unhide: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) != 0,
               "an unhidden application is visible again");
        [window orderOut: nil];
        expect(([app occlusionState] & NSApplicationOcclusionStateVisible) == 0,
               "an application whose only window was ordered out is not visible");
    }
    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
