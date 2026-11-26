/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <unistd.h>

@interface NSObject (PingStalledProbe)
+ (id)currentDisplay;
- (void)processPendingEvents;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        id display = [NSClassFromString(@"NSDisplay") currentDisplay];
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect:NSMakeRect(0, 0, 320, 200)
                          styleMask:NSWindowStyleMaskTitled
                            backing:NSBackingStoreBuffered
                              defer:NO];
        [window orderFront:nil];
        [display processPendingEvents];

        printf("STALLING_MAIN_THREAD\n");
        fflush(stdout);
        // Block the main thread without pumping CFRunLoop or WaylandDisplay.
        // The background ping responder must still answer xdg_wm_base.ping.
        sleep(2);
        printf("UNSTALLED\n");
        fflush(stdout);
        [window close];
    }
    return 0;
}
