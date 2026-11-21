/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSOutlineView setDataSource:] takes the data source it is given. A data
 * source of a view-based outline view need not implement
 * outlineView:objectValueForTableColumn:byItem: (its delegate gives the cell
 * views), and one that implements only some of the item methods is set as
 * well; neither raises. Observed on macOS 10.14.4 and 26.7.3 through the
 * public API (10.14.4 logs a message for the incomplete one).
 *
 * The test sets
 * - a data source with the three item methods and no object value method: it
 *   is the data source and its two items are the outline view's rows;
 * - a data source with only outlineView:numberOfChildrenOfItem:: it is the
 *   data source, nothing raises and the outline view does not ask it for
 *   items it cannot give;
 * - the first one again in a nib-like way, through the "dataSource" outlet
 *   key (setValue:forKey:), which is how a nib connects it.
 *
 * No display needed. No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

// The item methods only, as for a view-based outline view.
@interface ItemSource : NSObject
@end
@implementation ItemSource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return item == nil ? 2 : 0;
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	return index == 0 ? @"first" : @"second";
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return NO;
}
@end

@interface CountOnlySource : NSObject
@end
@implementation CountOnlySource
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	return item == nil ? 1 : 0;
}
@end

static NSOutlineView *makeOutlineView(void)
{
	NSOutlineView *outlineView = [[[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
	[outlineView addTableColumn:column];
	[outlineView setOutlineTableColumn:column];
	return outlineView;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		ItemSource *items = [[[ItemSource alloc] init] autorelease];
		NSOutlineView *outlineView = makeOutlineView();
		BOOL raised = NO;
		@try {
			[outlineView setDataSource:(id) items];
		} @catch (NSException *e) {
			raised = YES;
			printf("setDataSource: raised %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
		}
		expect(!raised, "a data source without an object value method does not raise");
		expect([outlineView dataSource] == (id) items, "a data source without an object value method is set");
		[outlineView reloadData];
		expect([outlineView numberOfRows] == 2, "its items are the rows");
		expect([[outlineView itemAtRow:1] isEqual:@"second"], "the second row is its second item");

		CountOnlySource *countOnly = [[[CountOnlySource alloc] init] autorelease];
		NSOutlineView *partial = makeOutlineView();
		raised = NO;
		@try {
			[partial setDataSource:(id) countOnly];
			[partial reloadData];
			[partial numberOfRows];
		} @catch (NSException *e) {
			raised = YES;
			printf("incomplete data source raised %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
		}
		expect(!raised, "an incomplete data source does not raise");
		expect([partial dataSource] == (id) countOnly, "an incomplete data source is set");

		NSOutlineView *connected = makeOutlineView();
		raised = NO;
		@try {
			[connected setValue:items forKey:@"dataSource"];
		} @catch (NSException *e) {
			raised = YES;
		}
		expect(!raised && [connected dataSource] == (id) items, "the dataSource outlet connects it");
		expect([connected numberOfRows] == 2, "the connected outline view has its rows");
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
