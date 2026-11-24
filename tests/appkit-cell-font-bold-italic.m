// Copyright (C) 2026 Lubos Dolezel
//
// The fontBold and fontItalic bindings of a table column reach its data cell by key-value coding.
// The contract is the Cocoa Bindings Reference for NSTableColumn
// (https://developer.apple.com/library/archive/documentation/Cocoa/Reference/CocoaBindingsRef/BindingsText/NSTableColumn.html):
// each binding is a Boolean that says whether the column's text is drawn bold (italic), a true
// value adding that attribute to the font. The constants NSFontBoldBinding and NSFontItalicBinding
// are in AppKit's NSKeyValueBinding.h.
// GUESS, marked in the implementation: NO takes the trait off the font again (the reference
// does not say; a column's data cell serves every row, so a row that is not bold must not keep
// the bold of the row before); a cell without a font is left alone
// (test_cell_without_font_is_left_alone). Pinned by black-box observation on macOS 26.7.3: YES gives the
// trait, NO and a missing value (nil) give a font without it, and NSNull raises
// NSInternalInconsistencyException (test_missing_and_null_values).
// The test needs a family with bold and italic faces, which the guest must have (Helvetica);
// the preconditions fail instead of skipping.
// Written from the documentation; not yet run in a guest.
// Build: clang -framework AppKit appkit-cell-font-bold-italic.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSFontTraitMask traits(NSCell *cell)
{
    return [[NSFontManager sharedFontManager] traitsOfFont:[cell font]];
}

static NSTextFieldCell *plainCell(void)
{
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"x"] autorelease];
    [cell setFont:[NSFont fontWithName:@"Helvetica" size:12]];
    CHECK([cell font] != nil);
    CHECK((traits(cell) & (NSBoldFontMask | NSItalicFontMask)) == 0);
    return cell;
}

static void test_bold_through_kvc(void)
{
    NSTextFieldCell *cell = plainCell();
    CHECK([[cell valueForKey:NSFontBoldBinding] boolValue] == NO);
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    CHECK(traits(cell) & NSBoldFontMask);
    CHECK((traits(cell) & NSItalicFontMask) == 0);
    CHECK([[cell valueForKey:NSFontBoldBinding] boolValue] == YES);
    CGFloat size = [[cell font] pointSize];
    CHECK(size == 12);
}

static void test_italic_through_kvc(void)
{
    NSTextFieldCell *cell = plainCell();
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontItalicBinding];
    CHECK(traits(cell) & NSItalicFontMask);
    CHECK((traits(cell) & NSBoldFontMask) == 0);
    CHECK([[cell valueForKey:NSFontItalicBinding] boolValue] == YES);
}

static void test_both_traits(void)
{
    NSTextFieldCell *cell = plainCell();
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontItalicBinding];
    CHECK((traits(cell) & (NSBoldFontMask | NSItalicFontMask)) == (NSBoldFontMask | NSItalicFontMask));
}

// GUESS (see the file comment): the data cell of a column is reused for every row
static void test_no_takes_the_trait_off_again(void)
{
    NSTextFieldCell *cell = plainCell();
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontItalicBinding];
    [cell setValue:[NSNumber numberWithBool:NO] forKey:NSFontBoldBinding];
    CHECK((traits(cell) & NSBoldFontMask) == 0);
    CHECK(traits(cell) & NSItalicFontMask); // the other trait stays
    [cell setValue:[NSNumber numberWithBool:NO] forKey:NSFontItalicBinding];
    CHECK((traits(cell) & (NSBoldFontMask | NSItalicFontMask)) == 0);
}

static void test_setting_the_same_value_changes_nothing(void)
{
    NSTextFieldCell *cell = plainCell();
    NSFont *before = [cell font];
    [cell setValue:[NSNumber numberWithBool:NO] forKey:NSFontBoldBinding];
    CHECK([[cell font] isEqual:before]);
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    NSFont *bold = [cell font];
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    CHECK([[cell font] isEqual:bold]);
}

static void test_cell_without_font_is_left_alone(void)
{
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"x"] autorelease];
    [cell setFont:nil];
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    CHECK([cell font] == nil);
    CHECK([[cell valueForKey:NSFontBoldBinding] boolValue] == NO);
}

