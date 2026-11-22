// CFLAGS: -framework AppKit -fobjc-arc
// Copyright (C) 2026 Lubos Dolezel
//
// Editing a cell-based table's cell with editColumn:row:withEvent:select:, in an NSTableView and an NSOutlineView: a
// new table column and its data cell are editable; the edit puts the field editor in as the window's first responder
// (the table, first responder before, gives way), the row being edited is editedRow, and Return ends it, handing the
// text typed to the data source's set-object-value method. Observed on macOS 10.14.4 and 26.7.3, where it passes
// unchanged. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    failures += !ok;
}

@interface Source : NSObject <NSTableViewDataSource, NSOutlineViewDataSource>
@property NSMutableArray *rows;
@property NSString *set;
@end

@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return [_rows count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return _rows[row]; }
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    _set = [NSString stringWithFormat: @"%@ for row %ld", value, (long) row];
}
- (NSInteger)outlineView:(NSOutlineView *)outline numberOfChildrenOfItem:(id)item { return item ? 0 : [_rows count]; }
- (id)outlineView:(NSOutlineView *)outline child:(NSInteger)index ofItem:(id)item { return _rows[index]; }
- (BOOL)outlineView:(NSOutlineView *)outline isItemExpandable:(id)item { return NO; }
- (id)outlineView:(NSOutlineView *)outline objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item { return item; }
- (void)outlineView:(NSOutlineView *)outline setObjectValue:(id)value forTableColumn:(NSTableColumn *)column byItem:(id)item
{
    _set = [NSString stringWithFormat: @"%@ for %@", value, item];
}
@end

static void editIn(NSTableView *table, NSString *kind, NSString *expectedSet)
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200) styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered defer: NO];
    window.releasedWhenClosed = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: [window.contentView bounds]];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"name"];
    expect(column.isEditable, [NSString stringWithFormat: @"%@: a new column is editable", kind]);
    expect([column.dataCell isEditable], [NSString stringWithFormat: @"%@: a new column's data cell is editable", kind]);
    column.width = 200;
    [table addTableColumn: column];
    if ([table isKindOfClass: [NSOutlineView class]])
        ((NSOutlineView *) table).outlineTableColumn = column;
    Source *source = [Source new];
    source.rows = [@[ @"a", @"b", @"c" ] mutableCopy];
    table.dataSource = source;
    scroll.documentView = table;
    [window.contentView addSubview: scroll];
    [window makeKeyAndOrderFront: nil];
    [table reloadData];
    [window makeFirstResponder: table];

    [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 1] byExtendingSelection: NO];
    [table editColumn: 0 row: 1 withEvent: nil select: YES];
    id responder = [window firstResponder];
    expect([responder isKindOfClass: [NSTextView class]] && [responder isFieldEditor] && responder == table.currentEditor,
           [NSString stringWithFormat: @"%@: the field editor is first responder (%@)", kind, [responder class]]);
    expect(table.editedRow == 1 && table.editedColumn == 0, [NSString stringWithFormat: @"%@: row 1 is being edited", kind]);
    NSTextView *editor = (NSTextView *) table.currentEditor;
    expect([[editor string] isEqual: @"b"], [NSString stringWithFormat: @"%@: the editor has the cell's text", kind]);
    [editor selectAll: nil];
    [editor insertText: @"zz"];
    [editor insertNewline: nil];
    expect([source.set isEqual: expectedSet], [NSString stringWithFormat: @"%@: Return hands the text to the data source (%@)", kind, source.set]);
    expect(table.editedRow == -1, [NSString stringWithFormat: @"%@: Return ends the edit", kind]);
    [window close];
}

int main(void)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        [NSApplication sharedApplication];
        editIn([[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)], @"table view", @"zz for row 1");
        editIn([[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)], @"outline view", @"zz for b");
        printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    }
    return failures != 0;
}
