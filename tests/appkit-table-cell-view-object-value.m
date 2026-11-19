/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A view-based NSTableView sets the objectValue of a cell view that the
 * delegate makes to what the data source's
 * tableView:objectValueForTableColumn:row: returns for the cell, as the
 * NSTableViewDataSource documentation describes for view-based tables.
 * Observed on macOS 10.14.4 and 26.7.3 through the public API:
 * - the data source is asked after the delegate made the view, and its value
 *   replaces one the delegate set;
 * - a group row's view gets the value for a nil column;
 * - a view that does not take an object value (a plain NSView) is not given
 *   one, and the data source is not asked for it;
 * - after -reloadData the views are made and given their values again.
 * A text field in the cell view bound to "objectValue" of the cell view, as
 * cell views in nibs usually are, shows the value.
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
static int valueRequests;
static int plainValueRequests;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

@interface Source : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
	NSMutableArray *columnsAsked;
}
@end
@implementation Source
- (id)init
{
	if ((self = [super init]))
		columnsAsked = [[NSMutableArray alloc] init];
	return self;
}
- (void)dealloc
{
	[columnsAsked release];
	[super dealloc];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return 3;
}
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	valueRequests++;
	[columnsAsked addObject:column ? [column identifier] : @"(nil)"];
	return [NSString stringWithFormat:@"value %ld", (long) row];
}
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return row == 0;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	NSTableCellView *cellView = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 150, 17)] autorelease];
	NSTextField *field = [[[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 150, 17)] autorelease];
	[field setBordered:NO];
	[field setEditable:NO];
	[cellView addSubview:field];
	[cellView setTextField:field];
	[field bind:NSValueBinding toObject:cellView withKeyPath:@"objectValue" options:nil];
	// replaced by the data source's value
	[cellView setObjectValue:@"set by the delegate"];
	return cellView;
}
@end

// Cell views that take no object value.
@interface PlainSource : Source
@end
@implementation PlainSource
- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return NO;
}
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	plainValueRequests++;
	return @"unused";
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	return [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 150, 17)] autorelease];
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSTableView *makeTable(NSView *content, NSRect frame, id source)
{
	NSTableView *table = [[[NSTableView alloc] initWithFrame:frame] autorelease];
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
	[column setWidth:150];
	[table addTableColumn:column];
	[table setDelegate:source];
	[table setDataSource:source];
	[content addSubview:table];
	return table;
}

static void checkRow(NSTableView *table, NSInteger row, const char *what)
{
	NSTableCellView *view = [table viewAtColumn:0 row:row makeIfNecessary:NO];
	NSString *expected = [NSString stringWithFormat:@"value %ld", (long) row];
	BOOL valueOK = [[view objectValue] isEqual:expected];
	BOOL fieldOK = [[[view textField] stringValue] isEqual:expected];
	printf("%s %s row %ld: objectValue '%s', text field '%s'\n", valueOK && fieldOK ? "PASS" : "FAIL", what,
	       (long) row, [[[view objectValue] description] UTF8String],
	       [[[view textField] stringValue] UTF8String]);
	if (!valueOK || !fieldOK)
		failures++;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 200)
		                                               styleMask:NSWindowStyleMaskTitled
		                                                 backing:NSBackingStoreBuffered
		                                                   defer:NO];
		NSView *content = [window contentView];
		Source *source = [[[Source alloc] init] autorelease];
		NSTableView *table = makeTable(content, NSMakeRect(0, 0, 160, 200), source);
		PlainSource *plainSource = [[[PlainSource alloc] init] autorelease];
		makeTable(content, NSMakeRect(200, 0, 160, 200), plainSource);
		[window orderFront:nil];
		[window display];
		spin(0.5);

		for (NSInteger row = 0; row < 3; row++)
			checkRow(table, row, "cell view");
		expect([source->columnsAsked containsObject:@"(nil)"], "the group row's value is asked for no column");
		expect([source->columnsAsked containsObject:@"name"], "the other rows' values are asked for their column");
		expect(plainValueRequests == 0, "the data source is not asked for views without an object value");

		int before = valueRequests;
		[table reloadData];
		[window display];
		spin(0.3);
		expect(valueRequests > before, "the values are asked again after reloadData");
		for (NSInteger row = 0; row < 3; row++)
			checkRow(table, row, "cell view after reloadData");

		[window orderOut:nil];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
