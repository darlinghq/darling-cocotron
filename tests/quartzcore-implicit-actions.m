/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Implicit actions: a layer outside a window-hosted layer tree never animates
 * a property change (with or without an explicit transaction), a layer in a
 * window-hosted tree does, and explicit animations always work.
 * Observed on macOS 26.7.3 and 10.14.4 (see MC12 in MAC-EVIDENCE.md).
 *
 * Needs a display (Xvfb is enough) for the hosted case. The standalone cases
 * need none.
 */
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
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
		CALayer *a = [CALayer layer];
		a.opacity = 0.5;
		a.position = CGPointMake(10, 10);
		a.bounds = CGRectMake(0, 0, 20, 20);
		expect([a animationKeys].count == 0, "standalone layer: no implicit animation");
		expect([a actionForKey: @"opacity"] == nil, "standalone layer: actionForKey is nil");

		CALayer *b = [CALayer layer];
		[CATransaction begin];
		b.opacity = 0.5;
		[CATransaction commit];
		expect([b animationKeys].count == 0,
			"standalone layer: no implicit animation inside an explicit transaction");

		CALayer *root = [CALayer layer];
		CALayer *sub = [CALayer layer];
		[root addSublayer: sub];
		sub.opacity = 0.5;
		expect([sub animationKeys].count == 0, "sublayer of a standalone root: none");

		CALayer *m = [CALayer layer];
		[m addAnimation: [CABasicAnimation animationWithKeyPath: @"opacity"] forKey: @"manual"];
		expect([[m animationKeys] containsObject: @"manual"], "explicit addAnimation works");

		[NSApplication sharedApplication];
		NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 60, 60)
			styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO];
		[w setReleasedWhenClosed: NO];
		NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 60, 60)];
		host.layer = [CALayer layer];
		host.wantsLayer = YES;
		w.contentView = host;
		CALayer *hs = [CALayer layer];
		[host.layer addSublayer: hs];
		[[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
		hs.opacity = 0.5;
		expect([hs actionForKey: @"opacity"] != nil, "hosted sublayer: actionForKey non-nil");
		expect([[hs animationKeys] containsObject: @"opacity"], "hosted sublayer: implicit animation added");

		CALayer *detached = [CALayer layer];
		detached.opacity = 0.5;
		expect([detached animationKeys].count == 0,
			"standalone layer while a window exists: still no animation");
		[w close];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
