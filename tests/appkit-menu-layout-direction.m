/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSMenu's userInterfaceLayoutDirection (documented in Apple's NSMenu
// reference, macOS 10.11): unless it is set, a menu lays out its items in the
// application's direction; a direction that is set is kept, per menu.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Test"];
        NSMenu *other = [[NSMenu alloc] initWithTitle: @"Other"];

        CHECK([menu userInterfaceLayoutDirection] == [NSApp userInterfaceLayoutDirection],
              "a new menu follows the application's direction");

        [menu setUserInterfaceLayoutDirection: NSUserInterfaceLayoutDirectionRightToLeft];
        CHECK([menu userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft,
              "a direction that is set is kept");
        CHECK([other userInterfaceLayoutDirection] == [NSApp userInterfaceLayoutDirection],
              "setting one menu's direction leaves other menus alone");

        menu.userInterfaceLayoutDirection = NSUserInterfaceLayoutDirectionLeftToRight;
        CHECK(menu.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionLeftToRight,
              "the property can be set back");

        [menu release];
        [other release];
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
