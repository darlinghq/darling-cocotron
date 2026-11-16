// Copyright (C) 2026 Lubos Dolezel
// A frame change marks the view and its superview as needing display, so that a view that layout
// resizes is drawn again at its new size (QUIRK, observed on Mac OS X 10.14.4: see NSView.m); a call
// that leaves the frame as it is marks neither.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 200)
                                                        styleMask: NSWindowStyleMaskTitled
                                                          backing: NSBackingStoreBuffered
                                                            defer: NO] autorelease];
        NSView *superview = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)] autorelease];
        [window setContentView: superview];
        NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(10, 10, 100, 40)] autorelease];
        [superview addSubview: view];
        [window orderFront: nil];
        [window displayIfNeeded];
        CHECK(![view needsDisplay] && ![superview needsDisplay]);

        [view setFrame: NSMakeRect(10, 10, 200, 40)];
        CHECK([view needsDisplay] && [superview needsDisplay]);
        [window displayIfNeeded];
        CHECK(![view needsDisplay] && ![superview needsDisplay]);

        [view setFrame: NSMakeRect(20, 20, 200, 40)];
        CHECK([view needsDisplay] && [superview needsDisplay]);
        [window displayIfNeeded];

        [view setFrameSize: NSMakeSize(250, 40)];
        CHECK([view needsDisplay] && [superview needsDisplay]);
        [window displayIfNeeded];

        [view setFrameOrigin: NSMakePoint(30, 30)];
        CHECK([view needsDisplay] && [superview needsDisplay]);
        [window displayIfNeeded];

        [view setFrame: NSMakeRect(30, 30, 250, 40)];
        CHECK(![view needsDisplay] && ![superview needsDisplay]);
    }
    if (g_failures == 0)
        printf("PASS\n");
    return g_failures != 0;
}
