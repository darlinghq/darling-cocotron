/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSWindowWillOrderOnScreenNotification and NSWindowWillOrderOffScreenNotification,
 * which AppKit exports without declaring them in the SDK, as observed on
 * macOS 26.7.3 and Mac OS X 10.14.4:
 *  - their names, and that of NSTextCheckingInsertionPointKey, exported the
 *    same way;
 *  - ordering a hidden window in (orderFront:, makeKeyAndOrderFront:,
 *    setIsVisible: YES) posts the first while the window is still hidden,
 *    and ordering a visible window out (orderOut:, orderWindow:NSWindowOut,
 *    close) posts the second while it is still visible, with the window as
 *    the object and no user info;
 *  - ordering a window where it already is posts neither.
 * Needs a window server.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

APPKIT_EXTERN NSNotificationName const NSWindowWillOrderOnScreenNotification;
APPKIT_EXTERN NSNotificationName const NSWindowWillOrderOffScreenNotification;
APPKIT_EXTERN NSString *const NSTextCheckingInsertionPointKey;

static int failures;

static void expect(BOOL ok, const char *what)
{
    if (!ok) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSMutableString *posted;

// What one step posts, as "on" and "off" with the window's visibility then,
// for example "on:hidden".
static NSString *step(void (^action)(void))
{
    [posted setString: @""];
    action();
    return [[posted copy] autorelease];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        expect([NSWindowWillOrderOnScreenNotification isEqualToString: @"_NSWindowWillBecomeVisible"],
               "the name of the order-on notification");
        expect([NSWindowWillOrderOffScreenNotification isEqualToString: @"NSWindowWillOrderOffScreenNotification"],
               "the name of the order-off notification");
        expect([NSTextCheckingInsertionPointKey isEqualToString: @"InsertionPoint"],
               "the name of the insertion point key");

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 100, 100)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setReleasedWhenClosed: NO];
        posted = [[NSMutableString alloc] init];
        for (NSString *name in @[ NSWindowWillOrderOnScreenNotification, NSWindowWillOrderOffScreenNotification ]) {
            BOOL on = name == NSWindowWillOrderOnScreenNotification;
            [[NSNotificationCenter defaultCenter] addObserverForName: name object: nil queue: nil
                                                           usingBlock: ^(NSNotification *note) {
                expect(note.object == window, "the window is the object");
                expect(note.userInfo == nil, "there is no user info");
                [posted appendFormat: @"%s:%s ", on ? "on" : "off", window.isVisible ? "visible" : "hidden"];
            }];
        }

        expect([step(^{ [window orderFront: nil]; }) isEqualToString: @"on:hidden "],
               "orderFront: on a hidden window announces it while it is hidden");
        expect([step(^{ [window orderFront: nil]; }) isEqualToString: @""],
               "orderFront: on a visible window announces nothing");
        expect([step(^{ [window orderOut: nil]; }) isEqualToString: @"off:visible "],
               "orderOut: on a visible window announces it while it is visible");
        expect([step(^{ [window orderOut: nil]; }) isEqualToString: @""],
               "orderOut: on a hidden window announces nothing");
        expect([step(^{ [window makeKeyAndOrderFront: nil]; }) isEqualToString: @"on:hidden "],
               "makeKeyAndOrderFront: announces the window");
        expect([step(^{ [window orderWindow: NSWindowOut relativeTo: 0]; }) isEqualToString: @"off:visible "],
               "orderWindow:NSWindowOut announces the window");
        expect([step(^{ [window setIsVisible: YES]; }) isEqualToString: @"on:hidden "],
               "setIsVisible: YES announces the window");
        expect([step(^{ [window close]; }) isEqualToString: @"off:visible "],
               "close announces the window");
        [window release];
    }

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
