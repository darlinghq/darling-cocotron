// Copyright (C) 2026 Lubos Dolezel
//
// NSTableColumn -sizeToFit. The documentation says: it resizes the column to fit the width
// of its header cell; a maximum width below the header's width is raised to it and a minimum
// width above it is lowered to it; a change of the width marks the table view as needing
// display. Observed on macOS 26.7.3 and Mac OS X 10.14.4 (x86_64 and i386, identical): the header cell's
// width is that of -cellSize (unrounded), the limits and the width go through the setters
// (a subclass's overrides are called), the cell is the stored header cell and not what an override of
// -headerCell returns, and the table view is marked as needing display when the width changes (26.7.3).
// The program passes on both Macs (the display request is counted through -setNeedsDisplay: and
// -setNeedsDisplayInRect:, both of which AppKit uses).
// Build: clang -fobjc-arc -framework AppKit appkit-tablecolumn-sizetofit.m
// Not covered: the drawn result. On master the method does not exist, so with ARC the test
// does not compile against master's header and without ARC every call raises an unrecognized
// selector.
#import <AppKit/AppKit.h>
#include <float.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// The legacy Objective-C runtime (i386) does not synthesize properties, so the helper
// classes below declare their state as plain instance variables.

// A header cell whose width is chosen by the test, so the expected result is a number.
@interface FixedHeaderCell : NSTableHeaderCell {
@public
    CGFloat fixedWidth;
}
@end
@implementation FixedHeaderCell
- (NSSize)cellSize { return NSMakeSize(fixedWidth, 17); }
@end

// Counts the display requests.
@interface CountingTableView : NSTableView {
@public
    NSInteger displayRequests;
}
@end
@implementation CountingTableView
- (void)setNeedsDisplay:(BOOL)flag {
    if (flag) displayRequests++;
    [super setNeedsDisplay:flag];
}
- (void)setNeedsDisplayInRect:(NSRect)rect {
    displayRequests++;
    [super setNeedsDisplayInRect:rect];
}
@end

// An application subclass that observes the setters the way an override does.
@interface RecordingColumn : NSTableColumn {
@public
    NSInteger widthSets, minSets, maxSets;
}
@end
@implementation RecordingColumn
- (void)setWidth:(CGFloat)width { widthSets++; [super setWidth:width]; }
- (void)setMinWidth:(CGFloat)width { minSets++; [super setMinWidth:width]; }
- (void)setMaxWidth:(CGFloat)width { maxSets++; [super setMaxWidth:width]; }
@end

// An application subclass that supplies its header cell through an override.
@interface OverridingColumn : NSTableColumn {
@public
    NSCell *replacement;
}
- (id)headerCell;
@end
@implementation OverridingColumn
- (id)headerCell { return replacement ? replacement : [super headerCell]; }
@end

static NSTableColumn *column(Class cls, CGFloat headerWidth) {
    NSTableColumn *col = [[cls alloc] initWithIdentifier:@"c"];
    FixedHeaderCell *cell = [[FixedHeaderCell alloc] initTextCell:@"Title"];
    cell->fixedWidth = headerWidth;
    [col setHeaderCell:cell];
    return col;
}

