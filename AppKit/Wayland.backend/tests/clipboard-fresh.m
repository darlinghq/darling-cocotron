/*
 Copyright (C) 2026 Darling Developers

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Guest fixture for clipboard-keyboard-removed.sh: every "c" key down puts a new string,
// "fresh-<n>" for the n-th key, on the general pasteboard, as a Copy command does; "q" quits.
// Keys are taken in -sendEvent:, so the copy happens while the key event is being handled.
@interface FreshCopyApplication : NSApplication {
    int _copies;
}
@end
@implementation FreshCopyApplication
- (void)sendEvent:(NSEvent *)event {
    if ([event type] != NSKeyDown) { [super sendEvent:event]; return; }
    NSString *key = [event charactersIgnoringModifiers];
    if ([key isEqual:@"c"]) {
        NSString *text = [NSString stringWithFormat:@"fresh-%d", ++_copies];
        NSPasteboard *board = [NSPasteboard generalPasteboard];
        [board declareTypes:@[NSPasteboardTypeString] owner:nil];
        [board setString:text forType:NSPasteboardTypeString];
        printf("copied %s\n", [text UTF8String]);
    } else if ([key isEqual:@"q"]) {
        printf("exiting\n");
        exit(0);
    }
    fflush(stdout);
}
@end

int main(void) {
    @autoreleasepool {
        [FreshCopyApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 200)
            styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"Wayland clipboard freshness"];
        [window makeKeyAndOrderFront:nil];
        printf("clipboard ready\n");
        fflush(stdout);
        [NSApp run];
    }
    return 0;
}
