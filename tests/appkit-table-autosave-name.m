/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSTableView's autosaveName and autosaveTableColumns properties keep the values they
 * are given, and NSOutlineView's -setDropItem:dropChildIndex: can be called (an
 * application's data source calls it to retarget a drop it is validating) without
 * effect on the content of the outline view. Observed on macOS 10.14.4 and 26.7.3
 * through the public API:
 * - a new table has no autosave name and does not autosave its columns;
 * - the name is returned as given (a copy), and nil clears it;
 * - setting the name does not turn on autosaveTableColumns, and the flag does not
 *   need a name;
 * - -setDropItem:dropChildIndex: leaves the items and row count alone.
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) do { if (cond) printf("PASS: " __VA_ARGS__); else { printf("FAIL: " __VA_ARGS__); failures++; } printf("\n"); } while (0)

@interface Items : NSObject <NSOutlineViewDataSource>
@end

@implementation Items
- (NSInteger) outlineView: (NSOutlineView *) outline numberOfChildrenOfItem: (id) item {
    return item == nil ? 3 : 0;
}

- (id) outlineView: (NSOutlineView *) outline child: (NSInteger) index ofItem: (id) item {
    return [NSNumber numberWithInteger: index];
}

- (BOOL) outlineView: (NSOutlineView *) outline isItemExpandable: (id) item {
    return NO;
}

- (id) outlineView: (NSOutlineView *) outline objectValueForTableColumn: (NSTableColumn *) column byItem: (id) item {
    return [item description];
}
@end

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];

    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    CHECK([table autosaveName] == nil, "a new table has no autosave name");
    CHECK(![table autosaveTableColumns], "a new table does not autosave its columns");

    [table setAutosaveName: @"VDTestTable"];
    CHECK([[table autosaveName] isEqualToString: @"VDTestTable"], "the autosave name is returned");
    CHECK(![table autosaveTableColumns], "setting the name does not turn on autosaveTableColumns");

    NSMutableString *mutable = [NSMutableString stringWithString: @"Mutable"];
    [table setAutosaveName: mutable];
    [mutable appendString: @"Changed"];
    CHECK([[table autosaveName] isEqualToString: @"Mutable"], "the autosave name is a copy");

    [table setAutosaveTableColumns: YES];
    CHECK([table autosaveTableColumns], "autosaveTableColumns is kept");
    [table setAutosaveName: nil];
    CHECK([table autosaveName] == nil, "nil clears the autosave name");
    CHECK([table autosaveTableColumns], "clearing the name keeps autosaveTableColumns");
    [table setAutosaveTableColumns: NO];
    CHECK(![table autosaveTableColumns], "autosaveTableColumns can be turned off");

    Items *items = [[Items alloc] init];
    NSOutlineView *outline = [[[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease];
    [outline addTableColumn: column];
    [outline setOutlineTableColumn: column];
    [outline setDataSource: items];
    [outline reloadData];
    CHECK([outline numberOfRows] == 3, "the outline view has three rows");
    [outline setDropItem: nil dropChildIndex: 1];
    [outline setDropItem: [outline itemAtRow: 0] dropChildIndex: -1];
    CHECK([outline numberOfRows] == 3, "retargeting a drop leaves the rows alone");
    CHECK([[outline itemAtRow: 2] isEqual: [NSNumber numberWithInteger: 2]], "retargeting a drop leaves the items alone");

    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    [pool drain];
    return failures != 0;
}
