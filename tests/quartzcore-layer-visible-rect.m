/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Every CALayer answers -visibleRect: the part of its bounds that shows
 * through the CAScrollLayers above it, in its own coordinates. A layer with no
 * scroll layer above it shows all of its bounds; masksToBounds on a parent
 * does not clip it. (CAScrollLayer declares visibleRect publicly; layers
 * under a scroll layer, such as an OpenGL layer that sizes its drawing to
 * what is visible, ask it too.) The expected values are those observed on
 * macOS 26.7.3.
 *
 * Usage: quartzcore-layer-visible-rect
 * Prints PASS/FAIL lines; exit status 1 on failure. No ARC.
 */
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
	printf("%s %s\n", ok ? "PASS" : "FAIL", what);
	if (!ok)
		failures++;
}

static CGRect visibleRect(CALayer *layer)
{
	NSRect rect = [[layer valueForKey: @"visibleRect"] rectValue];
	return CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	CALayer *alone = [CALayer layer];
	alone.frame = CGRectMake(5, 5, 30, 40);
	expect([alone respondsToSelector: @selector(visibleRect)], "a layer responds to visibleRect");
	expect(CGRectEqualToRect(visibleRect(alone), CGRectMake(0, 0, 30, 40)),
		   "a layer with no parent shows its bounds");
	alone.bounds = CGRectMake(7, 8, 30, 40);
	expect(CGRectEqualToRect(visibleRect(alone), CGRectMake(7, 8, 30, 40)),
		   "the bounds origin is part of the visible rect");

	CALayer *clipper = [CALayer layer];
	clipper.frame = CGRectMake(10, 10, 50, 50);
	clipper.masksToBounds = YES;
	CALayer *kid = [CALayer layer];
	kid.frame = CGRectMake(-20, -20, 100, 100);
	[clipper addSublayer: kid];
	expect(CGRectEqualToRect(visibleRect(kid), CGRectMake(0, 0, 100, 100)),
		   "masksToBounds on a parent does not clip the visible rect");

	CAScrollLayer *scroll = [CAScrollLayer layer];
	scroll.frame = CGRectMake(0, 0, 100, 100);
	CALayer *content = [CALayer layer];
	content.frame = CGRectMake(0, 0, 300, 300);
	[scroll addSublayer: content];
	expect(CGRectEqualToRect(visibleRect(scroll), CGRectMake(0, 0, 100, 100)),
		   "a scroll layer shows its bounds");
	expect(CGRectEqualToRect(visibleRect(content), CGRectMake(0, 0, 100, 100)),
		   "a layer in a scroll layer shows the part the scroll layer shows");

	scroll.bounds = CGRectMake(50, 60, 100, 100);
	expect(CGRectEqualToRect(visibleRect(scroll), CGRectMake(50, 60, 100, 100)),
		   "a scrolled scroll layer shows its scrolled bounds");
	expect(CGRectEqualToRect(visibleRect(content), CGRectMake(50, 60, 100, 100)),
		   "a layer in a scrolled scroll layer shows the scrolled part");

	[pool drain];
	return failures != 0;
}
