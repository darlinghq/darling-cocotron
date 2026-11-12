/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// minFullScreenContentSize and maxFullScreenContentSize keep what is set.
// No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(0, 0, 100, 80)
                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                            backing: NSBackingStoreBuffered
                              defer: YES];
        [window setMinFullScreenContentSize: NSMakeSize(320, 200)];
        [window setMaxFullScreenContentSize: NSMakeSize(1600, 900)];
        BOOL passed = NSEqualSizes([window minFullScreenContentSize], NSMakeSize(320, 200)) &&
                NSEqualSizes([window maxFullScreenContentSize], NSMakeSize(1600, 900));
        // The ordinary content size limits are separate.
        passed &= !NSEqualSizes([window contentMinSize], NSMakeSize(320, 200));
        [window release];
        printf("window full screen content sizes: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
