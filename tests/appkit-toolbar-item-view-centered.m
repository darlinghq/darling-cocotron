// Copyright (C) 2026 Lubos Dolezel
//
// Views of toolbar items in an icon-only toolbar are shown whole and centred vertically on a common line,
// whatever their heights. On macOS 10.14.4 (black-box) a regular-size icon-only toolbar with views 23, 30
// and 22 points high shows each view whole, with their middles at most a point apart; the item views
// that hold them are as high as the toolbar. The same checks pass on macOS 10.14.4 and 26.7.3.
//
// Build: clang -framework AppKit appkit-toolbar-item-view-centered.m
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Delegate : NSObject <NSToolbarDelegate>
@end
@implementation Delegate
- (NSArray *) toolbarDefaultItemIdentifiers: (NSToolbar *) toolbar {
    return @[ @"A", @"B", NSToolbarFlexibleSpaceItemIdentifier, @"C" ];
}
- (NSArray *) toolbarAllowedItemIdentifiers: (NSToolbar *) toolbar {
    return [self toolbarDefaultItemIdentifiers: toolbar];
}
- (NSToolbarItem *) toolbar: (NSToolbar *) toolbar itemForItemIdentifier: (NSString *) identifier willBeInsertedIntoToolbar: (BOOL) flag {
    NSToolbarItem *item = [[[NSToolbarItem alloc] initWithItemIdentifier: identifier] autorelease];
    NSView *view;
    // the frames' origins are not where the views end up
    if ([identifier isEqual: @"C"])
        view = [[[NSSearchField alloc] initWithFrame: NSMakeRect(0, 14, 150, 22)] autorelease];
    else
        view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 14, 60, [identifier isEqual: @"A"] ? 23 : 30)] autorelease];
    [item setLabel: identifier];
    [item setView: view];
    return item;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Delegate *delegate = [[Delegate alloc] init];
        NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier: @"centered-toolbar"];
        [toolbar setDisplayMode: NSToolbarDisplayModeIconOnly];
        [toolbar setSizeMode: NSToolbarSizeModeRegular];
        [toolbar setDelegate: delegate];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 600, 200)
                                                       styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setToolbar: toolbar];
        [window orderFront: nil];
        [window display];

        NSRect contentRect = [window contentRectForFrameRect: [window frame]];
        CGFloat contentTop = NSHeight(contentRect);
        CGFloat frameTop = NSHeight([window frame]);
        CGFloat middles[3];
        int n = 0;

        for (NSToolbarItem *item in [toolbar items]) {
            NSView *view = [item view];
            if (view == nil)
                continue;
            NSRect inWindow = [view convertRect: [view bounds] toView: nil];
            NSRect visible = [view visibleRect];

            printf("%s: %.1f x %.1f at y %.1f (content top %.1f), visible %.1f x %.1f\n",
                   [[item itemIdentifier] UTF8String], NSWidth(inWindow), NSHeight(inWindow),
                   NSMinY(inWindow), contentTop, NSWidth(visible), NSHeight(visible));
            // the whole view is shown, above the content view and below the top of the window
            CHECK(NSContainsRect(visible, [view bounds]));
            CHECK(NSMinY(inWindow) >= contentTop);
            CHECK(NSMaxY(inWindow) <= frameTop);
            if (n < 3)
                middles[n++] = NSMidY(inWindow);
        }
        CHECK(n == 3);
        if (n == 3) {
            CHECK(fabs(middles[0] - middles[1]) <= 1.5);
            CHECK(fabs(middles[0] - middles[2]) <= 1.5);
        }
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
