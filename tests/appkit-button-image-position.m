/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Giving a button (cell) an image while its image position is NSNoImage, as a
 * new button's is, sets the position to NSImageOnly, so the image is drawn
 * (test_quirk_set_image_shows_image). A position set before is kept, and
 * setting no image leaves NSNoImage. Observed on macOS 10.14.4 and 26.7.3
 * through the public API; macOS 10.14.4 also does it after NSNoImage was set
 * explicitly (26.7.3 then keeps NSNoImage), which is followed here.
 *
 * The test also draws an unbordered button given a red image into a bitmap
 * and checks the image shows.
 *
 * No display needed. No ARC. Prints PASS/FAIL lines.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expectPosition(NSCellImagePosition got, NSCellImagePosition expected, const char *what)
{
	BOOL ok = got == expected;
	printf("%s %s: %ld (expected %ld)\n", ok ? "PASS" : "FAIL", what, (long) got, (long) expected);
	if (!ok)
		failures++;
}

static NSImage *redImage(void)
{
	NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(16, 16)] autorelease];
	[image lockFocus];
	[[NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1] setFill];
	NSRectFill(NSMakeRect(0, 0, 16, 16));
	[image unlockFocus];
	return image;
}

static void test_quirk_set_image_shows_image(void)
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)] autorelease];
	expectPosition([button imagePosition], NSNoImage, "a new button has no image position");
	[button setImage:redImage()];
	expectPosition([button imagePosition], NSImageOnly, "a new button given an image");

	NSButtonCell *cell = [[[NSButtonCell alloc] initTextCell:@""] autorelease];
	[cell setImage:redImage()];
	expectPosition([cell imagePosition], NSImageOnly, "a text button cell given an image");

	button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)] autorelease];
	[button setImagePosition:NSImageLeft];
	[button setImage:redImage()];
	expectPosition([button imagePosition], NSImageLeft, "a position set before the image is kept");

	cell = [[[NSButtonCell alloc] initTextCell:@"t"] autorelease];
	[cell setImage:nil];
	expectPosition([cell imagePosition], NSNoImage, "no image leaves no image position");

	button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)] autorelease];
	[button setImage:redImage()];
	[button setImagePosition:NSNoImage];
	expectPosition([button imagePosition], NSNoImage, "NSNoImage set after the image");
	[button setImage:redImage()];
	expectPosition([button imagePosition], NSImageOnly, "an image given again after NSNoImage (10.14.4)");
}

static void test_image_drawn(void)
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 30, 30)] autorelease];
	[button setBordered:NO];
	[button setTitle:@""];
	[button setImage:redImage()];

	NSBitmapImageRep *rep = [button bitmapImageRepForCachingDisplayInRect:[button bounds]];
	[button cacheDisplayInRect:[button bounds] toBitmapImageRep:rep];
	NSInteger scale = [rep pixelsWide] / 30;

	NSColor *center = [[rep colorAtX:15 * scale y:15 * scale] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	BOOL ok = [center alphaComponent] > 0.9 && [center redComponent] > 0.8 && [center greenComponent] < 0.3 &&
	          [center blueComponent] < 0.3;
	printf("%s the button draws its image: center %.2f %.2f %.2f alpha %.2f\n", ok ? "PASS" : "FAIL",
	       [center redComponent], [center greenComponent], [center blueComponent], [center alphaComponent]);
	if (!ok)
		failures++;
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication];
		test_quirk_set_image_shows_image();
		test_image_drawn();
	}
	printf("%s\n", failures ? "FAIL" : "PASS");
	return failures ? 1 : 0;
}
