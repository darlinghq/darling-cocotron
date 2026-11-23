/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * -[NSMenuItem parentItem] is the item whose submenu holds the receiver, nil
 * for an item of a menu that is not a submenu.
 *
 * Usage: appkit-menu-item-parent-item
 * Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
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

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	NSMenu *top = [[[NSMenu alloc] initWithTitle: @"Main"] autorelease];
	NSMenuItem *file = [top addItemWithTitle: @"File" action: NULL keyEquivalent: @""];
	NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle: @"File"] autorelease];
	[file setSubmenu: fileMenu];
	NSMenuItem *open = [fileMenu addItemWithTitle: @"Open" action: NULL keyEquivalent: @""];
	NSMenuItem *recent = [fileMenu addItemWithTitle: @"Recent" action: NULL keyEquivalent: @""];
	NSMenu *recentMenu = [[[NSMenu alloc] initWithTitle: @"Recent"] autorelease];
	[recent setSubmenu: recentMenu];
	NSMenuItem *clear = [recentMenu addItemWithTitle: @"Clear" action: NULL keyEquivalent: @""];

	expect([clear parentItem] == recent, "an item of a submenu has the item holding that submenu as parent");
	expect([open parentItem] == file, "a second item of the same submenu has the same parent");
	expect([recent parentItem] == file, "a submenu item is itself a child of the next level up");
	expect([file parentItem] == nil, "an item of the top-level menu has no parent item");

	NSMenuItem *lone = [[[NSMenuItem alloc] initWithTitle: @"Lone" action: NULL keyEquivalent: @""] autorelease];
	expect([lone parentItem] == nil, "an item in no menu has no parent item");

	NSMenu *detached = [[[NSMenu alloc] initWithTitle: @"Detached"] autorelease];
	NSMenuItem *inDetached = [detached addItemWithTitle: @"Item" action: NULL keyEquivalent: @""];
	expect([inDetached parentItem] == nil, "an item of a menu that is nobody's submenu has no parent item");

	[pool drain];
	return failures != 0;
}
