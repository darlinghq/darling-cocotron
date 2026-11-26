/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSTextList's startingItemNumber (documented in Apple's NSTextList
// reference, macOS 10.6): a list starts at item 1 unless told otherwise, and
// the number it is given is kept, per list.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

int main(void) {
    @autoreleasepool {
        NSTextList *list = [[NSTextList alloc] initWithMarkerFormat: NSTextListMarkerDecimal options: 0];
        NSTextList *other = [[NSTextList alloc] initWithMarkerFormat: NSTextListMarkerDisc options: 0];

        CHECK([list startingItemNumber] == 1, "a new list starts at item 1");

        [list setStartingItemNumber: 7];
        CHECK([list startingItemNumber] == 7, "a starting number that is set is kept");
        CHECK([other startingItemNumber] == 1, "setting one list's number leaves other lists alone");

        list.startingItemNumber = -3;
        CHECK(list.startingItemNumber == -3, "the property takes any number");

        [list release];
        [other release];
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
