// Copyright (C) 2026 Lubos Dolezel
//
// NSTableView drop retargeting. The contract is the documentation of
// -[NSTableView setDropRow:dropOperation:]
// (https://developer.apple.com/documentation/appkit/nstableview/setdroprow(_:dropoperation:)) and
// of the data source method tableView:validateDrop:proposedRow:proposedDropOperation:
// (https://developer.apple.com/documentation/appkit/nstableviewdatasource/tableview(_:validatedrop:proposedrow:proposeddropoperation:)):
//  - the data source may retarget the proposed drop by calling setDropRow:dropOperation: while
//    validating, and returns the NSDragOperation it will perform;
//  - row 1 with NSTableViewDropOn is a drop on the second row, row numberOfRows with
//    NSTableViewDropAbove is a drop below the last row, row -1 with NSTableViewDropOn is a drop
//    on the whole table.
// The row and operation acceptDrop receives are the ones left after validation (the only
// reading the documentation allows; test_accept_receives_the_retargeted_drop). Beyond the
// documentation, pinned by black-box observation on macOS 26.7.3 and 10.14.4: the table proposes a drop on the
// row when the pointer is in the middle of it and above the row (or above the next one) near its edges
// (test_the_proposal), and a drop forced on a data source without validateDrop reaches acceptDrop with row -2
// and NSTableViewDropOn (test_quirk_drop_without_validate_drop; the drag itself is refused).
// Build: clang -framework AppKit appkit-table-set-drop-row.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *const DropType = @"org.example.table-set-drop-row";

// Only what the table reads from a dragging info
@interface FakeInfo : NSObject {
@public
    NSPoint location;
    NSPasteboard *board;
}
@end

@implementation FakeInfo
- (NSPoint)draggingLocation { return location; }
- (NSPasteboard *)draggingPasteboard { return board; }
@end

@interface Source : NSObject <NSTableViewDataSource> {
@public
    BOOL implementsValidate;
    NSInteger retargetRow;
    NSTableViewDropOperation retargetOperation;
    BOOL retarget;
    NSDragOperation answer;
    NSInteger proposedRow, acceptedRow;
    NSTableViewDropOperation proposedOperation, acceptedOperation;
    int accepts;
}
@end

@implementation Source
- (BOOL)respondsToSelector:(SEL)selector
{
    if (!implementsValidate && selector == @selector(tableView:validateDrop:proposedRow:proposedDropOperation:))
        return NO;
    return [super respondsToSelector:selector];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 5; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)row
{
    return [NSString stringWithFormat:@"row %ld", (long)row];
}
- (NSDragOperation)tableView:(NSTableView *)t validateDrop:(id<NSDraggingInfo>)info proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    proposedRow = row;
    proposedOperation = operation;
    if (retarget)
        [t setDropRow:retargetRow dropOperation:retargetOperation];
    return answer;
}
- (BOOL)tableView:(NSTableView *)t acceptDrop:(id<NSDraggingInfo>)info row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
    accepts++;
    acceptedRow = row;
    acceptedOperation = operation;
    return YES;
}
@end

static NSWindow *window;
static NSTableView *table;
static FakeInfo *info;

// The table is the destination of the drag; the protocol methods are not in its header
static id<NSDraggingDestination> dest(void) { return (id<NSDraggingDestination>)table; }

static Source *setup(BOOL implementsValidate)
{
    [window close];
    window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 250) styleMask:NSBorderlessWindowMask
                                           backing:NSBackingStoreBuffered defer:NO];
    [window setReleasedWhenClosed:NO];
    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 400, 250)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:300];
    [table addTableColumn:column];
    Source *source = [[[Source alloc] init] autorelease];
    source->implementsValidate = implementsValidate;
    source->answer = NSDragOperationMove;
    [table setDataSource:source];
    [table registerForDraggedTypes:[NSArray arrayWithObject:DropType]];
    [window setContentView:table];
    [table reloadData];

    info = [[[FakeInfo alloc] init] autorelease];
    info->board = [NSPasteboard pasteboardWithUniqueName];
    [info->board declareTypes:[NSArray arrayWithObject:DropType] owner:nil];
    return source;
}

// The pointer at a fraction of a row's height from its top edge, in window coordinates
static void pointAtRowFraction(NSInteger row, CGFloat fraction)
{
    NSRect cell = [table frameOfCellAtColumn:0 row:row];
    CGFloat y = [table isFlipped] ? NSMinY(cell) + fraction * NSHeight(cell) : NSMaxY(cell) - fraction * NSHeight(cell);
    info->location = [table convertPoint:NSMakePoint(NSMidX(cell), y) toView:nil];
}

// The pointer in the middle of a row
static void pointAtRow(NSInteger row)
{
    pointAtRowFraction(row, 0.5);
}

