/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Frame of a table cell (black-box observation on macOS 10.14.4 and 26.7.3 with the plain table style):
// -[NSTableView frameOfCellAtColumn:row:] is the column's width by the row's height, placed half the
// intercell spacing (rounded down) in from the corner of the rectangle of the column and the row. The cell
// views of a view-based table sit at that frame, in the row view's coordinates: the row view starts at the
// rectangle of the row, so a cell view's y is half the vertical spacing. A group row's view spans the row
// view's width, at x 0. In an outline view the outline column's cell frame is also indented by 16 points and
// the item's level times indentationPerLevel (and narrowed by as much), and the disclosure triangle's frame
// is 12 points wide, 6 in from the column's edge plus the indentation, one point less high than the row (when
// there is vertical spacing), empty for an item that cannot be expanded. Prints PASS or FAIL. Needs a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSString *R(NSRect r) { return NSStringFromRect(r); }
#define CHECK_RECT(actual, ex, ey, ew, eh, what) do { \
    NSRect a_ = (actual), e_ = NSMakeRect(ex, ey, ew, eh); \
    CHECK(NSEqualRects(a_, e_), "%s: got %s, expected %s", what, [R(a_) UTF8String], [R(e_) UTF8String]); } while (0)

// macOS 11 and later lay out group rows and outline columns differently (and apply a table style); the
// behavior followed is the one before that.
static BOOL laterSystem(void) {
    return NSAppKitVersionNumber >= 2000;
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate> {
@public
    BOOL viewBased;
    NSInteger groupRow;
}
@end
@implementation Source
- (NSInteger) numberOfRowsInTableView: (NSTableView *) t { return 3; }
- (id) tableView: (NSTableView *) t objectValueForTableColumn: (NSTableColumn *) c row: (NSInteger) r { return @"x"; }
- (BOOL) tableView: (NSTableView *) t isGroupRow: (NSInteger) r { return r == groupRow; }
- (NSView *) tableView: (NSTableView *) t viewForTableColumn: (NSTableColumn *) c row: (NSInteger) r {
    return [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 50, 10)] autorelease];
}
// "a" has children a0 and a1, "a0" has a00, and "b" is a leaf
- (NSInteger) outlineView: (NSOutlineView *) o numberOfChildrenOfItem: (id) item {
    if (item == nil) return 2;
    if ([item isEqual: @"a"]) return 2;
    if ([item isEqual: @"a0"]) return 1;
    return 0;
}
- (id) outlineView: (NSOutlineView *) o child: (NSInteger) i ofItem: (id) item {
    if (item == nil) return i == 0 ? @"a" : @"b";
    if ([item isEqual: @"a"]) return i == 0 ? @"a0" : @"a1";
    return @"a00";
}
- (BOOL) outlineView: (NSOutlineView *) o isItemExpandable: (id) item { return [item isEqual: @"a"] || [item isEqual: @"a0"]; }
- (id) outlineView: (NSOutlineView *) o objectValueForTableColumn: (NSTableColumn *) c byItem: (id) item { return item; }
- (NSView *) outlineView: (NSOutlineView *) o viewForTableColumn: (NSTableColumn *) c item: (id) item {
    return [[[NSTableCellView alloc] initWithFrame: NSMakeRect(0, 0, 50, 10)] autorelease];
}
@end

static Source *source;
static NSWindow *window;

static NSTableView *makeTable(BOOL outline, BOOL viewBased, NSSize spacing, CGFloat rowHeight, CGFloat indentation) {
    NSTableView *tv = outline ? [[NSOutlineView alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)]
                              : [[NSTableView alloc] initWithFrame: NSMakeRect(0, 0, 400, 200)];
    for (int i = 0; i < 2; i++) {
        NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier: [NSString stringWithFormat: @"c%d", i]];
        [c setWidth: (outline && i == 0) ? 200 : 100 + 20 * i];
        [tv addTableColumn: c];
        [c release];
    }
    // The plain style, the only one before macOS 11, has no margins around the cells
    if ([tv respondsToSelector: NSSelectorFromString(@"setStyle:")])
        [tv setValue: [NSNumber numberWithInteger: 4] forKey: @"style"];
    [tv setColumnAutoresizingStyle: NSTableViewNoColumnAutoresizing];
    [tv setIntercellSpacing: spacing];
    [tv setRowSizeStyle: NSTableViewRowSizeStyleCustom];
    [tv setRowHeight: rowHeight];
    if (outline) {
        [(NSOutlineView *) tv setOutlineTableColumn: [tv tableColumns][0]];
        // otherwise expanding widens the outline column to fit the indentation
        [(NSOutlineView *) tv setAutoresizesOutlineColumn: NO];
        if (indentation > 0)
            [(NSOutlineView *) tv setIndentationPerLevel: indentation];
    }
    source->viewBased = viewBased;
    [tv setDataSource: source];
    if (viewBased)
        [tv setDelegate: source];
    [window setContentView: tv];
    [tv reloadData];
    if (outline)
        [(NSOutlineView *) tv expandItem: @"a" expandChildren: YES];
    [tv layoutSubtreeIfNeeded];
    return tv;
}

