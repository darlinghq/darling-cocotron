/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAMetalLayer: -nextDrawable on the main thread, with every drawable checked
 * out and nothing queued yet, must return as soon as another thread presents
 * one of them. The presented drawable is recycled by a render pass that only
 * the main thread can run, so the call has to run that pass itself instead of
 * sleeping until its timeout.
 *
 * Needs a display (Xvfb is enough) and a Metal device (any Vulkan driver,
 * e.g. lavapipe). Prints SKIP and exits 0 without a device.
 */
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CABase.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what) {
	if (!ok) {
		fprintf(stderr, "FAIL: %s\n", what);
		failures++;
	}
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
		CAMetalLayer *layer = [CAMetalLayer layer];
		layer.device = device;
		layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		layer.drawableSize = CGSizeMake(64, 48);
		layer.allowsNextDrawableTimeout = YES;
		host.layer = layer;
		host.wantsLayer = YES;
		[window setContentView: host];
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];

		// Check out the whole pool, presenting none of it.
		NSMutableArray *held = [NSMutableArray array];
		for (NSUInteger i = 0; i < layer.maximumDrawableCount; ++i) {
			id<CAMetalDrawable> d = [layer nextDrawable];
			expect(d != nil, "drawable available while the pool is not exhausted");
			if (d)
				[held addObject: d];
		}

		// Another thread presents one of them while the main thread is already waiting.
		id<CAMetalDrawable> toPresent = held.firstObject;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC),
			dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
			[toPresent present];
		});

		CFTimeInterval start = CACurrentMediaTime();
		id<CAMetalDrawable> next = [layer nextDrawable];
		CFTimeInterval waited = CACurrentMediaTime() - start;
		expect(next != nil, "nextDrawable returns a drawable once another thread presented one");
		expect(waited < 0.9, "nextDrawable does not sleep until its one second timeout");

		[window close];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
