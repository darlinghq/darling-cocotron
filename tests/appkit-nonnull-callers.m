/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Menu items created without a key equivalent report an empty key equivalent
// (never nil), a separator item is recognised as such, and a pop-up button's
// items follow the same rule.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSMenuItem *separator = [NSMenuItem separatorItem];
        CHECK([separator isSeparatorItem], "separatorItem is a separator");
        CHECK([[separator keyEquivalent] isEqualToString: @""], "separator key equivalent is empty, not nil");
        CHECK([separator action] == NULL, "separator has no action");

        NSMenuItem *plain = [[NSMenuItem alloc] initWithTitle: @"Plain" action: NULL keyEquivalent: @""];
        CHECK(![plain isSeparatorItem], "a titled item is not a separator");

        NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 24) pullsDown: NO];
        [popup addItemWithTitle: @"First"];
        [popup insertItemWithTitle: @"Zero" atIndex: 0];
        CHECK([popup numberOfItems] == 2, "popup has two items");
        for (NSMenuItem *item in [popup itemArray])
            CHECK([[item keyEquivalent] isEqualToString: @""], "popup item key equivalent is empty, not nil");
        CHECK([[[popup itemAtIndex: 0] title] isEqualToString: @"Zero"], "insertItemWithTitle:atIndex: order");
    }
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
