// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView columnAutoresizingStyle: the default, the mapping to the deprecated
// autoresizesAllColumnsToFit flag, and how each style distributes a shrinking of the
// visible width over the columns. Expectations were observed on macOS 26 and Mojave and the
// program passes on both, except test_quirk_uniform_shrink_passes_the_shortfall_on, whose expectations are
// taken from probe 657.6 on macOS 26.1; that test has not been run on a Mac or in a guest.
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

static CGFloat totalWidth(NSTableView *table)
{
    CGFloat total = 0;
    for (NSTableColumn *column in [table tableColumns])
        total += [column width];
    return total;
}

// QUIRK (macOS 26.1, probe 657.6 "style Uniform ... widths before=[50,60,70,80,240] after=[20,20,26.5,36.5,197]"):
// the uniform style shrinks the columns that can by the share of those that reached their minimum width too, so
// the widths lose exactly what the clip view lost (200 in the probe). The documentation names no such rule. The half points of the probe depend on the display scale and the table style, so only the
// total, the order in which columns reach the minimum and the ordering of the rest are pinned.
static void test_quirk_uniform_shrink_passes_the_shortfall_on(void)
{
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    CGFloat widths[5] = {50, 60, 70, 80, 240};
    for (int i = 0; i < 5; i++)
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"u%d", i]] autorelease];
        [column setMinWidth:20];
        [column setMaxWidth:1000];
        [column setWidth:widths[i]];
        [table addTableColumn:column];
    }
    [table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [scroll setDocumentView:table];
    // the columns fill the clip view exactly before it shrinks
    CGFloat filled = NSMaxX([table rectOfColumn:4]);
    [scroll setFrameSize:NSMakeSize(filled, 200)];
    [scroll layoutSubtreeIfNeeded];
    CGFloat before = totalWidth(table);

    [scroll setFrameSize:NSMakeSize(filled - 200, 200)];
    [scroll layoutSubtreeIfNeeded];
    expect(same(before - totalWidth(table), 200), @"uniform: the widths lose exactly what the clip view lost");
    expect(same(width(table, 0), 20) && same(width(table, 1), 20), @"uniform: the two narrowest columns are at the minimum");
    expect(width(table, 2) > 20 && width(table, 2) < width(table, 3) && width(table, 3) < width(table, 4),
           @"uniform: the others keep their order");
    // the share the columns at the minimum could not take went to the others: more than the plain share of 40
    expect(70 - width(table, 2) > 40 && 80 - width(table, 3) > 40 && 240 - width(table, 4) > 40,
           @"uniform: the others shrink by more than the plain share");
}

// QUIRK (macOS 26.7.3 and 10.14.4, probe p790): the whole points of a uniform resize. Columns start at the given
// widths and fill the clip view exactly; the clip view then changes by delta.
static void checkUniformWidths(const char *what, const CGFloat *start, int count, CGFloat maxWidth, CGFloat delta, const CGFloat *expected)
{
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)] autorelease];
    CGFloat filled = 0;
    [table setIntercellSpacing:NSMakeSize(0, 0)];
    for (int i = 0; i < count; i++)
    {
        NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"w%d", i]] autorelease];
        [column setMinWidth:20];
        [column setMaxWidth:maxWidth];
        [column setWidth:start[i]];
        [table addTableColumn:column];
        filled += start[i];
    }
    [table setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
    [scroll setHasVerticalScroller:NO];
    [scroll setDocumentView:table];
    [scroll setFrameSize:NSMakeSize(filled, 200)];
    [scroll layoutSubtreeIfNeeded];
    [scroll setFrameSize:NSMakeSize(filled + delta, 200)];
    [scroll layoutSubtreeIfNeeded];
    BOOL ok = YES;
    for (int i = 0; i < count; i++)
        if (!same(width(table, i), expected[i]))
            ok = NO;
    expect(ok, [NSString stringWithFormat:@"uniform whole points: %s", what]);
}

static void test_quirk_uniform_whole_points(void)
{
    const CGFloat five[5] = {50, 60, 70, 80, 240}, up[5] = {50, 60, 70, 80, 90};
    const CGFloat a[5] = {20, 20, 26, 37, 197}, b[5] = {20, 20, 25, 36, 196}, c[5] = {30, 40, 50, 60, 220};
    const CGFloat d[5] = {20, 20, 20, 20, 113}, e[5] = {75, 84, 94, 100, 100}, f[5] = {71, 81, 91, 101, 109};
    const CGFloat g[5] = {39, 49, 59, 69, 81};
    checkUniformWidths("200 narrower, columns reach the minimum", five, 5, 1000, -200, a);
    checkUniformWidths("203 narrower", five, 5, 1000, -203, b);
    checkUniformWidths("100 narrower", five, 5, 1000, -100, c);
    checkUniformWidths("307 narrower", five, 5, 1000, -307, d);
    checkUniformWidths("103 wider, maximum width 100", up, 5, 100, 103, e);
    checkUniformWidths("103 wider, no limit", up, 5, 1000, 103, f);
    checkUniformWidths("53 narrower, no limit reached", up, 5, 1000, -53, g);
}

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

        test_quirk_uniform_shrink_passes_the_shortfall_on();
        test_quirk_uniform_whole_points();

        // Growing is left out: macOS 26 spreads the extra width as the style says, but a
        // table that does not already fill the clip view (Mojave) keeps its widths.
    }
    printf("PASS\n");
    return 0;
}
