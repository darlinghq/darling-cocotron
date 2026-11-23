// CFLAGS: -framework Foundation -framework AppKit
// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView columnsInRect: gives the range of the columns a rectangle intersects, also for a rectangle that
// starts in the first column and covers all the others. The program passes unchanged on macOS 26.7.3 and 10.14.4.
//
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what, NSRange got)
{
    printf("%s %s (%lu, %lu)\n", ok ? "PASS" : "FAIL", what, (unsigned long) got.location, (unsigned long) got.length);
    if (!ok)
        failures++;
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 1000, 200)];
    CGFloat widths[] = { 300, 180, 90, 160 };
    for (int i = 0; i < 4; i++) {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]] autorelease];
        [column setWidth: widths[i]];
        [table addTableColumn: column];
    }
    [table setColumnAutoresizingStyle: NSTableViewNoColumnAutoresizing];

    NSRect first = [table rectOfColumn: 0], last = [table rectOfColumn: 3];
    NSRect all = NSMakeRect(NSMinX(first), 0, NSMaxX(last) - NSMinX(first), 10);
    NSRange range = [table columnsInRect: all];
    expect(NSEqualRanges(range, NSMakeRange(0, 4)), "a rectangle over all the columns intersects all four", range);

    range = [table columnsInRect: NSMakeRect(NSMidX(first), 0, NSMaxX(last) - NSMidX(first), 10)];
    expect(NSEqualRanges(range, NSMakeRange(0, 4)), "from the middle of the first column to the end", range);

    NSRect second = [table rectOfColumn: 1], third = [table rectOfColumn: 2];
    range = [table columnsInRect: NSMakeRect(NSMinX(second) + 1, 0, NSMidX(third) - NSMinX(second), 10)];
    expect(NSEqualRanges(range, NSMakeRange(1, 2)), "from the second column into the third", range);

    range = [table columnsInRect: NSMakeRect(NSMidX(last), 0, 1, 10)];
    expect(NSEqualRanges(range, NSMakeRange(3, 1)), "inside the last column", range);

    range = [table columnsInRect: NSMakeRect(NSMidX(first), 0, 1, 10)];
    expect(NSEqualRanges(range, NSMakeRange(0, 1)), "inside the first column", range);

    [table release];
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    [pool release];
    return failures != 0;
}