// nil means no trait; NSNull raises NSInternalInconsistencyException (macOS 26.7.3)
static void test_missing_and_null_values(void)
{
    NSTextFieldCell *cell = plainCell();
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontBoldBinding];
    [cell setValue:nil forKey:NSFontBoldBinding];
    CHECK((traits(cell) & NSBoldFontMask) == 0);
    [cell setValue:[NSNumber numberWithBool:YES] forKey:NSFontItalicBinding];
    NSString *raised = nil;
    @try {
        [cell setValue:[NSNull null] forKey:NSFontItalicBinding];
    } @catch (NSException *e) {
        raised = [e name];
    }
    CHECK([raised isEqual:NSInternalInconsistencyException]);
    CHECK((traits(cell) & NSItalicFontMask) != 0);
}

// A string that reads as true, standing in for a controller marker (the markers are strings in Darling).
@interface TrueReadingMarker : NSString
@end
@implementation TrueReadingMarker
- (NSUInteger)length { return 3; }
- (unichar)characterAtIndex:(NSUInteger)index { return "YES"[index]; }
- (BOOL)boolValue { return YES; }
@end

// QUIRK (see bindingValueIsTrue in NSCell.m): strings read as -boolValue reads them, except those starting
// with "t" or "T"; observed on macOS 26.7.3 and 10.14.4 (probe p792). The controller markers give neither trait.
static void test_string_values(void)
{
    static const struct { const char *string; BOOL asksForTrait; } table[] = {
        { "YES", YES }, { "yes", YES }, { "1", YES }, { "2", YES }, { "-1", YES },
        { "NO", NO }, { "0", NO }, { "true", NO }, { "T", NO }, { "hello", NO }, { "", NO },
    };
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++) {
        NSTextFieldCell *row = plainCell();
        NSString *value = [NSString stringWithUTF8String:table[i].string];
        [row setValue:value forKey:NSFontBoldBinding];
        CHECK(((traits(row) & NSBoldFontMask) != 0) == table[i].asksForTrait);
        row = plainCell();
        [row setValue:value forKey:NSFontItalicBinding];
        CHECK(((traits(row) & NSItalicFontMask) != 0) == table[i].asksForTrait);
    }
    NSTextFieldCell *cell = plainCell();
    [cell setValue:@"YES" forKey:NSFontBoldBinding];
    CHECK((traits(cell) & NSBoldFontMask) != 0);
    [cell setValue:@"YES" forKey:NSFontItalicBinding];
    CHECK((traits(cell) & NSItalicFontMask) != 0);
    id markers[3] = { NSMultipleValuesMarker, NSNoSelectionMarker, NSNotApplicableMarker };
    for (int i = 0; i < 3; i++) {
        [cell setValue:@"YES" forKey:NSFontBoldBinding];
        [cell setValue:markers[i] forKey:NSFontBoldBinding];
        CHECK((traits(cell) & NSBoldFontMask) == 0);
    }
    // The check is by identity (NSIsControllerMarker), not by what the marker reads as: with a marker that
    // would read as true, the trait is still off. Darling's markers are strings, so the stand-in is one too.
    id saved = NSNoSelectionMarker;
    NSNoSelectionMarker = [[[TrueReadingMarker alloc] init] autorelease];
    [cell setValue:@"YES" forKey:NSFontBoldBinding];
    [cell setValue:NSNoSelectionMarker forKey:NSFontBoldBinding];
    CHECK((traits(cell) & NSBoldFontMask) == 0);
    NSNoSelectionMarker = saved;
}

// A column's data cell is prepared from the bound values of each row
static void test_column_binding(void)
{
    NSMutableArray *rows = [NSMutableArray array];
    for (NSNumber *bold in [NSArray arrayWithObjects:[NSNumber numberWithBool:YES], [NSNumber numberWithBool:NO], nil])
        [rows addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:@"x", @"name", bold, @"bold", nil]];
    NSArrayController *controller = [[[NSArrayController alloc] initWithContent:rows] autorelease];
    NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
    NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [[column dataCell] setFont:[NSFont fontWithName:@"Helvetica" size:12]];
    [table addTableColumn:column];
    [column bind:NSValueBinding toObject:controller withKeyPath:@"arrangedObjects.name" options:nil];
    [column bind:NSFontBoldBinding toObject:controller withKeyPath:@"arrangedObjects.bold" options:nil];
    [table reloadData];
    CHECK(traits([table preparedCellAtColumn:0 row:0]) & NSBoldFontMask);
    CHECK((traits([table preparedCellAtColumn:0 row:1]) & NSBoldFontMask) == 0);
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        test_bold_through_kvc();
        test_italic_through_kvc();
        test_both_traits();
        test_no_takes_the_trait_off_again();
        test_setting_the_same_value_changes_nothing();
        test_cell_without_font_is_left_alone();
        test_missing_and_null_values();
        test_string_values();
        test_column_binding();
    }
    if (failures)
        return 1;
    printf("ok\n");
    return 0;
}
