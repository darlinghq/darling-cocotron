/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSControl's sizeThatFits: (Apple's NSControl reference, macOS 10.10): the
// size that best fits within the given size. A wrapping label given a narrow
// width comes out taller and no wider than that width.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, what) do { if (!(cond)) { printf("FAIL: %s\n", what); failures++; } else printf("PASS: %s\n", what); } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSTextField *label = [NSTextField wrappingLabelWithString:
            @"Some words that will not fit on one line of a narrow label"];

        NSSize wide = [label sizeThatFits: NSMakeSize(10000, CGFLOAT_MAX)];
        NSSize narrow = [label sizeThatFits: NSMakeSize(80, CGFLOAT_MAX)];

        CHECK(wide.width > 80 && wide.height > 0, "a wide size fits the text on one line");
        CHECK(narrow.width <= 80, "the result is no wider than the width given");
        CHECK(narrow.height > wide.height, "a narrow width wraps the text onto more lines");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
