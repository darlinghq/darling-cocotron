// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView columnAutoresizingStyle: the default, the mapping to the deprecated
// autoresizesAllColumnsToFit flag, and how each style distributes a shrinking of the
// visible width over the columns. Expectations were observed on macOS 26 and Mojave and the
// program passes on both.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static NSTableView *makeTable(NSScrollView **scrollOut)
{
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    for (int i = 0; i < 3; i++)
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"c%d", i]] autorelease];
        [column setWidth:i == 2 ? 117 : 116];
        [column setMinWidth:50];
        [table addTableColumn:column];
    }
    [scroll setDocumentView:table];
    [scroll layoutSubtreeIfNeeded];
    *scrollOut = scroll;
    return table;
}

static CGFloat width(NSTableView *table, int column)
{
    return [[[table tableColumns] objectAtIndex:column] width];
}

// Applies the style, resizes the scroll view to the new width and returns the column widths
// before and after.
static void resizeWith(NSUInteger style, CGFloat newWidth, CGFloat before[3], CGFloat after[3])
{
    NSScrollView *scroll;
    NSTableView *table = makeTable(&scroll);
    [table setColumnAutoresizingStyle:style];
    for (int i = 0; i < 3; i++)
        before[i] = width(table, i);
    [scroll setFrameSize:NSMakeSize(newWidth, 200)];
    [scroll layoutSubtreeIfNeeded];
    for (int i = 0; i < 3; i++)
        after[i] = width(table, i);
}

static BOOL same(CGFloat a, CGFloat b) { return fabs(a - b) < 0.5; }

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        // Enumeration values
        expect(NSTableViewNoColumnAutoresizing == 0 && NSTableViewUniformColumnAutoresizingStyle == 1 &&
                   NSTableViewSequentialColumnAutoresizingStyle == 2 &&
                   NSTableViewReverseSequentialColumnAutoresizingStyle == 3 &&
                   NSTableViewLastColumnOnlyAutoresizingStyle == 4 && NSTableViewFirstColumnOnlyAutoresizingStyle == 5,
               @"style values");

        // Default and the deprecated flag
        NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
        expect([table columnAutoresizingStyle] == NSTableViewLastColumnOnlyAutoresizingStyle, @"default style is last-column-only");
        expect(![table autoresizesAllColumnsToFit], @"default flag is NO");
        [table setAutoresizesAllColumnsToFit:YES];
        expect([table columnAutoresizingStyle] == NSTableViewUniformColumnAutoresizingStyle, @"flag YES selects uniform");
        [table setAutoresizesAllColumnsToFit:NO];
        expect([table columnAutoresizingStyle] == NSTableViewLastColumnOnlyAutoresizingStyle, @"flag NO selects last-column-only");
        static const BOOL flagFor[6] = {NO, YES, YES, YES, NO, NO};
        for (NSUInteger style = 0; style <= 5; style++)
        {
            [table setColumnAutoresizingStyle:style];
            expect([table columnAutoresizingStyle] == style, @"style round-trips");
            expect([table autoresizesAllColumnsToFit] == flagFor[style], @"flag derived from style");
        }
        [table setColumnAutoresizingStyle:NSTableViewReverseSequentialColumnAutoresizingStyle];
        [table setColumnAutoresizingStyle:7];
        expect([table columnAutoresizingStyle] == NSTableViewReverseSequentialColumnAutoresizingStyle, @"an invalid style is ignored");

        CGFloat before[3], after[3];

        // Shrinking the visible width from 400 to 300
        resizeWith(NSTableViewNoColumnAutoresizing, 300, before, after);
        expect(same(before[0], after[0]) && same(before[1], after[1]) && same(before[2], after[2]), @"none: shrink leaves widths");

        resizeWith(NSTableViewUniformColumnAutoresizingStyle, 300, before, after);
        expect(after[0] < before[0] - 5 && after[1] < before[1] - 5 && after[2] < before[2] - 5, @"uniform: every column shrinks");
        expect(fabs(after[0] - after[1]) <= 1.5 && fabs(before[0] - after[0] - (before[2] - after[2])) <= 1.5,
               @"uniform: by the same amount");

        resizeWith(NSTableViewSequentialColumnAutoresizingStyle, 300, before, after);
        expect(same(before[0], after[0]) && after[2] < before[2] - 20, @"sequential: from the last column backwards");

        resizeWith(NSTableViewReverseSequentialColumnAutoresizingStyle, 300, before, after);
        expect(same(before[2], after[2]) && after[0] < before[0] - 20, @"reverse sequential: from the first column on");

        resizeWith(NSTableViewLastColumnOnlyAutoresizingStyle, 300, before, after);
        expect(same(before[0], after[0]) && same(before[1], after[1]) && after[2] < before[2] - 20, @"last only: the last column shrinks");

        resizeWith(NSTableViewFirstColumnOnlyAutoresizingStyle, 300, before, after);
        expect(same(before[1], after[1]) && same(before[2], after[2]) && after[0] < before[0] - 20, @"first only: the first column shrinks");

        // A much narrower width: a column stops at its minimum width (50) and the next one takes over
        resizeWith(NSTableViewSequentialColumnAutoresizingStyle, 200, before, after);
        expect(same(after[2], 50) && same(after[1], 50), @"sequential: last columns stop at the minimum");

        resizeWith(NSTableViewReverseSequentialColumnAutoresizingStyle, 200, before, after);
        expect(same(after[0], 50) && same(after[1], 50), @"reverse sequential: first columns stop at the minimum");

        resizeWith(NSTableViewLastColumnOnlyAutoresizingStyle, 200, before, after);
        expect(same(before[0], after[0]) && same(before[1], after[1]) && same(after[2], 50), @"last only: stops at the minimum width");

        resizeWith(NSTableViewFirstColumnOnlyAutoresizingStyle, 200, before, after);
        expect(same(before[1], after[1]) && same(before[2], after[2]) && same(after[0], 50), @"first only: stops at the minimum width");

        // Growing is left out: macOS 26 spreads the extra width as the style says, but a
        // table that does not already fill the clip view (Mojave) keeps its widths.
    }
    printf("PASS\n");
    return 0;
}
