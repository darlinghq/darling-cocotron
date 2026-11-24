// Copyright (C) 2026 Lubos Dolezel
//
// -[NSMenu update] and the delegate's -menuNeedsUpdate:. On macOS 26.7.3 and 10.14.4 (black-box observation,
// x86_64 and i386, probe p799) -update validates the items of the menu and of its submenus and never sends
// -menuNeedsUpdate: to a delegate (that message comes when the menu is about to be shown), so a delegate
// that calls -update on its own menu from -menuNeedsUpdate: does not recurse. The delegates here count their
// calls and give up at MAX_DEPTH, so that a framework that does recurse fails the checks instead of
// overflowing the stack. Needs no window server. Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

#define MAX_DEPTH 6

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

@interface Delegate : NSObject <NSMenuDelegate> {
@public
    int calls, depth, maxDepth, validations;
    BOOL updatesItself;
}
@end

@implementation Delegate
- (void) menuNeedsUpdate: (NSMenu *) menu {
    calls++;
    if (depth >= MAX_DEPTH)
        return;
    depth++;
    if (depth > maxDepth)
        maxDepth = depth;
    if (updatesItself)
        [menu update];
    depth--;
}
- (BOOL) validateMenuItem: (NSMenuItem *) item {
    validations++;
    return YES;
}
- (void) act: (id) sender {
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        Delegate *delegate = [[[Delegate alloc] init] autorelease];
        Delegate *subDelegate = [[[Delegate alloc] init] autorelease];
        NSMenu *menu = [[[NSMenu alloc] initWithTitle: @"M"] autorelease];
        NSMenu *submenu = [[[NSMenu alloc] initWithTitle: @"S"] autorelease];
        NSMenuItem *item = [menu addItemWithTitle: @"Item" action: @selector(act:) keyEquivalent: @""];
        NSMenuItem *subItem = [submenu addItemWithTitle: @"Inner" action: @selector(act:) keyEquivalent: @""];
        NSMenuItem *host = [menu addItemWithTitle: @"Sub" action: NULL keyEquivalent: @""];

        [item setTarget: delegate];
        [subItem setTarget: delegate];
        [host setSubmenu: submenu];
        [menu setDelegate: delegate];
        [submenu setDelegate: subDelegate];

        [menu update];
        expect(delegate->calls == 0, "-update does not send -menuNeedsUpdate: to the menu's delegate");
        expect(subDelegate->calls == 0, "-update does not send -menuNeedsUpdate: to a submenu's delegate");
        expect(delegate->validations >= 1, "-update still validates the items of the menu");
        expect([subItem isEnabled], "-update validates the items of the submenu");

        // A delegate that updates its menu whenever it is asked terminates.
        delegate->updatesItself = YES;
        [delegate menuNeedsUpdate: menu];
        expect(delegate->calls == 1 && delegate->maxDepth == 1, "a delegate calling -update from -menuNeedsUpdate: is not re-entered");
    }
    return failures ? 1 : 0;
}