static void checkViewBased(NSSize sp, const char *what) {
    CGFloat rowH = 20, ix = floor(sp.width / 2), iy = floor(sp.height / 2);
    NSTableView *tv = makeTable(NO, YES, sp, rowH, 0);
    source->groupRow = -1;
    [tv reloadData];
    char label[160];

    for (NSInteger r = 0; r < 3; r++) {
        NSTableRowView *rv = [tv rowViewAtRow: r makeIfNecessary: YES];
        CGFloat rowY = r * (rowH + sp.height);

        snprintf(label, sizeof label, "%s: row view %ld", what, (long) r);
        CHECK(NSMinX([rv frame]) == 0 && NSMinY([rv frame]) == rowY && NSHeight([rv frame]) == rowH + sp.height, "%s: %s", label,
              [R([rv frame]) UTF8String]);
        NSView *c0 = [tv viewAtColumn: 0 row: r makeIfNecessary: YES];
        NSView *c1 = [tv viewAtColumn: 1 row: r makeIfNecessary: YES];
        snprintf(label, sizeof label, "%s: cell view of row %ld column 0", what, (long) r);
        CHECK_RECT([c0 frame], ix, iy, 100, rowH, label);
        snprintf(label, sizeof label, "%s: cell view of row %ld column 1", what, (long) r);
        CHECK_RECT([c1 frame], 100 + sp.width + ix, iy, 120, rowH, label);
        CHECK([c0 superview] == rv, "%s: cell view not in its row view", what);
        snprintf(label, sizeof label, "%s: frameOfCell row %ld column 0", what, (long) r);
        CHECK_RECT([tv frameOfCellAtColumn: 0 row: r], ix, rowY + iy, 100, rowH, label);
        snprintf(label, sizeof label, "%s: frameOfCell row %ld column 1", what, (long) r);
        CHECK_RECT([tv frameOfCellAtColumn: 1 row: r], 100 + sp.width + ix, rowY + iy, 120, rowH, label);
        // the cell view's frame in the table's coordinates is the frame of the cell
        CHECK(NSEqualRects([tv convertRect: [c1 bounds] fromView: c1], [tv frameOfCellAtColumn: 1 row: r]), "%s: cell view not at frameOfCell", what);
    }
    [tv release];

    // a group row: one view over the whole row view
    if (laterSystem())
        return;
    tv = makeTable(NO, YES, sp, rowH, 0);
    source->groupRow = 1;
    [tv reloadData];
    NSTableRowView *grv = [tv rowViewAtRow: 1 makeIfNecessary: YES];
    NSView *gv = [tv viewAtColumn: 0 row: 1 makeIfNecessary: YES];
    CHECK(NSMinX([gv frame]) == 0 && NSMinY([gv frame]) == iy && NSWidth([gv frame]) == NSWidth([grv frame]) &&
                  NSHeight([gv frame]) == NSHeight([grv frame]) - sp.height,
          "%s: group row view %s in row view %s", what, [R([gv frame]) UTF8String], [R([grv frame]) UTF8String]);
    CHECK([tv viewAtColumn: 1 row: 1 makeIfNecessary: YES] == nil, "%s: group row has a view in column 1", what);
    [tv release];
}

