/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// -[NSTableView frameOfCellAtColumn:row:] with indexes outside the table. Documented contract
// (https://developer.apple.com/documentation/appkit/nstableview/frameofcell(atcolumn:row:)): it returns
// NSZeroRect when the column or row index is greater than the number of columns or rows, and takes the column's
// index in the tableColumns array. An index equal to the count names no column or row, and the siblings
// -rectOfColumn: and -rectOfRow: document NSZeroRect for any index outside the valid range, so the frame is
// NSZeroRect there too and no exception is raised; observed on macOS 26.7.3 and 10.14.4 for column 2 of 2, row 3 of 3 and negative or larger indexes, with rectOfColumn: and rectOfRow: also returning a zero rect there (black-box test). Prints PASS or FAIL. Does not need a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface Source : NSObject <NSTableViewDataSource>
@end
@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) t { return 3; }
- (id) tableView: (NSTableView *) t objectValueForTableColumn: (NSTableColumn *) c row: (NSInteger) r { return @"x"; }
@end

static NSRect frameOrRaise(NSTableView *tv, NSInteger column, NSInteger row, BOOL *raised) {
    NSRect frame = NSZeroRect;
    *raised = NO;
    @try {
        frame = [tv frameOfCellAtColumn: column row: row];
    } @catch (NSException *e) {
        *raised = YES;
    }
    return frame;
}

int main(void) {
    @autoreleasepool {
        Source *source = [[Source alloc] init];
        NSTableView *tv = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)];
        for (int i = 0; i < 2; i++) {
            NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]];
            [c setWidth: 100];
            [tv addTableColumn: c];
            [c release];
        }
        [tv setDataSource: source];
        [tv reloadData];

        BOOL raised;
        NSRect frame;

        // the last valid column still has a frame
        frame = frameOrRaise(tv, 1, 0, &raised);
        CHECK(!raised && !NSIsEmptyRect(frame), "last column raised or is empty: %s", [NSStringFromRect(frame) UTF8String]);

        // an index equal to the number of columns is outside the table
        frame = frameOrRaise(tv, [tv numberOfColumns], 0, &raised);
        CHECK(!raised, "column == numberOfColumns raised an exception");
        CHECK(NSEqualRects(frame, NSZeroRect), "column == numberOfColumns returned %s", [NSStringFromRect(frame) UTF8String]);

        frame = frameOrRaise(tv, [tv numberOfColumns] + 3, 0, &raised);
        CHECK(!raised && NSEqualRects(frame, NSZeroRect), "column beyond the columns: raised %d, frame %s", raised, [NSStringFromRect(frame) UTF8String]);

        frame = frameOrRaise(tv, -1, 0, &raised);
        CHECK(!raised && NSEqualRects(frame, NSZeroRect), "negative column: raised %d, frame %s", raised, [NSStringFromRect(frame) UTF8String]);

        // a row index equal to the number of rows names no row
        frame = frameOrRaise(tv, 0, [tv numberOfRows], &raised);
        CHECK(!raised && NSEqualRects(frame, NSZeroRect), "row == numberOfRows: raised %d, frame %s", raised, [NSStringFromRect(frame) UTF8String]);

        // a row index beyond the rows
        frame = frameOrRaise(tv, 0, [tv numberOfRows] + 3, &raised);
        CHECK(!raised && NSEqualRects(frame, NSZeroRect), "row beyond the rows: raised %d, frame %s", raised, [NSStringFromRect(frame) UTF8String]);

        frame = frameOrRaise(tv, 0, -1, &raised);
        CHECK(!raised && NSEqualRects(frame, NSZeroRect), "negative row: raised %d, frame %s", raised, [NSStringFromRect(frame) UTF8String]);

        [tv release];
        [source release];
        printf(failures ? "FAIL\n" : "PASS\n");
    }
    return failures != 0;
}
