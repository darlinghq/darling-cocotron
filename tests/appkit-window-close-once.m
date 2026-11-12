/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Closing a window twice posts NSWindowWillCloseNotification once; ordering it
// front again starts a new close cycle. Needs a window server (for example
// DARLING_APPKIT_BACKEND=x11 on Xvfb).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int closes;

@interface CloseCounter : NSObject
- (void) willClose: (NSNotification *) note;
@end

@implementation CloseCounter
- (void) willClose: (NSNotification *) note { closes++; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        CloseCounter *counter = [[CloseCounter alloc] init];
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 200, 120)
                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                            backing: NSBackingStoreBuffered
                              defer: NO];
        [window setReleasedWhenClosed: NO];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(willClose:)
                                                     name: NSWindowWillCloseNotification
                                                   object: window];
        BOOL passed = YES;
        [window makeKeyAndOrderFront: nil];
        [window close];
        passed &= closes == 1;
        [window close];
        passed &= closes == 1;

        [window makeKeyAndOrderFront: nil];
        [window close];
        passed &= closes == 2;

        [[NSNotificationCenter defaultCenter] removeObserver: counter];
        [window release];
        [counter release];
        printf("window close once: %s\n", passed ? "PASS" : "FAIL");
        return passed ? 0 : 1;
    }
}