int main(void) {
    @autoreleasepool {
        CHECK([NSTableColumn instancesRespondToSelector:@selector(sizeToFit)]);

        // The default limits (10 and the largest float) already hold the header: the width
        // becomes the header's width and the limits stay.
        NSTableColumn *col = column([NSTableColumn class], 137);
        CHECK([col width] == 100);
        [col sizeToFit];
        CHECK([col width] == 137);
        CHECK([col minWidth] == 10);
        CHECK([col maxWidth] == FLT_MAX);

        // A column wider than its header shrinks to it.
        [col setWidth:400];
        CHECK([col width] == 400);
        [col sizeToFit];
        CHECK([col width] == 137);

        // A maximum below the header's width is raised to it.
        col = column([NSTableColumn class], 137);
        [col setMaxWidth:50];
        [col sizeToFit];
        CHECK([col maxWidth] == 137);
        CHECK([col width] == 137);
        CHECK([col minWidth] == 10);

        // A minimum above the header's width is lowered to it.
        col = column([NSTableColumn class], 137);
        [col setMinWidth:200];
        [col setWidth:250];
        [col sizeToFit];
        CHECK([col minWidth] == 137);
        CHECK([col width] == 137);
        CHECK([col maxWidth] == FLT_MAX);

        // A limit equal to the header's width stays.
        col = column([NSTableColumn class], 137);
        [col setMinWidth:137];
        [col setMaxWidth:137];
        [col sizeToFit];
        CHECK([col minWidth] == 137 && [col maxWidth] == 137 && [col width] == 137);

        // A tiny header lowers the minimum, then the width follows it.
        col = column([NSTableColumn class], 3);
        [col sizeToFit];
        CHECK([col minWidth] == 3);
        CHECK([col width] == 3);

        // Repeating the call changes nothing.
        col = column([NSTableColumn class], 137);
        [col sizeToFit];
        [col sizeToFit];
        CHECK([col width] == 137 && [col minWidth] == 10 && [col maxWidth] == FLT_MAX);

        // The width of a real header cell follows its title: the cell's own width, and a
        // longer title gives a wider column.
        NSTableColumn *shortCol = [[NSTableColumn alloc] initWithIdentifier:@"s"];
        [shortCol setTitle:@"A"];
        [shortCol sizeToFit];
        CHECK([shortCol width] == [[shortCol headerCell] cellSize].width);
        NSTableColumn *longCol = [[NSTableColumn alloc] initWithIdentifier:@"l"];
        [longCol setTitle:@"A much longer column title"];
        [longCol sizeToFit];
        CHECK([longCol width] == [[longCol headerCell] cellSize].width);
        CHECK([longCol width] > [shortCol width]);
        CHECK([shortCol width] > 0);
        // a new title and a second call follow the new title
        [shortCol setTitle:@"A much longer column title"];
        [shortCol sizeToFit];
        CHECK([shortCol width] == [longCol width]);

        // The table view is marked as needing display when the width changes, and not when
        // it does not.
        CountingTableView *table = [[CountingTableView alloc]
            initWithFrame:NSMakeRect(0, 0, 400, 200)];
        col = column([NSTableColumn class], 137);
        [table addTableColumn:col];
        table->displayRequests = 0;
        [col sizeToFit];
        CHECK([col width] == 137);
        CHECK(table->displayRequests > 0);
        table->displayRequests = 0;
        [col sizeToFit];
        CHECK([col width] == 137);
        CHECK(table->displayRequests == 0);
        // a width that differs again is marked again
        [col setWidth:150];
        table->displayRequests = 0;
        [col sizeToFit];
        CHECK([col width] == 137);
        CHECK(table->displayRequests > 0);

        // A subclass whose setters are overridden sees the changes.
        RecordingColumn *recording = (RecordingColumn *)column([RecordingColumn class], 137);
        [recording setMaxWidth:50];
        recording->widthSets = recording->minSets = recording->maxSets = 0;
        [recording sizeToFit];
        CHECK([recording width] == 137);
        CHECK([recording maxWidth] == 137);
        CHECK(recording->widthSets == 1);
        CHECK(recording->maxSets == 1);
        CHECK(recording->minSets == 0);

        // QUIRK (macOS 26.7.3 and 10.14.4, probe sizetofit.m): the cell is the stored header cell, not the one an
        // override of -headerCell returns.
        OverridingColumn *overriding = (OverridingColumn *)column([OverridingColumn class], 137);
        FixedHeaderCell *other = [[FixedHeaderCell alloc] initTextCell:@"Other"];
        other->fixedWidth = 61;
        overriding->replacement = other;
        [overriding sizeToFit];
        CHECK([overriding width] == 137);
        CHECK([overriding minWidth] == 10);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
