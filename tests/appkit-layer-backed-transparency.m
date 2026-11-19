/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Layer-backed views are composited over the window: where a layer-backed
 * view draws nothing, or draws a clear or partly transparent color, the
 * window's content beneath shows through, as for a view without a layer
 * (layers with transparent contents are blended with what is under them).
 *
 * A borderless window with a red background holds three layer-backed views:
 * one that draws nothing, one that fills itself with the clear color and one
 * that fills itself with blue at 50% opacity. The screen must show red, red
 * and an even mix of red and blue.
 *
 * Needs a display (X11 or Wayland) and PIXEL_GRAB, a command taking the window
 * title and "label x y" triples (window points, top-left origin) and printing
 * "pixel <label> RRGGBB", such as
 *   PIXEL_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I <host path>/quartzcore-metal-layer-plane-grab.py"
 * (with SWAYSOCK set for Wayland). No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TITLE "layer-backed-transparency"

static int failures;

@interface ClearView : NSView
@end
@implementation ClearView
- (void)drawRect:(NSRect)rect
{
	[[NSColor clearColor] setFill];
	NSRectFill(rect);
}
@end

@interface HalfBlueView : NSView
@end
@implementation HalfBlueView
- (void)drawRect:(NSRect)rect
{
	[[NSColor colorWithSRGBRed:0 green:0 blue:1 alpha:0.5] setFill];
	NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
}
@end

static void checkPixels(const char *grab)
{
	static const struct {
		const char *label;
		int x;
		unsigned expected;
		const char *what;
	} checks[] = {
		{"empty", 50, 0xFF0000, "a layer-backed view that draws nothing shows the window"},
		{"clear", 150, 0xFF0000, "a layer-backed view filled with the clear color shows the window"},
		{"half", 250, 0x800080, "a half transparent layer-backed view is blended with the window"},
	};
	char command[1024];
	snprintf(command, sizeof command, "%s %s empty 50 50 clear 150 50 half 250 50", grab, TITLE);
	FILE *pipe = popen(command, "r");
	unsigned values[3];
	BOOL seen[3] = {NO, NO, NO};
	char line[256];
	while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
		char label[32];
		unsigned value;
		if (sscanf(line, "pixel %31s %x", label, &value) != 2)
			continue;
		for (int i = 0; i < 3; i++)
			if (strcmp(label, checks[i].label) == 0) {
				values[i] = value;
				seen[i] = YES;
			}
	}
	if (pipe != NULL)
		pclose(pipe);
	for (int i = 0; i < 3; i++) {
		BOOL match = seen[i];
		for (int shift = 0; match && shift < 24; shift += 8)
			if (abs((int) ((values[i] >> shift) & 0xFF) - (int) ((checks[i].expected >> shift) & 0xFF)) > 8)
				match = NO;
		if (seen[i])
			printf("%s %s: %06X (expected %06X)\n", match ? "PASS" : "FAIL", checks[i].what, values[i],
			       checks[i].expected);
		else
			printf("FAIL %s: no pixel read\n", checks[i].what);
		if (!match)
			failures++;
	}
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		const char *grab = getenv("PIXEL_GRAB");
		if (grab == NULL) {
			printf("SKIP PIXEL_GRAB is not set\n");
			return 0;
		}
		NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 100)
		                                               styleMask:NSWindowStyleMaskBorderless
		                                                 backing:NSBackingStoreBuffered
		                                                   defer:NO];
		[window setTitle:@TITLE];
		[window setBackgroundColor:[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1]];
		NSView *views[3] = {
			[[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease],
			[[[ClearView alloc] initWithFrame:NSMakeRect(100, 0, 100, 100)] autorelease],
			[[[HalfBlueView alloc] initWithFrame:NSMakeRect(200, 0, 100, 100)] autorelease],
		};
		for (int i = 0; i < 3; i++) {
			[views[i] setWantsLayer:YES];
			[[window contentView] addSubview:views[i]];
		}
		[window orderFront:nil];
		[window display];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
		checkPixels(grab);
		[window orderOut:nil];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
