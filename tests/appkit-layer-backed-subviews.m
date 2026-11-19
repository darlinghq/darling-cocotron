/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A view added to a layer-backed view is layer-backed too, whether the view it
 * is added to wants its layer or only got one from its own superview: it and
 * its subviews get layers in the layer tree, while -wantsLayer stays NO. Such
 * a view loses its layer when the view above stops being layer-backed, and
 * when it is moved into a view that is not layer-backed. Observed on macOS
 * 10.14.4 through the public API (macOS 26 makes every view of a window
 * layer-backed, so only the first part shows there).
 *
 * A typical case is a scroll view made layer-backed before its document view
 * is set: the clip view got its layer from the scroll view, and the document
 * view added to it later must be drawn in the layer tree too.
 *
 * The geometry checks run everywhere. With PIXEL_GRAB set the test also reads
 * the screen: a red view added to the implicitly layer-backed clip view of a
 * layer-backed scroll view must show. PIXEL_GRAB names a command taking the
 * window title and "label x y" triples (window points, top-left origin) and
 * printing "pixel <label> RRGGBB", such as
 *   PIXEL_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I <host path>/quartzcore-metal-layer-plane-grab.py"
 * (with SWAYSOCK set for Wayland).
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TITLE "layer-backed-subviews"

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

@interface Swatch : NSView
@end
@implementation Swatch
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect
{
	[[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] setFill];
	NSRectFill(rect);
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static void checkPixel(const char *name, const char *grab, int x, int y, unsigned expected)
{
	char command[1024];
	snprintf(command, sizeof command, "%s %s p %d %d", grab, TITLE, x, y);
	FILE *pipe = popen(command, "r");
	char line[256];
	BOOL seen = NO;
	while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
		unsigned value;
		if (sscanf(line, "pixel p %x", &value) != 1)
			continue;
		seen = YES;
		BOOL match = YES;
		for (int shift = 0; shift < 24; shift += 8)
			if (abs((int) ((value >> shift) & 0xFF) - (int) ((expected >> shift) & 0xFF)) > 8)
				match = NO;
		printf("%s %s: %06X (expected %06X)\n", match ? "PASS" : "FAIL", name, value, expected);
		if (!match)
			failures++;
	}
	if (pipe != NULL)
		pclose(pipe);
	if (!seen) {
		printf("FAIL %s: no pixel read\n", name);
		failures++;
	}
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
		                                               styleMask:NSWindowStyleMaskBorderless
		                                                 backing:NSBackingStoreBuffered
		                                                   defer:NO];
		[window setTitle:@TITLE];
		[window setBackgroundColor:[NSColor whiteColor]];
		NSView *content = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)] autorelease];
		[window setContentView:content];

		NSView *backed = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 150, 150)] autorelease];
		NSView *existing = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
		[backed addSubview:existing];
		[content addSubview:backed];
		[backed setWantsLayer:YES];
		[window orderFront:nil];
		spin(0.5);

		expect([existing layer] != nil && ![existing wantsLayer],
		       "a subview of a view made layer-backed has a layer and does not want one");

		NSView *direct = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)] autorelease];
		[backed addSubview:direct];
		NSView *later = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
		[existing addSubview:later];
		NSView *tree = [[[NSView alloc] initWithFrame:NSMakeRect(20, 0, 30, 30)] autorelease];
		NSView *treeChild = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)] autorelease];
		[tree addSubview:treeChild];
		[existing addSubview:tree];
		[window display];
		spin(0.3);

		expect([direct layer] != nil && ![direct wantsLayer],
		       "a view added to a view that wants a layer gets one and does not want one");
		expect([later layer] != nil && ![later wantsLayer] && [[later layer] superlayer] == [existing layer],
		       "a view added to an implicitly layer-backed view gets a layer in its superview's layer");
		expect([tree layer] != nil && [treeChild layer] != nil && [[treeChild layer] superlayer] == [tree layer],
		       "a view added with subviews gets layers for all of them");

		NSView *plain = [[[NSView alloc] initWithFrame:NSMakeRect(200, 0, 100, 100)] autorelease];
		[content addSubview:plain];
		[plain addSubview:tree];
		[window display];
		spin(0.3);
		expect([tree layer] == nil && [treeChild layer] == nil,
		       "a view moved into a view that is not layer-backed loses its layers");

		[backed setWantsLayer:NO];
		[window display];
		spin(0.3);
		expect([existing layer] == nil && [later layer] == nil,
		       "the subviews lose their layers when the view above stops being layer-backed");

		// A layer-backed scroll view whose document view is set afterwards.
		NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(200, 150, 150, 120)] autorelease];
		[content addSubview:scroll];
		[scroll setWantsLayer:YES];
		[window display];
		spin(0.3);
		Swatch *document = [[[Swatch alloc] initWithFrame:NSMakeRect(0, 0, 150, 120)] autorelease];
		[scroll setDocumentView:document];
		[window display];
		spin(1);
		expect([document layer] != nil && [[document layer] superlayer] == [[scroll contentView] layer],
		       "a document view set in a layer-backed scroll view gets a layer in the clip view's layer");

		const char *grab = getenv("PIXEL_GRAB");
		if (grab == NULL)
			printf("SKIP pixels: PIXEL_GRAB is not set\n");
		else
			checkPixel("document view of a layer-backed scroll view is drawn", grab, 275, 90, 0xFF0000);

		[window orderOut:nil];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
