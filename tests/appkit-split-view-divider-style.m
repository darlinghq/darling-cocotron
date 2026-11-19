/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * NSSplitView divider styles (NSSplitViewDividerStyle): a new split view has
 * the thick style; the thick, thin and pane splitter dividers are 9, 1 and 10
 * points thick, and the subviews are laid out around a divider of that
 * thickness. A split view from a nib has the style chosen in Interface
 * Builder (the archive stores it for the thin and pane splitter styles only).
 * A thin divider is a line in the divider color, without the dimple image.
 * Observed on macOS 10.14.4 and 26.7.3 through the public API.
 *
 * Usage: appkit-split-view-divider-style [<fixtures/nibarchive directory>]
 * With the directory it also loads flat/Splits.nib (from src/Splits.xib):
 * three vertical split views with the default, thin and pane splitter styles.
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

static void expectStyle(NSSplitView *split, NSSplitViewDividerStyle style, CGFloat thickness, const char *what)
{
	char line[256];
	snprintf(line, sizeof line, "%s: style %ld thickness %g (expected %ld, %g)", what, (long) [split dividerStyle],
	         [split dividerThickness], (long) style, thickness);
	expect([split dividerStyle] == style && fabs([split dividerThickness] - thickness) < 0.01, line);
}

int main(int argc, char **argv)
{
	@autoreleasepool {
		[NSApplication sharedApplication];

		NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 110, 100)] autorelease];
		expectStyle(split, NSSplitViewDividerStyleThick, 9, "a new split view");
		[split setVertical:YES];
		[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 50, 100)] autorelease]];
		[split addSubview:[[[NSView alloc] initWithFrame:NSMakeRect(60, 0, 50, 100)] autorelease]];

		const struct {
			NSSplitViewDividerStyle style;
			CGFloat thickness;
			const char *name;
		} styles[] = {
			{NSSplitViewDividerStyleThick, 9, "thick"},
			{NSSplitViewDividerStyleThin, 1, "thin"},
			{NSSplitViewDividerStylePaneSplitter, 10, "pane splitter"},
		};
		for (int i = 0; i < 3; i++) {
			[split setDividerStyle:styles[i].style];
			expectStyle(split, styles[i].style, styles[i].thickness, styles[i].name);
			[split adjustSubviews];
			NSRect first = [[[split subviews] objectAtIndex:0] frame];
			NSRect second = [[[split subviews] objectAtIndex:1] frame];
			char line[256];
			snprintf(line, sizeof line, "%s: the subviews leave the divider's thickness between them (%g to %g)",
			         styles[i].name, NSMaxX(first), NSMinX(second));
			expect(fabs(NSMinX(second) - NSMaxX(first) - styles[i].thickness) < 0.01 &&
			               fabs(NSMaxX(second) - 110) < 0.01,
			       line);
		}

		// The thin divider is drawn as a line: no other color within it.
		NSSplitView *thin = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 40, 40)] autorelease];
		[thin setDividerStyle:NSSplitViewDividerStyleThin];
		NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
		                                                                  pixelsWide:40
		                                                                  pixelsHigh:40
		                                                               bitsPerSample:8
		                                                             samplesPerPixel:4
		                                                                    hasAlpha:YES
		                                                                    isPlanar:NO
		                                                              colorSpaceName:NSDeviceRGBColorSpace
		                                                                 bytesPerRow:40 * 4
		                                                                bitsPerPixel:32] autorelease];
		[NSGraphicsContext saveGraphicsState];
		[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
		[[NSColor whiteColor] setFill];
		NSRectFill(NSMakeRect(0, 0, 40, 40));
		[thin drawDividerInRect:NSMakeRect(0, 15, 40, 10)];
		[NSGraphicsContext restoreGraphicsState];
		NSColor *corner = [rep colorAtX:0 y:20];
		BOOL uniform = YES;
		for (int x = 0; x < 40; x++)
			for (int y = 16; y < 24; y++) {
				NSColor *c = [rep colorAtX:x y:y];
				if (fabs([c redComponent] - [corner redComponent]) > 0.02 ||
				    fabs([c greenComponent] - [corner greenComponent]) > 0.02 ||
				    fabs([c blueComponent] - [corner blueComponent]) > 0.02)
					uniform = NO;
			}
		expect(uniform, "a thin divider is one color, without a dimple");

		if (argc > 1) {
			NSString *path = [[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"flat/Splits.nib"];
			NSNib *nib = [[[NSNib alloc] initWithNibData:[NSData dataWithContentsOfFile:path] bundle:nil] autorelease];
			NSArray *topLevelObjects = nil;
			NSView *container = nil;
			if ([nib instantiateWithOwner:nil topLevelObjects:&topLevelObjects])
				for (id object in topLevelObjects)
					if ([object isKindOfClass:[NSView class]])
						container = object;
			NSArray *splits = [container subviews];
			expect([splits count] == 3, "the nib has three split views");
			if ([splits count] == 3) {
				for (int i = 0; i < 3; i++) {
					char what[64];
					snprintf(what, sizeof what, "the nib's %s split view", styles[i].name);
					NSSplitView *fromNib = nil;
					for (NSSplitView *candidate in splits)
						if (fabs(NSMinX([candidate frame]) - 110 * i) < 0.5)
							fromNib = candidate;
					expectStyle(fromNib, styles[i].style, styles[i].thickness, what);
				}
			}
		} else {
			printf("SKIP nib: no fixtures directory given\n");
		}
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
