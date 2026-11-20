/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The part widths of NSMenuItemCell: -stateImageWidth, -imageWidth,
 * -titleWidth and -keyEquivalentWidth, for a menu item cell and for a pop-up
 * button cell, whose menu item is the item it shows (-menuItem). Expected
 * values are what macOS 26.7.3 returns through the public API: no menu item
 * (a pop-up cell made with an empty title has no items)
 * gives 0 for each; with an item the state column is 18 points, the image
 * width is the image's, the title width is the title's width in the cell's
 * font plus 4, and a cell outside a menu has no key equivalent width.
 *
 * No display needed. No ARC. Prints PASS/FAIL lines.
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

static BOOL near(CGFloat a, CGFloat b)
{
	return fabs(a - b) < 0.01;
}

static CGFloat textWidth(NSString *s, NSFont *font)
{
	return [s sizeWithAttributes:[NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName]].width;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		NSMenuItemCell *cell = [[[NSMenuItemCell alloc] init] autorelease];
		expect([cell stateImageWidth] == 0 && [cell imageWidth] == 0 && [cell titleWidth] == 0 && [cell keyEquivalentWidth] == 0,
		       "a cell without a menu item has no part widths");

		NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"Hello World" action:NULL keyEquivalent:@"s"] autorelease];
		[cell setMenuItem:item];
		expect([cell stateImageWidth] == 18, "the state column is 18 points");
		expect([cell imageWidth] == 0, "no image, no image width");
		expect(near([cell titleWidth], textWidth(@"Hello World", [cell font]) + 4), "title width: the title in the cell's font plus 4");
		expect([cell keyEquivalentWidth] == 0, "a cell outside a menu has no key equivalent width");

		[item setImage:[[[NSImage alloc] initWithSize:NSMakeSize(16, 12)] autorelease]];
		expect([cell imageWidth] == 16, "image width is the image's width");

		[cell setFont:[NSFont systemFontOfSize:20]];
		expect(near([cell titleWidth], textWidth(@"Hello World", [NSFont systemFontOfSize:20]) + 4), "title width follows the cell's font");
		expect([cell stateImageWidth] == 18, "the state column does not depend on the font");

		NSPopUpButtonCell *popUp = [[[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:NO] autorelease];
		expect([popUp numberOfItems] == 0 && [popUp indexOfSelectedItem] == -1, "a pop-up cell made with an empty title has no items");
		expect([popUp menuItem] == nil && [popUp titleWidth] == 0 && [popUp stateImageWidth] == 0, "an empty pop-up cell has no menu item and no widths");
		NSPopUpButtonCell *titled = [[[NSPopUpButtonCell alloc] initTextCell:@"First" pullsDown:NO] autorelease];
		expect([titled numberOfItems] == 1 && [[titled titleOfSelectedItem] isEqual:@"First"], "a pop-up cell made with a title has it as its selected item");
		[popUp addItemsWithTitles:[NSArray arrayWithObjects:@"Alpha", @"Beta longer", nil]];
		expect([popUp menuItem] == [popUp itemAtIndex:0], "a pop-up cell's menu item is its first item once it has items");
		[popUp selectItemAtIndex:1];
		expect([popUp menuItem] == [popUp selectedItem], "a pop-up cell's menu item is the selected item");
		expect(near([popUp titleWidth], textWidth(@"Beta longer", [popUp font]) + 4), "pop-up title width is the selected item's");
		expect([popUp stateImageWidth] == 18, "pop-up state column");
		[[popUp selectedItem] setImage:[[[NSImage alloc] initWithSize:NSMakeSize(16, 12)] autorelease]];
		expect([popUp imageWidth] == 16, "pop-up image width is the selected item's");

		NSPopUpButtonCell *pullDown = [[[NSPopUpButtonCell alloc] initTextCell:@"" pullsDown:YES] autorelease];
		[pullDown addItemsWithTitles:[NSArray arrayWithObjects:@"Head", @"Two", nil]];
		[pullDown selectItemAtIndex:1];
		expect([pullDown menuItem] == [pullDown itemAtIndex:0], "a pull-down cell's menu item is its first item");
		expect(near([pullDown titleWidth], textWidth(@"Head", [pullDown font]) + 4), "pull-down title width is the first item's");
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
