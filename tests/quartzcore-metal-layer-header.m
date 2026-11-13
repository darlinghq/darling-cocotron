/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Compile test: <QuartzCore/CAMetalLayer.h> alone must declare the
 * CAMetalDrawable protocol in full, so a client can use -texture and -present
 * on the value returned by -nextDrawable. Fails to compile without the fix.
 * Nothing is called at run time.
 */
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>

static id<MTLTexture> drawableTexture(CAMetalLayer *layer) {
	id<CAMetalDrawable> drawable = [layer nextDrawable];
	[drawable present];
	return drawable.texture;
}

int main(void) {
	id<MTLTexture> (*unused)(CAMetalLayer *) = drawableTexture;
	(void) unused;
	printf("PASS\n");
	return 0;
}