static void checkCellBased(NSSize sp, const char *what) {
    CGFloat rowH = 17, ix = floor(sp.width / 2), iy = floor(sp.height / 2);
    NSTableView *tv = makeTable(NO, NO, sp, rowH, 0);
    char label[160];

    for (NSInteger r = 0; r < 3; r++) {
        CGFloat rowY = r * (rowH + sp.height);

        snprintf(label, sizeof label, "%s: cell-based row %ld column 0", what, (long) r);
        CHECK_RECT([tv frameOfCellAtColumn: 0 row: r], ix, rowY + iy, 100, rowH, label);
        snprintf(label, sizeof label, "%s: cell-based row %ld column 1", what, (long) r);
        CHECK_RECT([tv frameOfCellAtColumn: 1 row: r], 100 + sp.width + ix, rowY + iy, 120, rowH, label);
        snprintf(label, sizeof label, "%s: rectOfRow %ld", what, (long) r);
        CHECK(NSMinY([tv rectOfRow: r]) == rowY && NSHeight([tv rectOfRow: r]) == rowH + sp.height, "%s", label);
    }
    [tv release];
}

static void checkOutline(NSSize sp, CGFloat indentation, BOOL viewBased, const char *what) {
    CGFloat rowH = 17, ix = floor(sp.width / 2), iy = floor(sp.height / 2);
    NSOutlineView *ov = (NSOutlineView *) makeTable(YES, viewBased, sp, rowH, indentation);
    CGFloat per = [ov indentationPerLevel];
    char label[160];

    // rows: a (level 0, expandable), a0 (1, expandable), a00 (2), a1 (1), b (0)
    CHECK([ov numberOfRows] == 5, "%s: %ld rows", what, (long) [ov numberOfRows]);
    NSInteger levels[] = {0, 1, 2, 1, 0};
    BOOL expandable[] = {YES, YES, NO, NO, NO};
    for (NSInteger r = 0; r < 5; r++) {
        CGFloat rowY = r * (rowH + sp.height);
        CGFloat inset = 16 + levels[r] * per;

        CHECK([ov levelForRow: r] == levels[r], "%s: level of row %ld", what, (long) r);
        snprintf(label, sizeof label, "%s: outline column of row %ld", what, (long) r);
        CHECK_RECT([ov frameOfCellAtColumn: 0 row: r], ix + inset, rowY + iy, 200 - inset, rowH, label);
        snprintf(label, sizeof label, "%s: second column of row %ld", what, (long) r);
        CHECK_RECT([ov frameOfCellAtColumn: 1 row: r], 200 + sp.width + ix, rowY + iy, 120, rowH, label);
        snprintf(label, sizeof label, "%s: marker of row %ld", what, (long) r);
        if (expandable[r])
            CHECK_RECT([ov frameOfOutlineCellAtRow: r], 6 + levels[r] * per, rowY + iy, 12, sp.height > 0 ? rowH - 1 : rowH, label);
        else
            CHECK_RECT([ov frameOfOutlineCellAtRow: r], 0, 0, 0, 0, label);
        if (viewBased) {
            NSView *v = [ov viewAtColumn: 0 row: r makeIfNecessary: YES];

            snprintf(label, sizeof label, "%s: cell view of the outline column, row %ld", what, (long) r);
            CHECK_RECT([v frame], ix + inset, iy, 200 - inset, rowH, label);
        }
    }
    [ov release];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        source = [Source new];
        window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 300, 400, 200)
                                             styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: YES];

        NSSize spacings[] = {{3, 2}, {0, 0}, {10, 6}, {5, 3}, {7, 5}};
        const char *names[] = {"spacing 3,2", "spacing 0,0", "spacing 10,6", "spacing 5,3", "spacing 7,5"};
        for (int i = 0; i < 5; i++) {
            checkViewBased(spacings[i], names[i]);
            checkCellBased(spacings[i], names[i]);
            if (!laterSystem()) {
                checkOutline(spacings[i], 0, NO, names[i]);
                checkOutline(spacings[i], 0, YES, names[i]);
            }
        }
        if (!laterSystem()) {
            checkOutline(NSMakeSize(3, 2), 24, NO, "indentation 24");
            checkOutline(NSMakeSize(3, 2), 24, YES, "indentation 24");
            checkOutline(NSMakeSize(3, 2), 8, YES, "indentation 8");
        }

        printf(failures ? "FAIL\n" : "PASS\n");
    }
    return failures != 0;
}
