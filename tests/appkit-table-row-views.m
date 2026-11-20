/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A view-based table view puts each shown row in a row view (NSTableRowView,
// or the one its delegate's tableView:rowViewForRow: gives), with the row's
// cell views as subviews. rowViewAtRow:makeIfNecessary: returns the row view
// of a shown row, makes one for another row only when asked, and raises
// NSTableViewException for a row outside the table;
// enumerateAvailableRowViewsUsingBlock: visits the row views there are. The
// delegate is told with tableView:didAddRowView:forRow:.
// Results as on macOS 26.7.3 and 10.14.4. Needs a display. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

@interface CustomRowView : NSTableRowView
@end
@implementation CustomRowView
@end

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
    BOOL _custom;
    NSMutableArray *_log;
    NSMutableDictionary *_given;
}
@end

@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) table {
    return 50;
}
- (NSView *) tableView: (NSTableView *) table viewForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 100, 17)] autorelease];
}
- (NSTableRowView *) tableView: (NSTableView *) table rowViewForRow: (NSInteger) row {
    [_log addObject: [NSString stringWithFormat: @"make %ld", (long) row]];
    if (!_custom)
        return nil;
    NSTableRowView *view = [[[CustomRowView alloc] init] autorelease];
    [_given setObject: view forKey: @(row)];
    return view;
}
- (void) tableView: (NSTableView *) table didAddRowView: (NSTableRowView *) rowView forRow: (NSInteger) row {
    [_log addObject: [NSString stringWithFormat: @"add %ld", (long) row]];
    if (_custom && [_given objectForKey: @(row)] != rowView)
        [_log addObject: @"other view added"];
}
@end

static BOOL raises(NSTableView *table, NSInteger row, BOOL make) {
    @try {
        [table rowViewAtRow: row makeIfNecessary: make];
    } @catch (NSException *e) {
        return [[e name] isEqualToString: @"NSTableViewException"];
    }
    return NO;
}

static void run(BOOL custom) {
    printf("-- %s row views\n", custom ? "delegate's" : "default");
    Source *source = [[Source alloc] init];
    source->_custom = custom;
    source->_log = [[NSMutableArray alloc] init];
    source->_given = [[NSMutableDictionary alloc] init];

    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease];
    [column setWidth: 180];
    [table addTableColumn: column];
    [table setDelegate: source];
    [table setDataSource: source];
    [scroll setDocumentView: table];
    [window setContentView: scroll];
    [table reloadData];

    expect([table rowViewAtRow: 0 makeIfNecessary: NO] == nil, "before the table is shown, a row has no row view");

    [window orderFront: nil];
    [window layoutIfNeeded];
    [window displayIfNeeded];

    NSTableRowView *first = [table rowViewAtRow: 0 makeIfNecessary: NO];
    expect(first != nil, "a shown row has a row view");
    expect([first isKindOfClass: custom ? [CustomRowView class] : [NSTableRowView class]],
           custom ? "it is the delegate's row view" : "it is an NSTableRowView");
    expect([first superview] == table, "the row view is a subview of the table");
    expect(NSEqualRects([first frame], [table rectOfRow: 0]), "the row view covers the row");
    NSView *cell = [table viewAtColumn: 0 row: 0 makeIfNecessary: NO];
    expect(cell != nil && [cell superview] == first, "the cell view is a subview of the row view");
    expect([table rowForView: cell] == 0 && [table rowForView: first] == 0, "rowForView: finds the row of the cell and row views");

    expect([table rowViewAtRow: 40 makeIfNecessary: NO] == nil, "a row that is not shown has no row view");
    NSTableRowView *made = [table rowViewAtRow: 40 makeIfNecessary: YES];
    expect(made != nil && [made isKindOfClass: custom ? [CustomRowView class] : [NSTableRowView class]],
           "asked to, the table makes the row view of a row that is not shown");
    expect([table viewAtColumn: 0 row: 40 makeIfNecessary: NO] != nil, "making a row view makes its cell views");
    expect([table rowViewAtRow: 40 makeIfNecessary: NO] == made, "the made row view is returned again");

    __block BOOL sawFirst = NO, sawMade = NO, rowsMatch = YES;
    [table enumerateAvailableRowViewsUsingBlock: ^(NSTableRowView *rowView, NSInteger row) {
        sawFirst |= rowView == first && row == 0;
        sawMade |= rowView == made && row == 40;
        rowsMatch &= [table rowViewAtRow: row makeIfNecessary: NO] == rowView;
    }];
    expect(sawFirst && sawMade && rowsMatch, "enumerateAvailableRowViewsUsingBlock: visits the row views with their rows");

    NSUInteger make = [source->_log indexOfObject: @"make 0"], add = [source->_log indexOfObject: @"add 0"];
    expect(make != NSNotFound && add != NSNotFound && make < add && ![source->_log containsObject: @"other view added"],
           "the delegate is asked for the row view, then told it was added");

    [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
    expect([first isSelected] && ![made isSelected], "the row view of a selected row is selected");

    expect(raises(table, 50, YES) && raises(table, -1, NO), "a row outside the table raises NSTableViewException");

    [window orderOut: nil];
    [table setDelegate: nil];
    [table setDataSource: nil];
    [window release];
    [source->_log release];
    [source->_given release];
    [source release];
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        run(NO);
        run(YES);
    }
    printf("failures=%d\n", failures);
    return failures ? 1 : 0;
}
