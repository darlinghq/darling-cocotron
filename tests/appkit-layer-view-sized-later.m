/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A layer-backed view shows its layer wherever its frame is, also when it had
 * no size when it got its layer and only gets one later, and shows nothing
 * while its frame is empty. The documented NSView contract has no exception
 * for a view that is resized after -setWantsLayer:, and views commonly start
 * out with NSZeroRect and are laid out afterwards.
 *
 * In an on-screen window, the test
 * - makes a sized view layer-backed with a red layer: its frame must show red;
 * - empties that view's frame: the place it had must show the window
 *   background;
 * - adds a view with a zero frame, makes it layer-backed with a red layer and
 *   gives it a frame: the frame must show red;
 * - empties that frame, then gives the view a frame elsewhere: the new place
 *   must show red, the old one the background.
 *
 * Pixels are read from the screen by a host program: set PIXEL_GRAB to a guest
 * path of a command that takes the window title and "label x y" triples
 * (window points, top-left origin) and prints "pixel <label> RRGGBB" lines,
 * such as quartzcore-metal-layer-plane-grab.py run with the host's python3:
 *   PIXEL_GRAB="/Volumes/SystemRoot/usr/bin/python3 -I <host path>/quartzcore-metal-layer-plane-grab.py"
 * (with SWAYSOCK set for Wayland). Without it the test prints SKIP.
 *
 * Needs a display (X11 or Wayland) and OpenGL. No ARC.
 */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TITLE "layer-view-sized-later"
#define WIDTH 300
#define HEIGHT 200

static int failures;

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
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
		length += snprintf(command + length, sizeof command - length, " %s %d %d",
		                   points[i].label, points[i].x, points[i].y);

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
			// a channel may be off by a little after colour conversion
			BOOL match = YES;
			for (int shift = 0; shift < 24; shift += 8)
				if (abs((int) ((value >> shift) & 0xFF) - (int) ((points[i].expected >> shift) & 0xFF)) > 8)
					match = NO;
			printf("%s %s, %s: %06X (expected %06X)\n", match ? "PASS" : "FAIL", name, points[i].label,
			       value, points[i].expected);
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
		const char *grab = getenv("PIXEL_GRAB");
		if (grab == NULL) {
			printf("SKIP: PIXEL_GRAB is not set\n");
			return 0;
		}

		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, WIDTH, HEIGHT)
		                                               styleMask: NSWindowStyleMaskBorderless
		                                                 backing: NSBackingStoreBuffered
		                                                   defer: NO];
		[window setTitle: @TITLE];
		[window setBackgroundColor: [NSColor whiteColor]];
		[window makeKeyAndOrderFront: nil];
		spin(1);

		CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);

		// x 160..280, y 100..180 from the top left
		NSView *first = [[NSView alloc] initWithFrame: NSMakeRect(160, 20, 120, 80)];
		[[window contentView] addSubview: first];
		[first setWantsLayer: YES];
		[first layer].backgroundColor = red;
		spin(1.5);
		struct point shown[] = {
			{"inside", 220, 140, 0xFF0000},
			{"outside", 80, 140, 0xFFFFFF},
		};
		checkPixels("sized view", grab, shown, 2);

		[first setFrame: NSMakeRect(160, 20, 0, 0)];
		spin(1.5);
		struct point hidden[] = {
			{"old-place", 220, 140, 0xFFFFFF},
		};
		checkPixels("sized view frame emptied", grab, hidden, 1);
		[first removeFromSuperview];
		[first release];

		NSView *view = [[NSView alloc] initWithFrame: NSZeroRect];
		[[window contentView] addSubview: view];
		[view setWantsLayer: YES];
		[view layer].backgroundColor = red;
		CGColorRelease(red);
		spin(0.5);

		// 120x80 at (20, 20) from the bottom left: x 20..140, y 100..180 from the top left
		[view setFrame: NSMakeRect(20, 20, 120, 80)];
		spin(1.5);
		struct point sized[] = {
			{"inside", 80, 140, 0xFF0000},
			{"outside", 220, 40, 0xFFFFFF},
		};
		checkPixels("view sized after it got its layer", grab, sized, 2);

		[view setFrame: NSMakeRect(20, 20, 0, 0)];
		spin(1.5);
		struct point emptied[] = {
			{"old-place", 80, 140, 0xFFFFFF},
		};
		checkPixels("view frame emptied", grab, emptied, 1);

		// x 160..280, y 100..180 from the top left
		[view setFrame: NSMakeRect(160, 20, 120, 80)];
		spin(1.5);
		struct point moved[] = {
			{"new-place", 220, 140, 0xFF0000},
			{"old-place", 80, 140, 0xFFFFFF},
		};
		checkPixels("view sized again elsewhere", grab, moved, 2);

		[window orderOut: nil];
		[view release];
		[window release];
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
