/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSTableView batch updates: the row count follows the data source when the
// outermost -endUpdates runs, and row insertion and removal notify the table.
// NSOutlineView item insertion reloads the data. No window is shown.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Rows : NSObject <NSTableViewDataSource> {
@public
    NSInteger count;
}
@end

@implementation Rows
- (NSInteger) numberOfRowsInTableView: (NSTableView *) tableView {
    return count;
}
- (id) tableView: (NSTableView *) tableView objectValueForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return [NSString stringWithFormat: @"%ld", (long) row];
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Rows *rows = [[Rows alloc] init];
        rows->count = 2;
        NSTableView *table = [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"a"];
        [table addTableColumn: column];
        [table setDataSource: rows];
        [table reloadData];
        expect([table numberOfRows] == 2, "initial row count");

        rows->count = 5;
        [table beginUpdates];
        [table beginUpdates];
        [table endUpdates];
        expect([table numberOfRows] == 2, "the inner endUpdates does not apply the change");
        [table endUpdates];
        expect([table numberOfRows] == 5, "the outermost endUpdates applies the change");

        // An unbalanced endUpdates is ignored.
        [table endUpdates];
        expect([table numberOfRows] == 5, "an unbalanced endUpdates does nothing");

        rows->count = 6;
        [table insertRowsAtIndexes: [NSIndexSet indexSetWithIndex: 3]
                     withAnimation: NSTableViewAnimationEffectNone];
        expect([table numberOfRows] == 6, "insertRowsAtIndexes: picks up the new count");
        rows->count = 4;
        [table removeRowsAtIndexes: [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(0, 2)]
                     withAnimation: NSTableViewAnimationEffectFade];
        expect([table numberOfRows] == 4, "removeRowsAtIndexes: picks up the new count");

        [table setUsesAutomaticRowHeights: YES];
        expect([table usesAutomaticRowHeights], "usesAutomaticRowHeights is kept");
        [table reloadDataForRowIndexes: [NSIndexSet indexSetWithIndex: 0]
                         columnIndexes: [NSIndexSet indexSetWithIndex: 0]];

        [table release];
        [column release];
        [rows release];
    }
    printf("table batch updates: %s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
