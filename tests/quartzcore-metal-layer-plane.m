/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A CAMetalLayer-backed view is drawn like any other layer: a sibling view
 * added after it is drawn over it (observed on macOS 27.0.1: the overlap shows
 * the sibling). Darling shows a Metal layer on a native surface of its own
 * (an overlay plane) only while nothing covers it, and composites it with the
 * window's layers otherwise. This test moves a sibling view onto the Metal view
 * and off it again, then hides and shows it over the Metal view, and checks
 * - which way the layer is shown (the private -presentsThroughSwapchain of
 *   Darling's CAMetalLayer): on its plane while uncovered, composited while
 *   covered, unless CAMetalLayerForceOpenGL makes it composite throughout;
 * - the pixels on screen, which must be the same either way.
 *
 * Pixels are read from the screen by a host program: set PLANE_GRAB to a guest
 * path of a command that takes the window title and "label x y" triples
 * (window points, top-left origin) and prints "pixel <label> RRGGBB" lines,
 * such as quartzcore-metal-layer-plane-grab.sh. Without it only the path is
 * checked.
 *
 * Needs a display (X11 or Wayland) and a Metal device (any Vulkan driver, e.g.
 * lavapipe). Prints SKIP and exits 0 without a device.
 */
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;

@interface MetalView : NSView
@end

@implementation MetalView
- (CALayer *)makeBackingLayer
{
	CAMetalLayer *layer = [CAMetalLayer layer];
	layer.device = device;
	return layer;
}
@end

static void spin(NSTimeInterval seconds)
{
	[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// clears a drawable to solid red and presents it
static BOOL presentRed(CAMetalLayer *layer)
{
	id<CAMetalDrawable> drawable = [layer nextDrawable];
	if (drawable == nil)
		return NO;
	MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
	pass.colorAttachments[0].texture = drawable.texture;
	pass.colorAttachments[0].loadAction = MTLLoadActionClear;
	pass.colorAttachments[0].storeAction = MTLStoreActionStore;
	pass.colorAttachments[0].clearColor = MTLClearColorMake(1, 0, 0, 1);
	id<MTLCommandBuffer> buffer = [queue commandBuffer];
	[[buffer renderCommandEncoderWithDescriptor: pass] endEncoding];
	[buffer presentDrawable: drawable];
	[buffer commit];
	[buffer waitUntilCompleted];
	return YES;
}

static BOOL onPlane(CAMetalLayer *layer)
{
	SEL sel = @selector(presentsThroughSwapchain);
	if (![layer respondsToSelector: sel])
		return NO;
	return ((BOOL (*)(id, SEL)) [layer methodForSelector: sel])(layer, sel);
}

// Window is 300x200 points. Metal view at (20,20) 120x100; the sibling is 100x100 at y 60,
// x 100 (covering the Metal view's upper right corner) or x 180 (beside it).
static void step(const char *name, CAMetalLayer *layer, BOOL covered, BOOL forcedGL, BOOL siblingShown)
{
	// a frame presented after the change, then time for it to be shown
	spin(0.3);
	if (!presentRed(layer)) {
		printf("FAIL %s: no drawable\n", name);
		failures++;
		return;
	}
	spin(0.3);
	presentRed(layer);
	spin(0.5);

	BOOL plane = onPlane(layer);
	BOOL expected = !covered && !forcedGL;
	printf("%s %s: path %s (expected %s)\n", plane == expected ? "PASS" : "FAIL", name,
	       plane ? "plane" : "composited", expected ? "plane" : "composited");
	if (plane != expected)
		failures++;

	const char *grab = getenv("PLANE_GRAB");
	if (grab == NULL)
		return;

	// window points, top-left origin: Metal view only, where the sibling can overlap it,
	// sibling only, background
	struct { const char *label; int x, y; unsigned expected; } points[] = {
		{"metal", 40, 150, 0xFF0000},
		{"overlap", 120, 110, covered ? 0x0000FF : 0xFF0000},
		{"sibling", 190, 50, siblingShown ? 0x0000FF : 0xFFFFFF},
		{"background", 280, 190, 0xFFFFFF},
	};
	const unsigned count = sizeof points / sizeof points[0];
	char command[1024];
	int length = snprintf(command, sizeof command, "%s plane-test", grab);
	for (unsigned i = 0; i < count; i++)
		length += snprintf(command + length, sizeof command - length, " %s %d %d", points[i].label, points[i].x, points[i].y);

	BOOL seen[count];
	memset(seen, 0, sizeof seen);
	FILE *pipe = popen(command, "r");
	char line[256];
	while (pipe != NULL && fgets(line, sizeof line, pipe) != NULL) {
		char label[64];
		unsigned value;
		if (sscanf(line, "pixel %63s %x", label, &value) != 2) {
			// other facts the reader reports, such as the number of native subwindows
			printf("info %s: %s", name, line);
			continue;
		}
		for (unsigned i = 0; i < count; i++) {
			if (strcmp(label, points[i].label) != 0)
				continue;
			seen[i] = YES;
			// a channel may be off by a little after colour conversion
			BOOL match = YES;
			for (int shift = 0; shift < 24; shift += 8)
				if (abs((int) ((value >> shift) & 0xFF) - (int) ((points[i].expected >> shift) & 0xFF)) > 8)
					match = NO;
			printf("%s %s %s: %06X (expected %06X)\n", match ? "PASS" : "FAIL", name, label, value, points[i].expected);
			if (!match)
				failures++;
		}
	}
	if (pipe != NULL)
		pclose(pipe);
	for (unsigned i = 0; i < count; i++) {
		if (!seen[i]) {
			printf("FAIL %s %s: no pixel read\n", name, points[i].label);
			failures++;
		}
	}
}

int main(void)
{
	@autoreleasepool {
		device = MTLCreateSystemDefaultDevice();
		if (device == nil) {
			printf("SKIP: no Metal device\n");
			return 0;
		}
		queue = [device newCommandQueue];
		BOOL forcedGL = [[NSUserDefaults standardUserDefaults] boolForKey: @"CAMetalLayerForceOpenGL"];

		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 200)
		                                               styleMask: NSWindowStyleMaskBorderless
		                                                 backing: NSBackingStoreBuffered
		                                                   defer: NO];
		[window setTitle: @"plane-test"];
		NSView *root = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];
		root.wantsLayer = YES;
		root.layer.backgroundColor = CGColorCreateGenericRGB(1, 1, 1, 1);
		window.contentView = root;

		MetalView *metal = [[MetalView alloc] initWithFrame: NSMakeRect(20, 20, 120, 100)];
		[root addSubview: metal];
		CAMetalLayer *layer = (CAMetalLayer *) metal.layer;
		if (![layer isKindOfClass: [CAMetalLayer class]]) {
			printf("FAIL: the view's layer is not a CAMetalLayer\n");
			return 1;
		}

		NSView *sibling = [[NSView alloc] initWithFrame: NSMakeRect(180, 60, 100, 100)];
		sibling.wantsLayer = YES;
		sibling.layer.backgroundColor = CGColorCreateGenericRGB(0, 0, 1, 1);
		[root addSubview: sibling];

		[window orderFront: nil];
		spin(0.5);

		step("uncovered", layer, NO, forcedGL, YES);
		[sibling setFrameOrigin: NSMakePoint(100, 60)];
		step("covered", layer, YES, forcedGL, YES);
		[sibling setFrameOrigin: NSMakePoint(180, 60)];
		step("uncovered-again", layer, NO, forcedGL, YES);
		// a hidden view covers nothing
		[sibling setHidden: YES];
		[sibling setFrameOrigin: NSMakePoint(100, 60)];
		step("hidden", layer, NO, forcedGL, NO);
		[sibling setHidden: NO];
		step("shown", layer, YES, forcedGL, YES);

		[window orderOut: nil];
		printf(failures ? "FAILED\n" : "OK\n");
		return failures ? 1 : 0;
	}
}
