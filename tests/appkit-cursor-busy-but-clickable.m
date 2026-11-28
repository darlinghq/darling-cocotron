// Copyright (C) 2026 Lubos Dolezel
//
// The private +busyButClickableCursor selector returns the shared wait cursor. Like the other standard cursors
// it preserves object identity across calls and can be selected as the current cursor.
#import <AppKit/AppKit.h>
#import <AppKit/NSCursor+Private.h>
#include <stdio.h>

static int failures;

static void Check(bool condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool {
        NSCursor *cursor = [NSCursor busyButClickableCursor];
        Check(cursor != nil, "no busy-but-clickable cursor");
        Check(cursor == [NSCursor busyButClickableCursor], "the cursor is not shared");
        Check(cursor != [NSCursor arrowCursor], "the wait cursor is the arrow");

        [cursor set];
        Check([NSCursor currentCursor] == cursor, "the cursor cannot be selected");
    }

    if (failures == 0)
        printf("PASS: busy-but-clickable cursor\n");
    return failures ? 1 : 0;
}
