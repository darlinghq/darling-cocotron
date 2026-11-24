// Copyright (C) 2026 Lubos Dolezel
//
// An exception raised while a column's bindings are applied to its data cell reaches the caller of
// -[NSTableView preparedCellAtColumn:row:] (https://developer.apple.com/documentation/appkit/nstableview/preparedcell(atcolumn:row:),
// which says nothing about errors).
// Observed on macOS 26.1 arm64, one Mac, black-box probe 661 cases 18, 25 and 30 (plain key-value-coding source
// returning the whole key, not one value per row): a getter that throws NSGenericException, and NSNull in a BOOL
// binding (NSInternalInconsistencyException, "Cannot create BOOL from object null of class NSNull"), were raised
// out of preparedCellAtColumn:row: on both calls made (row 0, then row 1), and the column was unchanged afterwards
// (hidden=0 editable=1 numberOfColumns=1). Those are the pinned checks (marked "observed" below).
// Everything marked "inferred" comes from this implementation's design, not from the Mac: the per-row source
// (rows.fontBold), row 1 preparing normally when only row 0 is bad, numberOfRows being 2 (the Mac reported 0 for
// its source), and recovery once the value is fixed.
// Not covered: an NSArrayController source (there the process ended in the run-loop turn after reloadData;
// propagation is only inferred and the termination is not copied) and the editable binding of case 25 (this test
// uses fontBold, which takes the same path and raises the same exception in this implementation).
// The table is never displayed and the run loop never runs.
// Written from the observations; not yet run in a guest or on a Mac.
// Build: clang -framework AppKit appkit-table-column-binding-exceptions.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Row : NSObject {
    NSString *_name;
    id _fontBold;
    BOOL _raises;
}
@property(nonatomic, copy) NSString *name;
@property(nonatomic, retain) id fontBold;
@property(nonatomic, assign) BOOL raises;
@end

@implementation Row
@synthesize name = _name;
@synthesize fontBold = _fontBold;
@synthesize raises = _raises;

- (id)valueForKey:(NSString *)key
{
    if (_raises && [key isEqualToString:@"fontBold"])
        [NSException raise:NSGenericException format:@"getter raised for key %@", key];
    return [super valueForKey:key];
}
@end

@interface Model : NSObject {
    NSArray *_rows;
}
@property(nonatomic, retain) NSArray *rows;
@end

@implementation Model
@synthesize rows = _rows;
@end

static Model *model;
static NSTableView *table;
static NSTableColumn *column;

// Two rows; row 0 carries the bad value, row 1 is valid. The raising switch is turned on after the bindings
// are made, so that only the preparation of a cell can raise.
static void setup(id firstFontBold)
{
    model = [[[Model alloc] init] autorelease];
    NSMutableArray *rows = [NSMutableArray array];
    NSInteger i = 0;
    for (NSString *name in [NSArray arrayWithObjects:@"alpha", @"beta", nil])
    {
        Row *row = [[[Row alloc] init] autorelease];
        [row setName:name];
        [row setFontBold:(i++ == 0 ? firstFontBold : [NSNumber numberWithBool:YES])];
        [rows addObject:row];
    }
    [model setRows:rows];

    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)] autorelease];
    column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:200];
    [table addTableColumn:column];
    [column bind:@"value" toObject:model withKeyPath:@"rows.name" options:nil];
    [column bind:NSFontBoldBinding toObject:model withKeyPath:@"rows.fontBold" options:nil];
    [table reloadData];
}

static NSString *raisedBy(NSInteger row, NSString **reason)
{
    @try
    {
        [table preparedCellAtColumn:0 row:row];
    }
    @catch (NSException *e)
    {
        if (reason)
            *reason = [e reason];
        return [e name];
    }
    return nil;
}

static void check_column_unchanged(void)
{
    // observed (cases 18, 25): numberOfColumns=1, hidden=0 after the raises
    CHECK([table numberOfColumns] == 1);
    CHECK(![column isHidden]);
}

static void check_other_row_prepares(void)
{
    // inferred, not observed: here only row 0 is bad, the Mac's source was bad for every row
    CHECK([table numberOfRows] == 2);
    CHECK(raisedBy(1, NULL) == nil);
    CHECK([[[table preparedCellAtColumn:0 row:1] objectValue] isEqual:@"beta"]);
}

// probe 661 case 18: NSGenericException from a getter, raised on two successive calls (observed)
static void test_raising_getter_propagates(void)
{
    setup([NSNumber numberWithBool:YES]);
    CHECK(raisedBy(0, NULL) == nil);
    [[[model rows] objectAtIndex:0] setRaises:YES];

    NSString *reason = nil;
    CHECK([raisedBy(0, &reason) isEqual:NSGenericException]);
    CHECK([reason isEqual:@"getter raised for key fontBold"]);
    CHECK([raisedBy(0, NULL) isEqual:NSGenericException]);
    check_column_unchanged();
    check_other_row_prepares();

    // inferred: recovery once the getter stops throwing
    [[[model rows] objectAtIndex:0] setRaises:NO];
    CHECK(raisedBy(0, NULL) == nil);
    CHECK([[[table preparedCellAtColumn:0 row:0] objectValue] isEqual:@"alpha"]);
}

// probe 661 case 25: NSNull in a BOOL binding, raised on two successive calls (observed)
static void test_null_in_bool_binding_propagates(void)
{
    setup([NSNull null]);

    NSString *reason = nil;
    CHECK([raisedBy(0, &reason) isEqual:NSInternalInconsistencyException]);
    CHECK([reason hasPrefix:@"Cannot create BOOL from object"]);
    CHECK([raisedBy(0, NULL) isEqual:NSInternalInconsistencyException]);
    check_column_unchanged();
    check_other_row_prepares();

    // inferred: recovery once the value is valid
    [[[model rows] objectAtIndex:0] setFontBold:[NSNumber numberWithBool:NO]];
    CHECK(raisedBy(0, NULL) == nil);
    CHECK([[[table preparedCellAtColumn:0 row:0] objectValue] isEqual:@"alpha"]);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_raising_getter_propagates();
        test_null_in_bool_binding_propagates();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
