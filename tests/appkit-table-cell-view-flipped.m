/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// In a view-based table view, the row view is flipped (origin at the top
// left) and the cell view inside it is not (origin at the bottom left), so a
// cell view that draws or places its content in the usual bottom-up
// coordinates shows it where it expects. A cell view that draws its own
// content must see an unflipped context with the origin at the bottom of the
// row. Results as on macOS 26.7.3. Needs a display. No ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

// Fills the lower half of its bounds (bottom-up) with red
@interface MarkCellView : NSTableCellView
@end
@implementation MarkCellView
- (void) drawRect: (NSRect) dirty {
    [[NSColor whiteColor] setFill];
    NSRectFill([self bounds]);
    [[NSColor redColor] setFill];
    NSRectFill(NSMakeRect(0, 0, NSWidth([self bounds]), NSHeight([self bounds]) / 2));
}
@end

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@end
@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) table {
    return 3;
}
- (NSView *) tableView: (NSTableView *) table viewForTableColumn: (NSTableColumn *) column row: (NSInteger) row {
    return [[[MarkCellView alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)] autorelease];
}
@end

static void pixel(NSBitmapImageRep *rep, NSInteger x, NSInteger y, int *r, int *g, int *b) {
    NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpace: [NSColorSpace genericRGBColorSpace]];
    *r = (int) ([c redComponent] * 255 + 0.5);
    *g = (int) ([c greenComponent] * 255 + 0.5);
    *b = (int) ([c blueComponent] * 255 + 0.5);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSTableRowView *plainRow = [[[NSTableRowView alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)] autorelease];
    NSTableCellView *plainCell = [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 100, 20)] autorelease];
    expect([plainRow isFlipped], "a row view is flipped");
    expect(![plainCell isFlipped], "a cell view is not flipped");

    NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 200, 100)
                                                    styleMask: NSWindowStyleMaskTitled
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO] autorelease];
    NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier: @"c"] autorelease];
    [column setWidth: 100];
    [table addTableColumn: column];
    [table setHeaderView: nil];
    [table setRowHeight: 20];
    [table setIntercellSpacing: NSZeroSize];
    Source *source = [[[Source alloc] init] autorelease];
    [table setDataSource: source];
    [table setDelegate: source];
    [scroll setDocumentView: table];
    [[window contentView] addSubview: scroll];
    [window orderFront: nil];
    [table reloadData];
    [table layoutSubtreeIfNeeded];
    [window displayIfNeeded];

    NSTableRowView *row = [table rowViewAtRow: 0 makeIfNecessary: NO];
    NSView *cell = [table viewAtColumn: 0 row: 0 makeIfNecessary: NO];
    expect(row != nil && [row isFlipped], "the table's row view is flipped");
    expect(cell != nil && ![cell isFlipped], "the table's cell view is not flipped");
    expect([cell superview] == row, "the cell view is in the row view");

    // The cell view's bottom half (bottom-up y 0..10) is the lower half of the row on screen
    NSRect lower = [cell convertRect: NSMakeRect(0, 0, 100, 10) toView: table];
    NSRect rowRect = [table rectOfRow: 0];
    expect(NSMinY(lower) == NSMinY(rowRect) + 10 && NSHeight(lower) == 10,
           "the cell view's bottom half is the lower half of the row in the table");

    // What is drawn: the red lower half shows in the lower half of the row
    NSRect rowInTable = [table rectOfRow: 0];
    NSBitmapImageRep *rep = [table bitmapImageRepForCachingDisplayInRect: rowInTable];
    [table cacheDisplayInRect: rowInTable toBitmapImageRep: rep];
    int r, g, b;
    pixel(rep, 50, 15, &r, &g, &b);
    expect(r > 200 && g < 60 && b < 60, "the lower half of the cell view's row is red");
    pixel(rep, 50, 4, &r, &g, &b);
    expect(r > 200 && g > 200 && b > 200, "the upper half of the cell view's row is white");

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    [pool drain];
    return failures != 0;
}
