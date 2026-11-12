/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Cancelling a menu's mouse tracking (Escape) returns no item, even though one
// is highlighted. Needs a window server (for example DARLING_APPKIT_BACKEND=x11
// on Xvfb).
#import <AppKit/AppKit.h>
#import "../AppKit/NSMenu.subproj/NSMenuView.h"
#import "../AppKit/NSMenu.subproj/NSMenuWindow.h"
#include <stdio.h>

int main(void) {
    int failures = 0;
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Context"];
        [menu setAutoenablesItems: NO];
        [menu addItemWithTitle: @"Cut" action: @selector(cut:) keyEquivalent: @""];
        NSMenuWindow *popup = [[NSMenuWindow alloc] initWithMenu: menu];
        [popup setReleasedWhenClosed: NO];
        NSMenuView *view = [popup menuView];

        NSEvent *start = [NSEvent mouseEventWithType: NSRightMouseDown
                                            location: NSMakePoint(10, NSHeight([view bounds]) - 10)
                                       modifierFlags: 0
                                           timestamp: 1
                                        windowNumber: [popup windowNumber]
                                             context: nil
                                         eventNumber: 0
                                          clickCount: 1
                                            pressure: 1];
        NSEvent *escape = [NSEvent keyEventWithType: NSKeyDown
                                           location: NSZeroPoint
                                      modifierFlags: 0
                                          timestamp: 2
                                       windowNumber: [popup windowNumber]
                                            context: nil
                                         characters: @"\033"
                        charactersIgnoringModifiers: @"\033"
                                          isARepeat: NO
                                            keyCode: 53];
        [NSApp postEvent: escape atStart: YES];
        if ([view trackForEvent: start] != nil) {
            fprintf(stderr, "FAIL: cancelling the tracking returned the highlighted item\n");
            failures++;
        }
        [menu release];
    }
    printf("context menu cancel: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
