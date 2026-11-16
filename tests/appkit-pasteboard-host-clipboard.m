/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Helper of appkit-pasteboard-host-clipboard.sh: a process of the window system with a general pasteboard.
 *   copy TEXT SECONDS   puts TEXT on the general pasteboard and keeps running, serving it, for SECONDS
 *   hold SECONDS        only runs for SECONDS (a window system process that makes the host clipboard visible)
 *   paste SECONDS TEXT  runs until the general pasteboard holds TEXT (exit 0) or SECONDS have passed (exit 1)
 *   count               prints the change count of the general pasteboard
 * With HOSTCLIP_WINDOW set in the environment the process also shows a window: a Wayland compositor only
 * tells a client about the clipboard (and takes it from one) while a window of the client has the keyboard focus.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void run(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([end timeIntervalSinceNow] > 0 && !(done != nil && done())) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                                     beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
        }
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2)
            return 2;
        // The application brings up the window system connection, which connects the general pasteboard
        // with the host clipboard.
        [NSApplication sharedApplication];
        if (getenv("HOSTCLIP_WINDOW") != NULL) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                           styleMask: NSWindowStyleMaskTitled
                                                             backing: NSBackingStoreBuffered
                                                               defer: NO];
            [window makeKeyAndOrderFront: nil];
        }
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        if (strcmp(argv[1], "copy") == 0 && argc == 4) {
            [pasteboard declareTypes: @[ NSPasteboardTypeString ] owner: nil];
            [pasteboard setString: [NSString stringWithUTF8String: argv[2]] forType: NSPasteboardTypeString];
            run(atof(argv[3]), nil);
            return 0;
        }
        if (strcmp(argv[1], "hold") == 0 && argc == 3) {
            run(atof(argv[2]), nil);
            return 0;
        }
        if (strcmp(argv[1], "paste") == 0 && argc == 4) {
            NSString *expected = [NSString stringWithUTF8String: argv[3]];
            __block NSString *got = nil;
            run(atof(argv[2]), ^BOOL {
              got = [pasteboard stringForType: NSPasteboardTypeString];
              return [got isEqualToString: expected];
            });
            printf("%s\n", got != nil ? [got UTF8String] : "(nothing)");
            return [got isEqualToString: expected] ? 0 : 1;
        }
        if (strcmp(argv[1], "count") == 0) {
            printf("%ld\n", (long) [pasteboard changeCount]);
            return 0;
        }
    }
    return 2;
}
