/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The window that shows a tool tip must not take part in event delivery: it
// ignores the mouse, so a click on a tool tip reaches the view below it.
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Class cls = NSClassFromString(@"NSToolTipWindow");
        if (cls == Nil || ![cls respondsToSelector: @selector(sharedToolTipWindow)]) {
            printf("SKIP: no shared tool tip window class\n");
            return 0;
        }
        NSWindow *window = [cls performSelector: @selector(sharedToolTipWindow)];
        if (window == nil) {
            printf("FAIL: no shared tool tip window\n");
            return 1;
        }
        if (![window ignoresMouseEvents]) {
            printf("FAIL: the tool tip window accepts mouse events\n");
            return 1;
        }
    }
    printf("OK\n");
    return 0;
}
