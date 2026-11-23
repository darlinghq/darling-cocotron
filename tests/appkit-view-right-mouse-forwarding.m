/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A right mouse click on a view that has no context menu of its own goes up
 * the responder chain: an ancestor that handles -rightMouseDown: receives it,
 * and an ancestor that has a menu takes it before a still higher ancestor.
 * A view whose -menuForEvent: returns nil passes the click on too.
 *
 * Needs a display (Xvfb).
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface RecordingView : NSView {
@public
	NSUInteger rightMouseDowns;
	NSPoint lastLocation;
}
@end

@implementation RecordingView
- (void) rightMouseDown: (NSEvent *) event
{
	rightMouseDowns++;
	lastLocation = [event locationInWindow];
}
@end

@interface NoMenuView : NSView
@end

@implementation NoMenuView
- (NSMenu *) menuForEvent: (NSEvent *) event
{
	return nil;
}
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL: %s\n", what);
		failures++;
	}
}

static void rightClick(NSWindow *window, NSPoint location)
{
	NSEvent *event = [NSEvent mouseEventWithType: NSEventTypeRightMouseDown
	                                    location: location
	                               modifierFlags: 0
	                                   timestamp: 0
	                                windowNumber: [window windowNumber]
	                                     context: nil
	                                 eventNumber: 1
	                                  clickCount: 1
	                                    pressure: 1];
	[window sendEvent: event];
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 300)
		                                               styleMask: NSWindowStyleMaskTitled
		                                                 backing: NSBackingStoreBuffered
		                                                   defer: NO];
		RecordingView *root = [[RecordingView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
		NSView *middle = [[NSView alloc] initWithFrame: NSMakeRect(20, 20, 360, 260)];
		NSView *leaf = [[NSView alloc] initWithFrame: NSMakeRect(10, 10, 100, 100)];
		[root addSubview: middle];
		[middle addSubview: leaf];
		[window setContentView: root];
		[window makeKeyAndOrderFront: nil];

		NSPoint inLeaf = NSMakePoint(50, 50);
		expect([root hitTest: inLeaf] == leaf, "the click lands on the leaf view");

		rightClick(window, inLeaf);
		expect(root->rightMouseDowns == 1, "a right click on views without a menu reaches the ancestor handling it");
		expect(NSEqualPoints(root->lastLocation, inLeaf), "the ancestor gets the same event");

		// A menu on an ancestor in between takes the click.
		[middle setMenu: [[NSMenu alloc] initWithTitle: @"menu"]];
		rightClick(window, inLeaf);
		expect(root->rightMouseDowns == 1, "an ancestor with a menu takes the click before a higher ancestor");
		[middle setMenu: nil];

		// A view that answers -menuForEvent: with nil passes the click on.
		NoMenuView *noMenu = [[NoMenuView alloc] initWithFrame: NSMakeRect(0, 0, 360, 260)];
		[middle addSubview: noMenu];
		[noMenu addSubview: leaf];
		rightClick(window, inLeaf);
		expect(root->rightMouseDowns == 2, "a view whose menu for the event is nil passes the click on");

		[window close];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
