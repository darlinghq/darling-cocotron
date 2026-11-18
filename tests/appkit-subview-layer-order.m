// Copyright (C) 2026 Lubos Dolezel
//
// The sublayers of a layer-backed superview follow its subviews: after
// -addSubview:positioned:relativeTo:, -replaceSubview:with:, -setSubviews:,
// -sortSubviewsUsingFunction:context: and removing a view and adding it again,
// the sublayer order equals the subview order, and the view that is last in
// the subviews is the one drawn on top.
//
// Three opaque swatches with the same frame overlap in one window; one point in
// the overlap tells which one is on top. The pixel is read from the screen by a
// host program when PIXEL_GRAB names one (a command taking the window title and
// "label x y" triples, window points with a top-left origin, printing
// "pixel <label> RRGGBB"; see quartzcore-metal-layer-plane-grab.py). Without PIXEL_GRAB the view
// hierarchy is rendered into a bitmap with -cacheDisplayInRect:toBitmapImageRep:,
// which on macOS composites the layers but where drawing ignores layers
// follows the subview order only. The sublayer order is always checked.
//
// Needs a display (X11 or Wayland, or a window server). Prints PASS/FAIL lines.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
static NSWindow *window;
static NSView *root;
@class Swatch;
static Swatch *A, *B, *C, *D, *E;
static NSString *const kTitle = @"subview-layer-order";

@interface Swatch : NSView {
	NSColor *color;
	NSString *name;
	NSInteger order;
}
- (id)initWithColor:(NSColor *)c name:(NSString *)n;
- (NSString *)name;
- (NSColor *)color;
@end

@implementation Swatch
- (id)initWithColor:(NSColor *)c name:(NSString *)n
{
	if ((self = [super initWithFrame:NSMakeRect(20, 10, 100, 80)])) {
		color = [c retain];
		name = [n retain];
	}
	return self;
}
- (NSInteger)tag { return order; }
- (void)setTag:(NSInteger)value { order = value; }
- (NSString *)name { return name; }
- (NSColor *)color { return color; }
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)rect
{
	[color setFill];
	NSRectFill(rect);
}
@end

static Swatch *make(NSString *n, double r, double g, double b)
{
	return [[Swatch alloc] initWithColor:[NSColor colorWithSRGBRed:r green:g blue:b alpha:1] name:n];
}

static NSString *names(NSArray *views)
{
	NSMutableString *s = [NSMutableString string];
	for (Swatch *v in views)
		[s appendString:[v name]];
	return s;
}

