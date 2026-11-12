/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSComboBox uses NSComboBoxCell and the cell starts with its documented
// defaults; items can be added and read back. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        expect([NSComboBox cellClass] == [NSComboBoxCell class], "NSComboBox's cell class is NSComboBoxCell");
        NSComboBox *box = [[NSComboBox alloc] initWithFrame: NSMakeRect(0, 0, 120, 24)];
        expect([[box cell] isKindOfClass: [NSComboBoxCell class]], "a combo box has a combo box cell");
        expect([box numberOfVisibleItems] == 5, "five visible items by default");
        [box addItemWithObjectValue: @"one"];
        [box addItemsWithObjectValues: @[ @"two", @"three" ]];
        expect([box numberOfItems] == 3, "three items were added");
        expect([[box itemObjectValueAtIndex: 1] isEqual: @"two"], "an item can be read back");
        [box selectItemAtIndex: 2];
        expect([box indexOfSelectedItem] == 2, "selecting an item by index");
        [box removeAllItems];
        expect([box numberOfItems] == 0, "removeAllItems empties the box");
        NSComboBoxCell *cell = [[NSComboBoxCell alloc] initTextCell: @"x"];
        [cell addItemWithObjectValue: @"a"];
        expect([cell numberOfItems] == 1, "a cell made with initTextCell: accepts items");
        [cell release];
        [box release];
    }
    printf("combo box cell: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
