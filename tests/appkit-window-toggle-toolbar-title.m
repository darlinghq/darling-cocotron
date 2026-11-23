// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// NSWindow and a menu item whose action is toggleToolbarShown: (as in View > Hide Toolbar): validation enables it for a
// window with a toolbar, shown or hidden, and disables it for a window without one; neither validating nor toggling
// changes the item's title (an application titles it). Observed on macOS 10.14.4 and 26.7.3, where it passes unchanged.
// Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing: NSBackingStoreBuffered defer: NO];
        window.releasedWhenClosed = NO;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"Toolbar" action: @selector(toggleToolbarShown:) keyEquivalent: @""];

        expect(![window validateMenuItem: item], @"without a toolbar the item is disabled");

        window.toolbar = [[NSToolbar alloc] initWithIdentifier: @"toggle-title"];
        [window makeKeyAndOrderFront: nil];
        BOOL enabled = [window validateMenuItem: item];
        expect(enabled && [item.title isEqual: @"Toolbar"],
               [NSString stringWithFormat: @"a shown toolbar: enabled, the title as it was (%d, %@)", enabled, item.title]);
        window.toolbar.visible = NO;
        enabled = [window validateMenuItem: item];
        expect(enabled && [item.title isEqual: @"Toolbar"],
               [NSString stringWithFormat: @"a hidden toolbar: enabled, the title as it was (%d, %@)", enabled, item.title]);
        [window toggleToolbarShown: item];
        expect([window.toolbar isVisible] && [item.title isEqual: @"Toolbar"],
               [NSString stringWithFormat: @"toggleToolbarShown: shows it again, and leaves the title (%@)", item.title]);

        [window close];
        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
