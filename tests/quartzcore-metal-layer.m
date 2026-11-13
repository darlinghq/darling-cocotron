/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAMetalLayer: a subclass behaves like the class itself, the drawable size
 * follows the bounds until it is set explicitly, the timed present calls do
 * not terminate the process, and -nextDrawable on the main thread with the
 * whole pool presented renders the pending frame instead of blocking.
 *
 * Needs a display (Xvfb is enough) and a Metal device (any Vulkan driver,
 * e.g. lavapipe). Prints SKIP and exits 0 without a device.
 */
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@interface MyMetalLayer : CAMetalLayer
@end
@implementation MyMetalLayer
@end

static int failures;

static void expect(BOOL ok, const char *what) {
	if (!ok) {
		fprintf(stderr, "FAIL: %s\n", what);
		failures++;
	}
}

static void spin(NSTimeInterval seconds) {
	[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

int main(void) {
	@autoreleasepool {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (device == nil) {
			printf("SKIP: no Metal device\n");
			return 0;
		}

		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 64, 48)
			styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO];
		[window setReleasedWhenClosed: NO];
		NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 64, 48)];

		MyMetalLayer *layer = [MyMetalLayer layer];
		expect([layer isKindOfClass: [CAMetalLayer class]], "subclass instance is a CAMetalLayer");
		layer.device = device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.bounds = CGRectMake(0, 0, 64, 48);
		expect(layer.device == device, "subclass keeps its device");
		expect(layer.pixelFormat == MTLPixelFormatBGRA8Unorm, "subclass keeps its pixel format");
		expect(CGSizeEqualToSize(layer.drawableSize, CGSizeMake(64, 48)),
			"drawable size follows the bounds");

		host.layer = layer;
		host.wantsLayer = YES;
		[window setContentView: host];
		spin(0.1);

		layer.bounds = CGRectMake(0, 0, 128, 96);
		expect(CGSizeEqualToSize(layer.drawableSize, CGSizeMake(128, 96)),
			"drawable size follows a bounds change");
		layer.drawableSize = CGSizeMake(32, 32);
		layer.bounds = CGRectMake(0, 0, 256, 192);
		expect(CGSizeEqualToSize(layer.drawableSize, CGSizeMake(32, 32)),
			"an explicit drawable size is kept when the bounds change");
		layer.drawableSize = CGSizeMake(64, 48);

		id<CAMetalDrawable> drawable = [layer nextDrawable];
		expect(drawable != nil, "subclass layer hands out a drawable");
		expect([drawable texture].width == 64 && [drawable texture].height == 48,
			"drawable has the layer's drawable size");

		// Timed presents are hints: they must return instead of aborting.
		[drawable presentAtTime: CACurrentMediaTime() + 1.0];
		drawable = [layer nextDrawable];
		[drawable presentAfterMinimumDuration: 0.5];

		// Present the whole pool without letting the run loop render, then ask
		// for another drawable on the main thread: it must not deadlock.
		NSUInteger count = [layer maximumDrawableCount];
		for (NSUInteger i = 0; i < count; ++i) {
			id<CAMetalDrawable> d = [layer nextDrawable];
			if (d == nil)
				break;
			[d present];
		}
		id<CAMetalDrawable> extra = [layer nextDrawable];
		expect(extra != nil, "nextDrawable on the main thread with every drawable presented");

		[window close];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
