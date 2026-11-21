/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSWindow tabGroup] (macOS 10.13). A window that takes part in tabbing has
 * a tab group naming its tabbing identifier and holding the window; a window
 * on its own has no tab bar shown and is its group's selected window.
 *
 * Which windows have a group is not documented. The "quirk" cases pin what
 * macOS 10.14.4 and 26.7.3 both do (black-box observation): a window has a
 * group once a tabbing identifier is set on it or it prefers tabs, and not
 * when tabbing is disallowed. The group keeps the identifier it was made
 * with. (A borderless window has a group on 10.14.4 and none on 26.7.3, so
 * that case is not tested.) The program builds and runs on macOS too.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static NSWindow *makeWindow(NSUInteger style)
{
    return [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 200)
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;

        NSWindow *plain = makeWindow(titled);
        if (![plain respondsToSelector:@selector(tabGroup)]) {
            expect(NO, "NSWindow responds to -tabGroup");
            printf("FAIL\n");
            return 1;
        }
        expect(NSClassFromString(@"NSWindowTabGroup") != Nil, "the NSWindowTabGroup class exists");

        expect([plain tabGroup] == nil, "quirk, no group: a new window");
        [plain orderFront:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        expect([plain tabGroup] == nil, "quirk, no group: a shown window without an identifier of its own");
        [plain orderOut:nil];

        NSWindow *named = makeWindow(titled);
        [named setTabbingIdentifier:@"Documents"];
        NSWindowTabGroup *group = [named tabGroup];
        expect(group != nil, "quirk, group: a window with a tabbing identifier set");
        expect([group isKindOfClass:NSClassFromString(@"NSWindowTabGroup")], "the group is an NSWindowTabGroup");
        expect([[group identifier] isEqualToString:@"Documents"], "the group is named by the window's tabbing identifier");
        expect([[group windows] isEqualToArray:@[ named ]], "the group holds the window");
        expect([group selectedWindow] == named, "the window is the group's selected window");
        expect(![group isTabBarVisible], "a group of one window shows no tab bar");
        expect(![group isOverviewVisible], "the tab overview is not shown");
        expect([named tabGroup] == group, "the window keeps its group");
        expect([named tabbedWindows] == nil, "a window alone has no tabbed windows");
        [named setTabbingIdentifier:@"Other"];
        expect([[[named tabGroup] identifier] isEqualToString:@"Documents"],
               "quirk, group: the group keeps the identifier it was made with");

        NSWindow *cleared = makeWindow(titled);
        [cleared setTabbingIdentifier:@"Documents"];
        [cleared setTabbingIdentifier:nil];
        expect([cleared tabGroup] == nil, "quirk, no group: the tabbing identifier set back to nil");

        NSWindow *disallowed = makeWindow(titled);
        [disallowed setTabbingMode:NSWindowTabbingModeDisallowed];
        [disallowed setTabbingIdentifier:@"Documents"];
        expect([disallowed tabGroup] == nil, "quirk, no group: tabbing disallowed");

        NSWindow *preferred = makeWindow(titled);
        [preferred setTabbingMode:NSWindowTabbingModePreferred];
        NSWindowTabGroup *preferredGroup = [preferred tabGroup];
        expect(preferredGroup != nil, "quirk, group: a window that prefers tabs");
        expect([[preferredGroup identifier] isEqualToString:[preferred tabbingIdentifier]],
               "the group of a window that prefers tabs is named by its default identifier");
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