static void test_the_proposal(void)
{
    Source *source = setup(YES);
    pointAtRow(3);
    NSDragOperation result = [dest() draggingEntered:(id<NSDraggingInfo>)info];
    CHECK(source->proposedRow == 3);
    CHECK(source->proposedOperation == NSTableViewDropOn); // the middle of a row is a drop on it
    CHECK(result == NSDragOperationMove); // the data source's operation, not a flag

    pointAtRowFraction(3, 0.02);
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK(source->proposedRow == 3 && source->proposedOperation == NSTableViewDropAbove);
    pointAtRowFraction(3, 0.98);
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK(source->proposedRow == 4 && source->proposedOperation == NSTableViewDropAbove);

    // Below the last row: above the end of the table.
    NSRect last = [table frameOfCellAtColumn:0 row:4];
    info->location = [table convertPoint:NSMakePoint(NSMidX(last), NSMaxY(last) + 40) toView:nil];
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK(source->proposedRow == 5 && source->proposedOperation == NSTableViewDropAbove);
}

static void test_returned_operation_is_passed_on(void)
{
    Source *source = setup(YES);
    pointAtRow(1);
    source->answer = NSDragOperationLink;
    CHECK([dest() draggingEntered:(id<NSDraggingInfo>)info] == NSDragOperationLink);
    source->answer = NSDragOperationNone;
    CHECK([dest() draggingUpdated:(id<NSDraggingInfo>)info] == NSDragOperationNone);
}

static void test_accept_receives_the_retargeted_drop(void)
{
    Source *source = setup(YES);
    pointAtRow(3);
    source->retarget = YES;
    source->retargetRow = 1;
    source->retargetOperation = NSTableViewDropOn;
    CHECK([dest() draggingUpdated:(id<NSDraggingInfo>)info] == NSDragOperationMove);
    CHECK([dest() prepareForDragOperation:(id<NSDraggingInfo>)info]);
    CHECK([dest() performDragOperation:(id<NSDraggingInfo>)info]);
    CHECK(source->accepts == 1);
    CHECK(source->acceptedRow == 1);
    CHECK(source->acceptedOperation == NSTableViewDropOn);
}

static void test_drop_below_the_last_row(void)
{
    Source *source = setup(YES);
    pointAtRow(0);
    source->retarget = YES;
    source->retargetRow = [table numberOfRows];
    source->retargetOperation = NSTableViewDropAbove;
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK([dest() performDragOperation:(id<NSDraggingInfo>)info]);
    CHECK(source->acceptedRow == 5);
    CHECK(source->acceptedOperation == NSTableViewDropAbove);
}

static void test_drop_on_the_whole_table(void)
{
    Source *source = setup(YES);
    pointAtRow(2);
    source->retarget = YES;
    source->retargetRow = -1;
    source->retargetOperation = NSTableViewDropOn;
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    [window displayIfNeeded]; // the table highlights itself; must not trip on row -1
    CHECK([dest() performDragOperation:(id<NSDraggingInfo>)info]);
    CHECK(source->acceptedRow == -1);
    CHECK(source->acceptedOperation == NSTableViewDropOn);
}

static void test_without_retarget_the_proposal_is_accepted(void)
{
    Source *source = setup(YES);
    pointAtRow(4);
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK([dest() performDragOperation:(id<NSDraggingInfo>)info]);
    CHECK(source->acceptedRow == 4);
    CHECK(source->acceptedOperation == NSTableViewDropOn);
}

static void test_each_update_starts_from_a_fresh_proposal(void)
{
    Source *source = setup(YES);
    pointAtRow(3);
    source->retarget = YES;
    source->retargetRow = 0;
    source->retargetOperation = NSTableViewDropOn;
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    source->retarget = NO;
    pointAtRow(2);
    [dest() draggingUpdated:(id<NSDraggingInfo>)info];
    CHECK(source->proposedRow == 2);
    CHECK(source->proposedOperation == NSTableViewDropOn);
}

// The drag is refused without validateDrop (nothing to perform), and a drop forced on the table reaches acceptDrop
// with row -2 and NSTableViewDropOn (black-box observation on macOS 26.7.3 and 10.14.4)
static void test_quirk_drop_without_validate_drop(void)
{
    Source *source = setup(NO);
    pointAtRow(2);
    CHECK([dest() draggingEntered:(id<NSDraggingInfo>)info] == NSDragOperationNone);
    CHECK([dest() draggingUpdated:(id<NSDraggingInfo>)info] == NSDragOperationNone);
    CHECK(source->accepts == 0);
    CHECK([dest() performDragOperation:(id<NSDraggingInfo>)info]);
    CHECK(source->accepts == 1);
    CHECK(source->acceptedRow == -2);
    CHECK(source->acceptedOperation == NSTableViewDropOn);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_the_proposal();
        test_returned_operation_is_passed_on();
        test_accept_receives_the_retargeted_drop();
        test_drop_below_the_last_row();
        test_drop_on_the_whole_table();
        test_without_retarget_the_proposal_is_accepted();
        test_each_update_starts_from_a_fresh_proposal();
        test_quirk_drop_without_validate_drop();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
