/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A view-based NSOutlineView, whose delegate makes cell views with
 * outlineView:viewForTableColumn:item:, shows those views (the documented
 * NSOutlineViewDelegate contract). Observed on macOS 10.14.4 and 26.7.3
 * through the public API, and checked here:
 * - every visible cell gets a view from the delegate once the outline view is
 *   drawn; a group item (outlineView:isGroupItem:) gets one view for the
 *   whole row, asked for with no column, and no view in the other columns;
 * - the view of the outline column starts where frameOfCellAtColumn:row:
 *   does, so a child item's view is indented by indentationPerLevel;
 * - a cell view's object value is what the data source's
 *   outlineView:objectValueForTableColumn:byItem: returns, asked after the
 *   view was made (a data source without that method leaves it as the
 *   delegate set it);
 * - after collapsing and expanding an item, the rows show the views of the
 *   items now in them.
 * It also passes on macOS 26.7.3 and 10.14.4.
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

// Items: "top", and the group "G" with the children "c1" and "c2".
@interface Items : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate> {
@public
	NSMutableArray *asked;
}
@end
@implementation Items
- (id)init
{
	if ((self = [super init]))
		asked = [[NSMutableArray alloc] init];
	return self;
}
- (void)dealloc
{
	[asked release];
	[super dealloc];
}
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (item == nil)
		return 2;
	return [item isEqual:@"G"] ? 2 : 0;
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (item == nil)
		return index ? @"G" : @"top";
	return index ? @"c2" : @"c1";
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	return [item isEqual:@"G"];
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item
{
	return [item isEqual:@"G"];
}
- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)column item:(id)item
{
	[asked addObject:[NSString stringWithFormat:@"%@/%@", item, column ? [column identifier] : @"-"]];
	NSTableCellView *view = [[[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 50, 17)] autorelease];
	[view setObjectValue:[@"delegate-" stringByAppendingString:item]];
	return view;
}
@end

@interface ValueItems : Items
@end
@implementation ValueItems
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	return [@"value-" stringByAppendingString:item];
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static NSOutlineView *makeOutline(NSWindow *window, Items *items)
{
	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)] autorelease];
	NSOutlineView *outline = [[[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 300, 300)] autorelease];
	NSTableColumn *name = [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
	[name setWidth:180];
	[outline addTableColumn:name];
	[outline setOutlineTableColumn:name];
	NSTableColumn *other = [[[NSTableColumn alloc] initWithIdentifier:@"other"] autorelease];
	[other setWidth:60];
	[outline addTableColumn:other];
	[outline setIndentationPerLevel:16];
	[outline setDelegate:items];
	[outline setDataSource:items];
	[scroll setDocumentView:outline];
	[[window contentView] addSubview:scroll];
	[outline expandItem:nil expandChildren:YES];
	[window display];
	spin(0.5);
	return outline;
}

static NSInteger rowOf(NSOutlineView *outline, NSString *item)
{
	for (NSInteger row = 0; row < [outline numberOfRows]; row++)
		if ([[outline itemAtRow:row] isEqual:item])
			return row;
	return -1;
}

static void checkValues(NSOutlineView *outline, NSString *prefix, const char *when)
{
	char what[256];
	for (NSString *item in @[@"top", @"G", @"c1", @"c2"]) {
		NSInteger row = rowOf(outline, item);
		NSTableCellView *view = row < 0 ? nil : [outline viewAtColumn:0 row:row makeIfNecessary:NO];
		NSString *expected = [prefix stringByAppendingString:item];
		snprintf(what, sizeof what, "%s: the view of %s has the object value '%s' (got '%s')", when,
		         [item UTF8String], [expected UTF8String], [[[view objectValue] description] UTF8String]);
		expect([[view objectValue] isEqual:expected], what);
	}
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 300)
		                                               styleMask:NSWindowStyleMaskTitled
		                                                 backing:NSBackingStoreBuffered
		                                                   defer:NO];
		[window orderFront:nil];

		Items *items = [[[Items alloc] init] autorelease];
		NSOutlineView *outline = makeOutline(window, items);
		expect([outline numberOfRows] == 4, "all four items are rows");
		expect([items->asked containsObject:@"G/-"], "the group item's view is asked for with no column");
		expect(![items->asked containsObject:@"G/name"] && ![items->asked containsObject:@"G/other"],
		       "the group item's view is not asked for per column");
		expect([items->asked containsObject:@"c1/name"] && [items->asked containsObject:@"c1/other"],
		       "a child item's views are asked for every column");

		NSInteger topRow = rowOf(outline, @"top"), childRow = rowOf(outline, @"c1"), groupRow = rowOf(outline, @"G");
		NSView *topView = [outline viewAtColumn:0 row:topRow makeIfNecessary:NO];
		NSView *childView = [outline viewAtColumn:0 row:childRow makeIfNecessary:NO];
		expect([topView isKindOfClass:[NSTableCellView class]] && [childView isKindOfClass:[NSTableCellView class]],
		       "the rows show the delegate's views");
		expect([outline viewAtColumn:0 row:groupRow makeIfNecessary:NO] != nil &&
		               [outline viewAtColumn:1 row:groupRow makeIfNecessary:NO] == nil,
		       "the group row has one view, in the first column");

		CGFloat topX = NSMinX([topView frame]), childX = NSMinX([childView frame]);
		CGFloat cellX = NSMinX([outline frameOfCellAtColumn:0 row:childRow]);
		char what[256];
		snprintf(what, sizeof what, "a child's view starts at its cell (%g, cell %g) and is indented by %g from its parent level (%g)",
		         childX, cellX, [outline indentationPerLevel], childX - topX);
		expect(fabs(childX - cellX) < 0.5 && fabs(childX - topX - [outline indentationPerLevel]) < 0.5, what);
		checkValues(outline, @"delegate-", "without an object value method");

		[[outline enclosingScrollView] removeFromSuperview];
		ValueItems *valueItems = [[[ValueItems alloc] init] autorelease];
		outline = makeOutline(window, valueItems);
		checkValues(outline, @"value-", "with an object value method");

		[outline collapseItem:@"G"];
		[window display];
		spin(0.3);
		expect([outline numberOfRows] == 2, "collapsing the group leaves two rows");
		[outline expandItem:@"G"];
		[window display];
		spin(0.3);
		checkValues(outline, @"value-", "after collapsing and expanding");

		[window orderOut:nil];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
