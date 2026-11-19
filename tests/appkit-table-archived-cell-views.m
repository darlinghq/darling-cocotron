/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSTableView makeViewWithIdentifier:owner:] makes the cell views that were
 * laid out in a view-based table in Interface Builder (a table column's
 * prototype cell views), as the method's documentation describes, when the
 * table comes from a nib.
 *
 * Loads fixtures/nibarchive/flat/CellViews.nib (ibtool-compiled from
 * fixtures/nibarchive/src/CellViews.xib): a window with a view-based table
 * whose column has a prototype NSTableCellView with the identifier
 * "nameCell" and a text field bound to the cell view's objectValue. The
 * owner is the table's data source and delegate and makes its cell views with
 * makeViewWithIdentifier:owner:. The test checks that
 * - each row gets an NSTableCellView with that identifier and its text field,
 *   a new one per row;
 * - the text field shows the object value the owner sets;
 * - an identifier the table does not know gives nil.
 * It also passes on macOS 26.7.3 (macOS 10.14.4 does not load this
 * NIBArchive through -initWithNibData:bundle:).
 *
 * Usage: appkit-table-archived-cell-views <fixtures/nibarchive directory>
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
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

@interface CellViewsOwner : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
@public
	NSWindow *window;
	NSTableView *table;
	NSMutableArray *made;
}
@end

@implementation CellViewsOwner
- (id)init
{
	if ((self = [super init]))
		made = [[NSMutableArray alloc] init];
	return self;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return 2;
}
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	NSTableCellView *view = [tableView makeViewWithIdentifier:@"nameCell" owner:self];
	[view setObjectValue:[NSString stringWithFormat:@"item %ld", (long) row]];
	if (view != nil)
		[made addObject:view];
	return view;
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		if (argc < 2) {
			fprintf(stderr, "usage: %s <fixtures/nibarchive>\n", argv[0]);
			return 2;
		}
		[NSApplication sharedApplication];
		NSString *path = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"flat/CellViews.nib"];
		NSData *data = [NSData dataWithContentsOfFile:path];
		if (data == nil) {
			printf("FAIL cannot read %s\n", [path UTF8String]);
			return 1;
		}
		NSNib *nib = [[[NSNib alloc] initWithNibData:data bundle:nil] autorelease];
		CellViewsOwner *owner = [[CellViewsOwner alloc] init];
		NSArray *topLevelObjects = nil;
		BOOL loaded = [nib instantiateWithOwner:owner topLevelObjects:&topLevelObjects];
		expect(loaded && owner->table != nil && owner->window != nil, "the nib loads with its table");
		if (!loaded || owner->table == nil) {
			printf("FAIL\n");
			return 1;
		}

		[owner->window orderFront:nil];
		[owner->window display];
		spin(0.5);

		for (NSInteger row = 0; row < 2; row++) {
			NSTableCellView *view = [owner->table viewAtColumn:0 row:row makeIfNecessary:YES];
			NSString *expected = [NSString stringWithFormat:@"item %ld", (long) row];
			BOOL ok = [view isKindOfClass:[NSTableCellView class]] && [[view identifier] isEqual:@"nameCell"] &&
			          [view textField] != nil;
			printf("%s row %ld has the nib's cell view: %s, identifier '%s', text field %p\n", ok ? "PASS" : "FAIL",
			       (long) row, view ? object_getClassName(view) : "nil", [[view identifier] UTF8String],
			       [view textField]);
			if (!ok)
				failures++;
			ok = [[[view textField] stringValue] isEqual:expected];
			printf("%s row %ld text field shows '%s' (expected '%s')\n", ok ? "PASS" : "FAIL", (long) row,
			       [[[view textField] stringValue] UTF8String], [expected UTF8String]);
			if (!ok)
				failures++;
		}
		expect([owner->made count] >= 2 && [owner->made objectAtIndex:0] != [owner->made objectAtIndex:1],
		       "each row gets a view of its own");
		expect([owner->table makeViewWithIdentifier:@"noSuchCell" owner:owner] == nil,
		       "an unknown identifier gives nil");
		[owner->window orderOut:nil];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
