// Copyright (C) 2026 Lubos Dolezel
//
// Value transformers on a table column's value binding. The contract is the documentation of
// NSValueTransformerNameBindingOption and NSValueTransformerBindingOption
// (https://developer.apple.com/documentation/appkit/nsbindingoption/valuetransformername,
// https://developer.apple.com/documentation/appkit/nsbindingoption/valuetransformer): the
// transformer is applied to the bound value; and of -[NSValueTransformer reverseTransformedValue:]
// (https://developer.apple.com/documentation/foundation/valuetransformer/reversetransformedvalue(_:)),
// which a transformer that cannot reverse refuses (it raises). The cell of a bound column shows the
// transformed value, and what the user enters is reverse transformed before it is stored in the
// model. A transformer that cannot reverse makes the column read-only instead of raising
// (test_irreversible_transformer_is_read_only): pinned by black-box observation on macOS 26.7.3 and 10.14.4,
// where such a column stays editable but no row reports editable, no editor starts and the model is unchanged.
// -_binderForBinding:create: and -applyFromCell:inRow: are not public; the test calls them because
// there is no public call that ends an edit without a user (test_write_back).
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-table-column-value-transformers.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Row : NSObject {
    NSString *_name;
}
@property(nonatomic, copy) NSString *name;
@end

@implementation Row
@synthesize name = _name;
@end

@interface Model : NSObject {
    NSArray *_rows;
}
@property(nonatomic, retain) NSArray *rows;
@end

@implementation Model
@synthesize rows = _rows;
@end

@interface Upper : NSValueTransformer
@end
@implementation Upper
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return YES; }
- (id)transformedValue:(id)value { return [(NSString *)value uppercaseString]; }
- (id)reverseTransformedValue:(id)value { return [(NSString *)value lowercaseString]; }
@end

@interface OneWay : NSValueTransformer
@end
@implementation OneWay
+ (Class)transformedValueClass { return [NSString class]; }
+ (BOOL)allowsReverseTransformation { return NO; }
- (id)transformedValue:(id)value { return [NSString stringWithFormat:@"<%@>", value]; }
@end

@interface NSObject (PrivateBinding)
- (id)_binderForBinding:(id)binding create:(BOOL)create;
@end
@interface NSObject (PrivateBinder)
- (void)applyFromCell:(id)cell inRow:(NSInteger)row;
- (BOOL)allowsEditingForRow:(NSInteger)row;
@end

static Model *model;
static NSTableView *table;

static void setup(NSDictionary *options)
{
    model = [[Model alloc] init];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSString *name in [NSArray arrayWithObjects:@"alpha", @"beta", nil])
    {
        Row *row = [[[Row alloc] init] autorelease];
        [row setName:name];
        [rows addObject:row];
    }
    [model setRows:rows];

    table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:200];
    [table addTableColumn:column];
    [column bind:@"value" toObject:model withKeyPath:@"rows.name" options:options];
    [table reloadData];
}

static NSTableColumn *column(void) { return [[table tableColumns] objectAtIndex:0]; }

static id shown(NSInteger row) { return [[table preparedCellAtColumn:0 row:row] objectValue]; }

static NSString *stored(NSInteger row) { return [[[model rows] objectAtIndex:row] name]; }

static void test_no_transformer(void)
{
    setup(nil);
    CHECK([shown(0) isEqual:@"alpha"]);
}

static void test_named_transformer_is_applied(void)
{
    [NSValueTransformer setValueTransformer:[[[Upper alloc] init] autorelease] forName:@"Appkit.Upper"];
    setup([NSDictionary dictionaryWithObject:@"Appkit.Upper" forKey:NSValueTransformerNameBindingOption]);
    CHECK([shown(0) isEqual:@"ALPHA"]);
    CHECK([shown(1) isEqual:@"BETA"]);
}

static void test_transformer_instance_is_applied(void)
{
    setup([NSDictionary dictionaryWithObject:[[[Upper alloc] init] autorelease] forKey:NSValueTransformerBindingOption]);
    CHECK([shown(1) isEqual:@"BETA"]);
}

static void test_write_back(void)
{
    setup([NSDictionary dictionaryWithObject:[[[Upper alloc] init] autorelease] forKey:NSValueTransformerBindingOption]);
    NSCell *cell = [table preparedCellAtColumn:0 row:1];
    [cell setObjectValue:@"GAMMA"];
    [[column() _binderForBinding:@"value" create:NO] applyFromCell:cell inRow:1];
    CHECK([stored(1) isEqual:@"gamma"]); // reverse transformed
    CHECK([stored(0) isEqual:@"alpha"]);
}

// (see the file comment, observed on macOS): not reversible means read-only
static void test_irreversible_transformer_is_read_only(void)
{
    setup([NSDictionary dictionaryWithObject:[[[OneWay alloc] init] autorelease] forKey:NSValueTransformerBindingOption]);
    CHECK([shown(0) isEqual:@"<alpha>"]);
    id binder = [column() _binderForBinding:@"value" create:NO];
    CHECK(![binder allowsEditingForRow:0]);
    NSCell *cell = [table preparedCellAtColumn:0 row:0];
    [cell setObjectValue:@"changed"];
    [binder applyFromCell:cell inRow:0];
    CHECK([stored(0) isEqual:@"alpha"]);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_no_transformer();
        test_named_transformer_is_applied();
        test_transformer_instance_is_applied();
        test_write_back();
        test_irreversible_transformer_is_read_only();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
