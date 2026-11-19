/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * The layers of the subviews of a flipped layer-backed view are placed where
 * the subviews are on screen. A subview at the top of a flipped view (frame
 * origin y = 0) must show at the top, as it does without layers.
 *
 * Geometry, as observed on macOS 10.14.4 through the public API: in the layer
 * of a flipped superview, a sublayer has its anchor point at (0, 1) and its
 * position at the mirrored top-left corner of the view's frame, so its layer
 * frame is the view frame mirrored within the superview's bounds (y up).
 * Under a plain superview the layer frame equals the view frame. After the
 * flipped superview's size changes, its sublayers are placed again.
 * (macOS 26 reaches the same screen result with geometryFlipped layers; the
 * older layout is the one checked, see the QUIRK in NSView.m.)
 *
 * The test also builds a layer-backed scroll view with a table and its header
 * and checks that the header's layer is at the top of the scroll view's
 * layer (macOS 10.14 lets the rows' clip view run on under the header, so only
 * the header's place is checked), and, with
 * PIXEL_GRAB set, reads the screen: a red view at the top of a flipped
 * layer-backed view must show at the top. PIXEL_GRAB names a command taking
 * the window title and "label x y" triples (window points, top-left origin)
 * and printing "pixel <label> RRGGBB", such as
 *   PIXEL_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I <host path>/quartzcore-metal-layer-plane-grab.py"
 * (with SWAYSOCK set for Wayland). Without it the pixel part prints SKIP.
 *
 * Needs a display (X11 or Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TITLE "layer-flipped-superview"

static int failures;

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface Swatch : NSView {
	NSColor *color;
}
- (id)initWithFrame:(NSRect)frame color:(NSColor *)c;
@end
@implementation Swatch
- (id)initWithFrame:(NSRect)frame color:(NSColor *)c
{
	if ((self = [super initWithFrame:frame]))
		color = [c retain];
	return self;
}
- (void)dealloc
{
	[color release];
	[super dealloc];
}
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect
{
	[color setFill];
	NSRectFill(rect);
}
@end

@interface Rows : NSObject <NSTableViewDataSource>
@end
@implementation Rows
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return 3; }
- (id)tableView:(NSTableView *)t objectValueForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	return [NSString stringWithFormat:@"row %ld", (long) r];
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static BOOL near(CGFloat a, CGFloat b)
{
	return fabs(a - b) < 0.01;
}

static void checkLayer(const char *name, NSView *view, CGRect frame, CGPoint anchor)
{
	CALayer *layer = [view layer];
	if (layer == nil) {
		printf("FAIL %s: no layer\n", name);
		failures++;
		return;
	}
	CGRect f = [layer frame];
	CGPoint a = [layer anchorPoint];
	BOOL ok = near(f.origin.x, frame.origin.x) && near(f.origin.y, frame.origin.y) &&
	          near(f.size.width, frame.size.width) && near(f.size.height, frame.size.height) &&
	          near(a.x, anchor.x) && near(a.y, anchor.y) && ![layer isGeometryFlipped];
	printf("%s %s: layer frame {%g,%g,%g,%g} anchor {%g,%g} geometryFlipped %d (expected {%g,%g,%g,%g} {%g,%g} 0)\n",
	       ok ? "PASS" : "FAIL", name, f.origin.x, f.origin.y, f.size.width, f.size.height, a.x, a.y,
	       [layer isGeometryFlipped], frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
	       anchor.x, anchor.y);
	if (!ok)
		failures++;
}

struct point {
	const char *label;
	int x, y; // window points, top-left origin
	unsigned expected;
};

static void checkPixels(const char *name, const char *grab, const struct point *points, unsigned count)
{
	char command[1024];
	int length = snprintf(command, sizeof command, "%s %s", grab, TITLE);
	for (unsigned i = 0; i < count; i++)
		length += snprintf(command + length, sizeof command - length, " %s %d %d", points[i].label,
		                   points[i].x, points[i].y);

	BOOL seen[count];
	memset(seen, 0, sizeof seen);
	FILE *pipe = popen(command, "r");
	char line[256];
	while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
		char label[64];
		unsigned value;
		if (sscanf(line, "pixel %63s %x", label, &value) != 2)
			continue;
		for (unsigned i = 0; i < count; i++) {
			if (strcmp(label, points[i].label) != 0)
				continue;
			seen[i] = YES;
			BOOL match = YES;
			for (int shift = 0; shift < 24; shift += 8)
				if (abs((int) ((value >> shift) & 0xFF) - (int) ((points[i].expected >> shift) & 0xFF)) > 8)
					match = NO;
			printf("%s %s, %s: %06X (expected %06X)\n", match ? "PASS" : "FAIL", name, points[i].label, value,
			       points[i].expected);
			if (!match)
				failures++;
		}
	}
	if (pipe != NULL)
		pclose(pipe);
	for (unsigned i = 0; i < count; i++) {
		if (!seen[i]) {
			printf("FAIL %s, %s: no pixel read\n", name, points[i].label);
			failures++;
		}
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

		// A flipped layer-backed view with a plain and a flipped subview, and a
		// plain grandchild in the flipped one.
		FlippedView *flipped = [[[FlippedView alloc] initWithFrame:NSMakeRect(10, 20, 200, 100)] autorelease];
		[content addSubview:flipped];
		[flipped setWantsLayer:YES];
		NSView *child = [[[NSView alloc] initWithFrame:NSMakeRect(5, 10, 50, 30)] autorelease];
		[flipped addSubview:child];
		FlippedView *flippedChild = [[[FlippedView alloc] initWithFrame:NSMakeRect(60, 0, 40, 25)] autorelease];
		[flipped addSubview:flippedChild];
		NSView *grandchild = [[[NSView alloc] initWithFrame:NSMakeRect(1, 2, 10, 5)] autorelease];
		[flippedChild addSubview:grandchild];

		// A plain layer-backed view: its sublayers have the frames of the views.
		NSView *plain = [[[NSView alloc] initWithFrame:NSMakeRect(220, 20, 100, 100)] autorelease];
		[content addSubview:plain];
		[plain setWantsLayer:YES];
		NSView *plainChild = [[[NSView alloc] initWithFrame:NSMakeRect(5, 10, 50, 30)] autorelease];
		[plain addSubview:plainChild];

		[window orderFront:nil];
		spin(1);

		checkLayer("plain view in a flipped view", child, CGRectMake(5, 60, 50, 30), CGPointMake(0, 1));
		checkLayer("flipped view in a flipped view", flippedChild, CGRectMake(60, 75, 40, 25), CGPointMake(0, 1));
		checkLayer("plain view in a flipped subview", grandchild, CGRectMake(1, 18, 10, 5), CGPointMake(0, 1));
		checkLayer("plain view in a plain view", plainChild, CGRectMake(5, 10, 50, 30), CGPointMake(0, 0));

		// The sublayers follow the flipped view's new height, also for a
		// subview whose frame does not change.
		[flipped setFrameSize:NSMakeSize(200, 150)];
		spin(0.3);
		checkLayer("plain view in a flipped view after its height changed", child, CGRectMake(5, 110, 50, 30),
		           CGPointMake(0, 1));

		// A layer-backed scroll view with a table and its header (the scroll
		// view is flipped): the header is on top of the rows.
		NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0, 150, 220, 140)] autorelease];
		NSTableView *table = [[[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
		NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"c"] autorelease];
		[[column headerCell] setStringValue:@"Name"];
		[table addTableColumn:column];
		Rows *rows = [[[Rows alloc] init] autorelease];
		[table setDataSource:rows];
		[scroll setDocumentView:table];
		[scroll setHasVerticalScroller:YES];
		[content addSubview:scroll];
		[scroll setWantsLayer:YES];
		spin(0.5);
		NSView *headerClip = [[table headerView] superview];
		NSView *rowsClip = [scroll contentView];
		CGRect headerFrame = [[headerClip layer] frame], rowsFrame = [[rowsClip layer] frame];
		BOOL above = [headerClip layer] != nil && [rowsClip layer] != nil &&
		             CGRectGetMinY(headerFrame) > CGRectGetMinY(rowsFrame) &&
		             near(CGRectGetMaxY(headerFrame), [scroll bounds].size.height);
		printf("%s table header layer at the top of the scroll view: header {%g,%g,%g,%g}, rows {%g,%g,%g,%g}\n",
		       above ? "PASS" : "FAIL", headerFrame.origin.x, headerFrame.origin.y, headerFrame.size.width,
		       headerFrame.size.height, rowsFrame.origin.x, rowsFrame.origin.y, rowsFrame.size.width,
		       rowsFrame.size.height);
		if (!above)
			failures++;

		const char *grab = getenv("PIXEL_GRAB");
		if (grab == NULL) {
			printf("SKIP pixels: PIXEL_GRAB is not set\n");
		} else {
			// Red at the top and blue at the bottom of a flipped layer-backed
			// view at x 240..390, y 160..280 from the top left of the window.
			FlippedView *stack = [[[FlippedView alloc] initWithFrame:NSMakeRect(240, 20, 150, 120)] autorelease];
			Swatch *top = [[[Swatch alloc] initWithFrame:NSMakeRect(0, 0, 150, 40)
			                                       color:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]]
			        autorelease];
			Swatch *bottom = [[[Swatch alloc] initWithFrame:NSMakeRect(0, 80, 150, 40)
			                                          color:[NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:1]]
			        autorelease];
			[stack addSubview:top];
			[stack addSubview:bottom];
			[content addSubview:stack];
			[stack setWantsLayer:YES];
			[window display];
			spin(1.5);
			struct point points[] = {
			        {"top", 315, 180, 0xFF0000},
			        {"bottom", 315, 260, 0x0000FF},
			};
			checkPixels("flipped layer-backed view", grab, points, 2);
		}

		[window orderOut:nil];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
