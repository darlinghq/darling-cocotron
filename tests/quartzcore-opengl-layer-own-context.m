/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * A CAOpenGLLayer whose -copyCGLContextForPixelFormat: returns a context made
 * without a share context, and one that keeps the default context, drawn by a
 * CARenderer into a context of its own. The layer draws a solid colour into
 * the context it is handed; that colour has to be what the renderer composites,
 * whether or not the layer's context shares objects with the renderer's.
 *
 * Needs a display (Xvfb) and OpenGL. Darling-specific: on macOS the system
 * compositor, not CARenderer, draws these layers (a CARenderer does not call
 * their drawing methods).
 */
#define GL_GLEXT_PROTOTYPES 1
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

enum { kSize = 64 };

@interface OwnContextLayer : CAOpenGLLayer {
@public
	BOOL makeOwnContext;
	BOOL shareWith;
	CGLContextObj shareContext;
	unsigned draws;
	float color[3];
}
@end

@implementation OwnContextLayer
- (CGLContextObj) copyCGLContextForPixelFormat: (CGLPixelFormatObj) pf
{
	if (!makeOwnContext)
		return [super copyCGLContextForPixelFormat: pf];
	CGLContextObj ctx = NULL;
	CGLCreateContext(pf, shareWith ? shareContext : NULL, &ctx);
	return ctx;
}

- (void) drawInCGLContext: (CGLContextObj) ctx pixelFormat: (CGLPixelFormatObj) pf
	forLayerTime: (CFTimeInterval) t displayTime: (const CVTimeStamp *) ts
{
	++draws;
	glClearColor(color[0], color[1], color[2], 1);
	glClear(GL_COLOR_BUFFER_BIT);
}
@end

static int failures;

static void expect(BOOL ok, const char *what)
{
	if (!ok) {
		fprintf(stderr, "FAIL: %s\n", what);
		failures++;
	}
}

static const GLubyte *pixelAt(const GLubyte *pixels, int x, int yFromTop)
{
	return pixels + 4 * ((kSize - 1 - yFromTop) * kSize + x);
}

static BOOL isColor(const GLubyte *p, int r, int g, int b)
{
	return abs(p[0] - r) < 8 && abs(p[1] - g) < 8 && abs(p[2] - b) < 8;
}

static void render(CARenderer *renderer, GLubyte *pixels)
{
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, kSize, 0, kSize, -1, 1);
	glClearColor(0, 0, 0, 1);
	glClear(GL_COLOR_BUFFER_BIT);
	[renderer render];
	glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

// Composites a root with one 32x32 layer at (16, 16) and checks its centre.
static void checkComposite(CGLContextObj host, const char *what, BOOL ownContext, BOOL share, BOOL async)
{
	CALayer *root = [CALayer layer];
	root.bounds = CGRectMake(0, 0, kSize, kSize);
	root.anchorPoint = CGPointZero;
	root.position = CGPointZero;

	OwnContextLayer *gl = [OwnContextLayer layer];
	gl->makeOwnContext = ownContext;
	gl->shareWith = share;
	gl->shareContext = host;
	gl->color[0] = 0; gl->color[1] = 1; gl->color[2] = 0;
	gl.asynchronous = async;
	gl.bounds = CGRectMake(0, 0, 32, 32);
	gl.anchorPoint = CGPointZero;
	gl.position = CGPointMake(16, 16);
	[root addSublayer: gl];
	[gl setNeedsDisplay];

	CARenderer *renderer = [CARenderer rendererWithCGLContext: host options: nil];
	renderer.layer = root;
	renderer.bounds = CGRectMake(0, 0, kSize, kSize);
	GLubyte *pixels = malloc(4 * kSize * kSize);

	char name[200];
	render(renderer, pixels);
	snprintf(name, sizeof name, "%s: the layer is drawn", what);
	expect(gl->draws >= 1, name);
	snprintf(name, sizeof name, "%s: the composited layer shows its colour", what);
	expect(isColor(pixelAt(pixels, 32, 32), 0, 255, 0), name);
	snprintf(name, sizeof name, "%s: outside the layer is untouched", what);
	expect(isColor(pixelAt(pixels, 4, 4), 0, 0, 0), name);

	// A redraw with another colour reaches the screen too.
	gl->color[0] = 1; gl->color[1] = 0; gl->color[2] = 0;
	[gl setNeedsDisplay];
	render(renderer, pixels);
	snprintf(name, sizeof name, "%s: a redraw with another colour is composited", what);
	expect(isColor(pixelAt(pixels, 32, 32), 255, 0, 0), name);
	free(pixels);
}

int main(void)
{
	@autoreleasepool {
		[NSApplication sharedApplication]; // registers the window system's display with CGL

		CGLPixelFormatAttribute attributes[] = {0};
		CGLPixelFormatObj format;
		GLint screens;
		CGLContextObj host;
		expect(CGLChoosePixelFormat(attributes, &format, &screens) == kCGLNoError, "CGLChoosePixelFormat");
		expect(CGLCreateContext(format, NULL, &host) == kCGLNoError, "CGLCreateContext");
		expect(CGLSetCurrentContext(host) == kCGLNoError, "CGLSetCurrentContext");

		GLuint framebuffer, colorbuffer;
		glGenFramebuffers(1, &framebuffer);
		glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
		glGenRenderbuffers(1, &colorbuffer);
		glBindRenderbuffer(GL_RENDERBUFFER, colorbuffer);
		glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, kSize, kSize);
		glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, colorbuffer);
		expect(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "offscreen framebuffer");
		glViewport(0, 0, kSize, kSize);

		checkComposite(host, "own context without a share context", YES, NO, NO);
		checkComposite(host, "own context without a share context, asynchronous", YES, NO, YES);
		checkComposite(host, "own context sharing with the renderer's context", YES, YES, NO);
		checkComposite(host, "default context", NO, NO, NO);

		CGLSetCurrentContext(NULL);
		CGLReleaseContext(host);
		CGLReleasePixelFormat(format);
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
