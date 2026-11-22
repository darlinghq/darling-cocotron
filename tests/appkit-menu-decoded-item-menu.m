/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The items of a menu that was decoded from an archive (as every menu loaded
 * from a nib is) belong to that menu: -[NSMenuItem menu] returns it, the
 * submenus have it as their supermenu, and -parentItem finds the item that
 * holds a submenu. Anything that is handed an item and looks its menu up (the
 * exported global menu does, to run the action of a chosen item) depends on it.
 *
 * Usage: appkit-menu-decoded-item-menu
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

	NSMenu *main = [[[NSMenu alloc] initWithTitle: @"Main"] autorelease];
	NSMenuItem *app = [main addItemWithTitle: @"App" action: NULL keyEquivalent: @""];
	NSMenu *appMenu = [[[NSMenu alloc] initWithTitle: @"App"] autorelease];
	[app setSubmenu: appMenu];
	[appMenu addItemWithTitle: @"About" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
	[appMenu addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];

	NSData *data = [NSKeyedArchiver archivedDataWithRootObject: main];
	NSMenu *decoded = [NSKeyedUnarchiver unarchiveObjectWithData: data];
	expect(decoded != nil && [decoded numberOfItems] == 1, "the menu decodes");

	NSMenuItem *decodedApp = [decoded itemAtIndex: 0];
	NSMenu *decodedAppMenu = [decodedApp submenu];
	expect([decodedApp menu] == decoded, "an item of a decoded menu has that menu");
	expect([decodedAppMenu supermenu] == decoded, "the submenu of a decoded item has the decoded menu as supermenu");
	expect([decodedApp parentItem] == nil, "an item of the decoded top-level menu has no parent item");

	NSMenuItem *quit = [decodedAppMenu itemAtIndex: 1];
	expect([quit menu] == decodedAppMenu, "an item of a decoded submenu has the submenu");
	expect([quit parentItem] == decodedApp, "the item holding the decoded submenu is its parent item");
	expect([decodedAppMenu indexOfItem: quit] == 1, "the menu of a decoded item finds it");

	[pool drain];
	printf(failures ? "FAIL\n" : "PASS\n");
	return failures != 0;
}
