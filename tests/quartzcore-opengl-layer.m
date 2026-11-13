/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAOpenGLLayer in a window-hosted layer tree: a synchronous layer is drawn
 * after -setNeedsDisplay and then left alone, an asynchronous layer is drawn
 * again on every frame, the frame is drawn into the layer's own framebuffer
 * (a cleared colour is read back from it inside -drawInCGLContext:), the
 * default context shares objects with the hosting layer context, and the
 * OpenGL profile pixel-format constants have the values macOS declares.
 *
 * Needs a display (Xvfb) and OpenGL. Does not check the composited pixels.
 */
#define GL_GLEXT_PROTOTYPES 1
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

@interface CountingGLLayer : CAOpenGLLayer {
@public
	unsigned draws;
	unsigned char lastPixel[4];
	GLint lastFramebuffer;
}
@end

@implementation CountingGLLayer
- (void) drawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf
	forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts
{
	++draws;
	glGetIntegerv(GL_FRAMEBUFFER_BINDING, &lastFramebuffer);
	glClearColor(1, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, lastPixel);
}
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
		expect(NSOpenGLPFAOpenGLProfile == 99, "NSOpenGLPFAOpenGLProfile");
		expect(NSOpenGLProfileVersionLegacy == 0x1000, "NSOpenGLProfileVersionLegacy");
		expect(NSOpenGLProfileVersion3_2Core == 0x3200, "NSOpenGLProfileVersion3_2Core");
		expect(NSOpenGLProfileVersion4_1Core == 0x4100, "NSOpenGLProfileVersion4_1Core");

		[NSApplication sharedApplication];
		NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 64, 64)
			styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO];
		[window setReleasedWhenClosed: NO];
		NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 64, 64)];
		host.layer = [CALayer layer];
		host.wantsLayer = YES;
		[window setContentView: host];

		CountingGLLayer *sync = [CountingGLLayer layer];
		sync.bounds = CGRectMake(0, 0, 32, 32);
		[host.layer addSublayer: sync];
		spin(0.1);
		[sync setNeedsDisplay];
		spin(0.3);
		expect(sync->draws >= 1, "synchronous layer is drawn after setNeedsDisplay");
		expect(sync->lastFramebuffer != 0, "drawing goes to the layer's own framebuffer");
		expect(sync->lastPixel[0] == 255 && sync->lastPixel[1] == 0 && sync->lastPixel[2] == 0,
			"the cleared colour is in the framebuffer");
		unsigned settled = sync->draws;
		spin(0.3);
		expect(sync->draws == settled, "synchronous layer is not redrawn without setNeedsDisplay");

		CountingGLLayer *async = [CountingGLLayer layer];
		async.bounds = CGRectMake(0, 0, 32, 32);
		async.asynchronous = YES;
		[host.layer addSublayer: async];
		[async setNeedsDisplay];
		spin(0.5);
		expect(async->draws >= 5, "asynchronous layer is redrawn every frame");

		CGLPixelFormatObj pf = [async copyCGLPixelFormatForDisplayMask: 0];
		CGLContextObj ctx = [async copyCGLContextForPixelFormat: pf];
		expect(ctx != NULL, "default context is created");
		// Two default contexts of a hosted layer share objects with each other
		// through the context of the window that hosts the layer.
		CGLContextObj other = [async copyCGLContextForPixelFormat: pf];
		expect(other != NULL, "second default context is created");
		if (ctx != NULL && other != NULL) {
			CGLContextObj previous = CGLGetCurrentContext();
			GLuint texture = 0;
			CGLSetCurrentContext(ctx);
			glGenTextures(1, &texture);
			glBindTexture(GL_TEXTURE_2D, texture);
			unsigned char texel[4] = {0, 0, 0, 0};
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, texel);
			glFinish();
			CGLSetCurrentContext(other);
			expect(glIsTexture(texture), "default contexts share objects");
			// Control: a context created without a share context does not see it.
			CGLContextObj isolated = NULL;
			CGLCreateContext(pf, NULL, &isolated);
			if (isolated != NULL) {
				CGLSetCurrentContext(isolated);
				expect(!glIsTexture(texture), "an unshared context does not see the texture");
				CGLDestroyContext(isolated);
			}
			CGLSetCurrentContext(ctx);
			glDeleteTextures(1, &texture);
			CGLSetCurrentContext(previous);
		}
		if (other != NULL)
			[async releaseCGLContext: other];
		[async releaseCGLContext: ctx];

		[window close];
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
