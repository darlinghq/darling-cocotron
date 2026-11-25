// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// A window's hidden toolbar takes no room: with the toolbar hidden, the window's frame is the size of the same window
// without a toolbar, and its content keeps its size; shown again, the frame is taller. Observed on macOS 10.14.4 and
// 26.7.3, where it passes unchanged. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

static NSWindow *makeWindow(void)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 640, 400)
                                                   styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing: NSBackingStoreBuffered defer: NO];
    window.releasedWhenClosed = NO;
    return window;
}

static void spin(void)
{
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        NSWindow *plain = makeWindow();
        [plain makeKeyAndOrderFront: nil];
        spin();
        NSSize bare = [plain frame].size;
        [plain close];

        NSWindow *window = makeWindow();
        window.toolbar = [[NSToolbar alloc] initWithIdentifier: @"hidden-frame"];
        [window makeKeyAndOrderFront: nil];
        spin();
        NSSize shown = [window frame].size;
        window.toolbar.visible = NO;
        spin();
        NSSize hidden = [window frame].size;
        expect(NSEqualSizes(hidden, bare), [NSString stringWithFormat: @"hidden: the frame of a window without a toolbar %@ (%@)",
                                            NSStringFromSize(bare), NSStringFromSize(hidden)]);
        expect(NSEqualSizes([window.contentView frame].size, NSMakeSize(640, 400)),
               [NSString stringWithFormat: @"hidden: the content keeps its size (%@)", NSStringFromSize([window.contentView frame].size)]);
        window.toolbar.visible = YES;
        spin();
        expect([window frame].size.height > hidden.height && NSEqualSizes([window frame].size, shown),
               [NSString stringWithFormat: @"shown again: taller, as before (%@, %@)", NSStringFromSize([window frame].size),
                NSStringFromSize(shown)]);
        [window close];

        // Hidden before the window is first shown
        window = makeWindow();
        window.toolbar = [[NSToolbar alloc] initWithIdentifier: @"hidden-early"];
        window.toolbar.visible = NO;
        [window makeKeyAndOrderFront: nil];
        spin();
        expect(NSEqualSizes([window frame].size, bare), [NSString stringWithFormat: @"hidden before shown: %@ (%@)",
                                                         NSStringFromSize(bare), NSStringFromSize([window frame].size)]);
        [window close];
        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