static void spin(double seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

// the names of the swatches in the order of root's sublayers
static NSString *layerOrder(void)
{
	NSMutableString *s = [NSMutableString string];
	for (CALayer *layer in [[root layer] sublayers]) {
		NSString *n = @"?";
		for (Swatch *v in [root subviews])
			if ([v layer] == layer)
				n = [v name];
		[s appendString:n];
	}
	return s;
}

static unsigned topPixel(void)
{
	const char *grab = getenv("PIXEL_GRAB");
	if (grab != NULL) {
		char command[1024];
		snprintf(command, sizeof command, "%s %s top 60 50", grab, [kTitle UTF8String]);
		FILE *pipe = popen(command, "r");
		char line[256];
		unsigned value = 0xFFFFFFFF;
		char label[64];
		while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
			unsigned v;
			if (sscanf(line, "pixel %63s %x", label, &v) == 2)
				value = v;
		}
		if (pipe != NULL)
			pclose(pipe);
		return value;
	}
	NSBitmapImageRep *rep = [root bitmapImageRepForCachingDisplayInRect:[root bounds]];
	[root cacheDisplayInRect:[root bounds] toBitmapImageRep:rep];
	NSColor *c = [[rep colorAtX:60 y:50] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	return ((unsigned)(lround([c redComponent] * 255)) << 16) | ((unsigned)(lround([c greenComponent] * 255)) << 8) |
	       (unsigned)lround([c blueComponent] * 255);
}

static BOOL near(unsigned a, unsigned b)
{
	for (int shift = 0; shift < 24; shift += 8) {
		int d = (int)((a >> shift) & 0xFF) - (int)((b >> shift) & 0xFF);
		if (d > 64 || d < -64)
			return NO;
	}
	return YES;
}

static void reset(void)
{
	for (NSView *v in [[[root subviews] copy] autorelease])
		[v removeFromSuperview];
	[root addSubview:A];
	[root addSubview:B];
	[root addSubview:C];
}

static void expectOrder(const char *name, const char *expectedOrder)
{
	spin(0.4);
	NSString *subviews = names([root subviews]);
	NSString *layers = layerOrder();
	Swatch *top = [[root subviews] lastObject];
	unsigned wanted = 0;
	NSColor *c = [[top color] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	wanted = ((unsigned)lround([c redComponent] * 255) << 16) | ((unsigned)lround([c greenComponent] * 255) << 8) |
	         (unsigned)lround([c blueComponent] * 255);
	unsigned got = topPixel();

	BOOL orderOK = [subviews isEqualToString:[NSString stringWithUTF8String:expectedOrder]];
	BOOL layersOK = [layers isEqualToString:subviews];
	BOOL pixelOK = near(got, wanted);
	printf("%s %s: subviews %s (expected %s), sublayers %s, top pixel %06X (expected %06X)\n",
	       orderOK && layersOK && pixelOK ? "PASS" : "FAIL", name, [subviews UTF8String], expectedOrder,
	       [layers UTF8String], got, wanted);
	if (!(orderOK && layersOK && pixelOK))
		failures++;
}

static NSComparisonResult byTagDescending(id a, id b, void *context)
{
	return [b tag] > [a tag] ? NSOrderedDescending : ([b tag] < [a tag] ? NSOrderedAscending : NSOrderedSame);
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 100)
		                                     styleMask:NSWindowStyleMaskTitled
		                                       backing:NSBackingStoreBuffered
		                                         defer:NO];
		[window setTitle:kTitle];
		root = [window contentView];
		[root setWantsLayer:YES];
		A = make(@"A", 1, 0, 0);
		B = make(@"B", 0, 1, 0);
		C = make(@"C", 0, 0, 1);
		D = make(@"D", 1, 1, 0);
		E = make(@"E", 1, 0, 1);
		[A setTag:1];
		[B setTag:2];
		[C setTag:3];
		[D setTag:4];
		[E setTag:5];
		[window makeKeyAndOrderFront:nil];
		spin(1.0);

		reset();
		expectOrder("add three", "ABC");

		reset();
		[root addSubview:D positioned:NSWindowBelow relativeTo:nil];
		expectOrder("new view below all (positioned below nil)", "DABC");

		reset();
		[root addSubview:D positioned:NSWindowAbove relativeTo:A];
		expectOrder("new view above a sibling", "ADBC");

		reset();
		[root addSubview:D positioned:NSWindowBelow relativeTo:C];
		expectOrder("new view below a sibling", "ABDC");

		reset();
		[root addSubview:A positioned:NSWindowAbove relativeTo:C];
		expectOrder("existing view moved above the top view", "BCA");

		reset();
		[root addSubview:C positioned:NSWindowBelow relativeTo:A];
		expectOrder("existing view moved below the bottom view", "CAB");

		reset();
		[root addSubview:A];
		expectOrder("addSubview: of an existing view", "BCA");

		reset();
		[root sortSubviewsUsingFunction:byTagDescending context:NULL];
		expectOrder("sortSubviewsUsingFunction:context:", "CBA");

		reset();
		[root setSubviews:[NSArray arrayWithObjects:C, B, A, nil]];
		expectOrder("setSubviews: with the same views reordered", "CBA");

		reset();
		[root setSubviews:[NSArray arrayWithObjects:E, A, C, nil]];
		expectOrder("setSubviews: with a new view and one removed", "EAC");

		reset();
		[root replaceSubview:A with:E];
		expectOrder("replaceSubview:with: at the bottom", "EBC");

		reset();
		[root replaceSubview:B with:E];
		expectOrder("replaceSubview:with: in the middle", "AEC");

		reset();
		[B removeFromSuperview];
		[root addSubview:B positioned:NSWindowBelow relativeTo:A];
		expectOrder("remove, then add below the bottom view", "BAC");

		reset();
		[B removeFromSuperview];
		[root addSubview:B positioned:NSWindowAbove relativeTo:A];
		expectOrder("remove, then add above the bottom view", "ABC");

		reset();
		[A removeFromSuperview];
		[root addSubview:A];
		expectOrder("remove, then add", "BCA");

		printf(failures == 0 ? "ALL PASSED\n" : "FAILED %d\n", failures);
	}
	return failures != 0;
}
