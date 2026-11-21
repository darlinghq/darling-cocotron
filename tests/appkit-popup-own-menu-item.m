/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A pop-up button cell normally shows the title and image of the selected
 * item (of the first item for a pull-down menu). After
 * -setUsesItemFromMenu:NO it shows the cell's own menu item set with
 * -setMenuItem: instead, and nothing while it has none, as the
 * NSPopUpButtonCell documentation of usesItemFromMenu describes. A new cell
 * uses the item from its menu. Observed on macOS 10.14.4 and 26.7.3 through
 * the public API.
 *
 * The test checks the titles and images and draws a pull-down button whose
 * own menu item has a red image into a bitmap, checking the image shows.
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

static NSImage *redImage(void)
{
	NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(12, 12)] autorelease];
	[image lockFocus];
	[[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] setFill];
	NSRectFill(NSMakeRect(0, 0, 12, 12));
	[image unlockFocus];
	return image;
}

static NSInteger redPixels(NSView *view)
{
	NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
	[view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
	NSInteger count = 0;
	for (NSInteger y = 0; y < [rep pixelsHigh]; y++)
		for (NSInteger x = 0; x < [rep pixelsWide]; x++) {
			NSColor *c = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
			if ([c alphaComponent] > 0.9 && [c redComponent] > 0.8 && [c greenComponent] < 0.3 &&
			    [c blueComponent] < 0.3)
				count++;
		}
	NSInteger scale = [rep pixelsWide] / (NSInteger) NSWidth([view bounds]);
	return count / (scale * scale);
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 100, 24) pullsDown:NO] autorelease];
		[popUp addItemWithTitle:@"First"];
		[popUp addItemWithTitle:@"Second"];
		[popUp selectItemAtIndex:1];
		NSPopUpButtonCell *cell = [popUp cell];
		expect([cell usesItemFromMenu], "a new cell uses the item from its menu");
		expect([[popUp title] isEqual:@"Second"], "a pop-up button shows its selected item");

		NSPopUpButton *pullDown = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 60, 24) pullsDown:YES] autorelease];
		[pullDown addItemWithTitle:@"Head"];
		[pullDown addItemWithTitle:@"Action"];
		cell = [pullDown cell];
		expect([[pullDown title] isEqual:@"Head"], "a pull-down button shows its first item");

		[cell setUsesItemFromMenu:NO];
		expect(![cell usesItemFromMenu], "the cell no longer uses the item from its menu");
		expect([[pullDown title] isEqual:@""], "without its own item it shows no title");

		NSMenuItem *own = [[[NSMenuItem alloc] initWithTitle:@"" action:NULL keyEquivalent:@""] autorelease];
		[own setImage:redImage()];
		[cell setMenuItem:own];
		expect([cell menuItem] == own, "the cell keeps its own item");
		expect([[pullDown title] isEqual:@""], "it shows its own item's title");
		expect([cell image] == [own image], "it shows its own item's image");
		expect([[pullDown itemAtIndex:0] image] == nil && [[[pullDown itemAtIndex:0] title] isEqual:@"Head"],
		       "the menu's items are unchanged");

		[pullDown setBordered:NO];
		[cell setArrowPosition:NSPopUpNoArrow];
		NSInteger red = redPixels(pullDown);
		char what[128];
		snprintf(what, sizeof what, "the button draws its own item's image (%ld red points)", (long) red);
		expect(red >= 100, what);
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
