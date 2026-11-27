// Copyright (C) 2026 Lubos Dolezel
//
// A window is opaque unless the application says otherwise: -[NSWindow isOpaque] is YES for a freshly
// created window of any style, and -setOpaque: changes it. The window system backends decide from it
// whether the window's pixels carry alpha, so a window that reports NO without having been asked
// is composited against whatever is behind it. Observed through the public API on macOS 26.7.3 (all
// styles below report YES) and macOS 10.14.4.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", what);
    failures += !ok;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger styles[] = { NSWindowStyleMaskTitled | NSWindowStyleMaskClosable, NSWindowStyleMaskBorderless,
            NSWindowStyleMaskTitled | NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable,
            NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow };
        for (int i = 0; i < 4; i++) {
            NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100) styleMask: styles[i]
                                                        backing: NSBackingStoreBuffered defer: YES];
            char msg[96];
            snprintf(msg, sizeof msg, "style %d: a new window is opaque", i);
            expect([w isOpaque], msg);
            [w setOpaque: NO];
            snprintf(msg, sizeof msg, "style %d: setOpaque:NO is reported", i);
            expect(![w isOpaque], msg);
            [w setOpaque: YES];
            snprintf(msg, sizeof msg, "style %d: setOpaque:YES is reported", i);
            expect([w isOpaque], msg);
            [w release];
        }
        NSWindow *screenWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                             styleMask: NSWindowStyleMaskTitled
                                                               backing: NSBackingStoreBuffered defer: YES screen: nil];
        expect([screenWindow isOpaque], "a window made with an explicit screen is opaque");
        NSPanel *panel = [[NSPanel alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
                                                    styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskUtilityWindow
                                                      backing: NSBackingStoreBuffered defer: YES];
        expect([panel isOpaque], "a new panel is opaque");
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
