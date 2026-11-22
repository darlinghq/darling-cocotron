/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * CAOpenGLLayers composited by a CARenderer into a context of its own: one
 * whose -copyCGLContextForPixelFormat: returns a context made without a share
 * context (also drawing on another thread), one that shares with the
 * renderer's context, and one that keeps the default context. The layer draws
 * a solid colour into the context it is handed; that colour has to be what the
 * renderer composites, whether or not the layer's context shares objects with
 * the renderer's, and at the layer's size after a resize. A layer that is not
 * opaque composites with its alpha channel; an opaque one does not look at it.
 * Frames drawn by another thread are composited whole (each half of a frame is
 * drawn separately, with a pause between them). Into a drawable that starts out
 * transparent (the layers of a native subwindow are drawn that way, and a Wayland
 * compositor takes the drawable's alpha as the surface's alpha), an opaque layer
 * leaves alpha 1 (times its opacity) and every pixel stays a valid premultiplied
 * colour (no colour channel above alpha), whatever alpha the layer's frame holds.
 *
 * Needs a display (Xvfb or a Wayland compositor) and OpenGL. Darling-specific:
 * on macOS the system compositor, not CARenderer, draws these layers (a
 * CARenderer does not call their drawing methods).
 */
#define GL_GLEXT_PROTOTYPES 1
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

enum { kSize = 64 };

// Private to QuartzCore: the renderer of a native subwindow clears to alpha 0.
@interface CARenderer (TransparentClear)
- (void) _setClearsToTransparent: (BOOL) value;
@end

@interface OwnContextLayer : CAOpenGLLayer {
@public
	BOOL makeOwnContext;
	BOOL shareWith;
	CGLContextObj shareContext;
	unsigned draws;
	float color[4];
	// Draws each half of the frame separately, with the GL work finished and a
	// pause in between, so that a half-finished frame is easy to catch.
	BOOL slow;
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
	glClearColor(color[0], color[1], color[2], color[3]);
	if (!slow) {
		glClear(GL_COLOR_BUFFER_BIT);
		return;
	}
	glEnable(GL_SCISSOR_TEST);
	glScissor(0, 0, 16, 32);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	usleep(300);
	glScissor(16, 0, 16, 32);
	glClear(GL_COLOR_BUFFER_BIT);
	glDisable(GL_SCISSOR_TEST);
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

static float background; // grey level of the root layer's background; 0 for none
static float clearAlpha = 1; // alpha the drawable is cleared to before the layers are drawn

static void render(CARenderer *renderer, GLubyte *pixels)
{
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, kSize, 0, kSize, -1, 1);
	glClearColor(0, 0, 0, clearAlpha);
	glClear(GL_COLOR_BUFFER_BIT);
	[renderer render];
	glReadPixels(0, 0, kSize, kSize, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

typedef struct {
	BOOL ownContext, share, async;
} Kind;

static const Kind kUnshared = {YES, NO, NO}, kUnsharedAsync = {YES, NO, YES},
	kShared = {YES, YES, NO}, kDefault = {NO, NO, NO};

// A renderer showing root, a 64x64 layer with one 32x32 CAOpenGLLayer at (16, 16).
typedef struct {
	CARenderer *renderer;
	OwnContextLayer *gl;
	GLubyte *pixels;
} Scene;

static Scene makeScene(CGLContextObj host, Kind kind)
{
	CALayer *root = [CALayer layer];
	root.bounds = CGRectMake(0, 0, kSize, kSize);
	root.anchorPoint = CGPointZero;
	root.position = CGPointZero;
	if (background > 0) {
		CGColorRef grey = CGColorCreateGenericRGB(background, background, background, 1);
		root.backgroundColor = grey;
		CGColorRelease(grey);
	}

	OwnContextLayer *gl = [OwnContextLayer layer];
	gl->makeOwnContext = kind.ownContext;
	gl->shareWith = kind.share;
	gl->shareContext = host;
	gl->color[0] = 0; gl->color[1] = 1; gl->color[2] = 0; gl->color[3] = 1;
	gl.asynchronous = kind.async;
	gl.bounds = CGRectMake(0, 0, 32, 32);
	gl.anchorPoint = CGPointZero;
	gl.position = CGPointMake(16, 16);
	[root addSublayer: gl];
	[gl setNeedsDisplay];

	Scene scene;
	scene.renderer = [CARenderer rendererWithCGLContext: host options: nil];
	scene.renderer.layer = root;
	scene.renderer.bounds = CGRectMake(0, 0, kSize, kSize);
	if (clearAlpha == 0)
		[scene.renderer _setClearsToTransparent: YES];
	scene.gl = gl;
	scene.pixels = malloc(4 * kSize * kSize);
	return scene;
}

// Composites a root with one 32x32 layer at (16, 16) and checks its centre.
static void checkComposite(CGLContextObj host, const char *what, Kind kind)
{
	background = 0;
	Scene scene = makeScene(host, kind);
	OwnContextLayer *gl = scene.gl;
	GLubyte *pixels = scene.pixels;

	char name[200];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: the layer is drawn", what);
	expect(gl->draws >= 1, name);
	snprintf(name, sizeof name, "%s: the composited layer shows its colour", what);
	expect(isColor(pixelAt(pixels, 32, 32), 0, 255, 0), name);
	snprintf(name, sizeof name, "%s: outside the layer is untouched", what);
	expect(isColor(pixelAt(pixels, 4, 4), 0, 0, 0), name);

	// A redraw with another colour reaches the screen too.
	gl->color[0] = 1; gl->color[1] = 0; gl->color[2] = 0;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: a redraw with another colour is composited", what);
	expect(isColor(pixelAt(pixels, 32, 32), 255, 0, 0), name);

	// A layer that grows shows its frame at the new size, and the size
	// changes again.
	gl.bounds = CGRectMake(0, 0, 44, 44);
	gl->color[0] = 0; gl->color[2] = 1;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: a layer resized larger shows the new frame over its whole area", what);
	expect(isColor(pixelAt(pixels, 56, 8), 0, 0, 255), name);
	gl.bounds = CGRectMake(0, 0, 20, 20);
	gl->color[1] = 1; gl->color[2] = 0; gl->color[0] = 1;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: a layer resized smaller shows the new frame", what);
	expect(isColor(pixelAt(pixels, 26, 38), 255, 255, 0), name);
	snprintf(name, sizeof name, "%s: nothing is left of the larger frame", what);
	expect(isColor(pixelAt(pixels, 56, 8), 0, 0, 0), name);
	free(pixels);
}

// A layer that is not opaque composites with its alpha channel (premultiplied
// colour) over what is behind it; an opaque one shows its colour.
static void checkAlpha(CGLContextObj host, const char *what, Kind kind)
{
	background = 0.25;
	Scene scene = makeScene(host, kind);
	OwnContextLayer *gl = scene.gl;
	GLubyte *pixels = scene.pixels;
	char name[200];

	gl.opaque = NO;
	gl->color[0] = 0; gl->color[1] = 0.5; gl->color[2] = 0; gl->color[3] = 0.5;
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: half transparent green over grey is blended", what);
	expect(isColor(pixelAt(pixels, 32, 32), 32, 160, 32), name);

	gl->color[1] = 0; gl->color[3] = 0;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: a transparent frame shows what is behind the layer", what);
	expect(isColor(pixelAt(pixels, 32, 32), 64, 64, 64), name);

	gl.opaque = YES;
	gl->color[0] = 0; gl->color[1] = 1; gl->color[2] = 0; gl->color[3] = 1;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: an opaque layer shows its colour", what);
	expect(isColor(pixelAt(pixels, 32, 32), 0, 255, 0), name);

	// Its alpha channel is not looked at, whatever the frame holds there.
	gl->color[3] = 0;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: an opaque layer shows its colour where the frame's alpha is 0", what);
	expect(isColor(pixelAt(pixels, 32, 32), 0, 255, 0), name);

	// A faded opaque layer blends with what is behind it by its opacity only.
	gl->color[3] = 0;
	gl.opacity = 0.5;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	snprintf(name, sizeof name, "%s: a half faded opaque layer is blended by its opacity", what);
	expect(isColor(pixelAt(pixels, 32, 32), 32, 160, 32), name);
	gl.opacity = 1;
	free(pixels);
	background = 0;
}

// Drawn into a drawable cleared to alpha 0, an opaque layer is opaque whatever
// alpha its frame holds, and a fade only lowers the alpha it leaves.
static void checkOpaqueLeavesAlpha(CGLContextObj host, const char *what, Kind kind)
{
	background = 0;
	clearAlpha = 0;
	Scene scene = makeScene(host, kind);
	OwnContextLayer *gl = scene.gl;
	GLubyte *pixels = scene.pixels;
	char name[200];

	gl.opaque = YES;
	gl->color[0] = 0; gl->color[1] = 1; gl->color[2] = 0; gl->color[3] = 0;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	const GLubyte *p = pixelAt(pixels, 32, 32);
	snprintf(name, sizeof name, "%s: an opaque layer drawn into a transparent drawable leaves alpha 1 (%d,%d,%d,%d)",
		what, p[0], p[1], p[2], p[3]);
	expect(isColor(p, 0, 255, 0) && p[3] > 250, name);
	p = pixelAt(pixels, 4, 4);
	snprintf(name, sizeof name, "%s: the drawable stays transparent outside the layer", what);
	expect(p[3] == 0, name);

	gl->color[3] = 1;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	p = pixelAt(pixels, 32, 32);
	snprintf(name, sizeof name, "%s: the same with a frame of alpha 1 (%d,%d,%d,%d)", what, p[0], p[1], p[2], p[3]);
	expect(isColor(p, 0, 255, 0) && p[3] > 250, name);

	gl->color[3] = 0;
	gl.opacity = 0.5;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	p = pixelAt(pixels, 32, 32);
	snprintf(name, sizeof name, "%s: a half faded opaque layer leaves half alpha and a valid premultiplied colour (%d,%d,%d,%d)",
		what, p[0], p[1], p[2], p[3]);
	expect(abs(p[3] - 128) < 8 && p[1] <= p[3] + 2 && isColor(p, 0, 128, 0), name);
	gl.opacity = 1;

	// A layer that is not opaque keeps what its premultiplied frame says.
	gl.opaque = NO;
	gl->color[0] = 0; gl->color[1] = 0.5; gl->color[2] = 0; gl->color[3] = 0.5;
	[gl setNeedsDisplay];
	render(scene.renderer, pixels);
	p = pixelAt(pixels, 32, 32);
	snprintf(name, sizeof name, "%s: a half transparent layer leaves its own alpha (%d,%d,%d,%d)", what, p[0], p[1], p[2], p[3]);
	expect(abs(p[3] - 128) < 8 && isColor(p, 0, 128, 0), name);
	clearAlpha = 1;
	free(pixels);
}

static volatile int stopDrawing;

static void *drawFrames(void *argument)
{
	OwnContextLayer *gl = argument;
	BOOL green = NO;
	while (!stopDrawing) {
		green = !green;
		gl->color[0] = green ? 0 : 1;
		gl->color[1] = green ? 1 : 0;
		[gl display];
	}
	return NULL;
}

// Frames that another thread draws are composited whole: each half of a frame
// is drawn separately, and the two halves seen by the compositor always agree.
static void checkWholeFrames(CGLContextObj host, const char *what, Kind kind)
{
	background = 0;
	Scene scene = makeScene(host, kind);
	OwnContextLayer *gl = scene.gl;
	gl->slow = YES;
	GLubyte *pixels = scene.pixels;
	char name[200];

	render(scene.renderer, pixels);
	pthread_t thread;
	pthread_create(&thread, NULL, drawFrames, gl);
	int torn = 0, empty = 0, changes = 0;
	GLubyte lastRed = 0;
	for (int i = 0; i < 300; i++) {
		render(scene.renderer, pixels);
		const GLubyte *left = pixelAt(pixels, 20, 32), *right = pixelAt(pixels, 44, 32);
		if (abs(left[0] - right[0]) > 8 || abs(left[1] - right[1]) > 8 || abs(left[2] - right[2]) > 8)
			torn++;
		if (left[0] + left[1] + left[2] < 100 || right[0] + right[1] + right[2] < 100)
			empty++;
		if (abs(left[0] - lastRed) > 8) {
			changes++;
			lastRed = left[0];
		}
	}
	stopDrawing = 1;
	pthread_join(thread, NULL);
	stopDrawing = 0;
	snprintf(name, sizeof name, "%s: another thread draws frames (%u)", what, gl->draws);
	expect(gl->draws > 10, name);
	snprintf(name, sizeof name, "%s: no composited frame has two halves that differ (%d of 300)", what, torn);
	expect(torn == 0, name);
	snprintf(name, sizeof name, "%s: the layer is never empty while frames are drawn (%d of 300)", what, empty);
	expect(empty == 0, name);
	snprintf(name, sizeof name, "%s: the compositor sees new frames (%d changes)", what, changes);
	expect(changes >= 1, name);
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

		checkComposite(host, "own context without a share context", kUnshared);
		checkComposite(host, "own context without a share context, asynchronous", kUnsharedAsync);
		checkComposite(host, "own context sharing with the renderer's context", kShared);
		checkComposite(host, "default context", kDefault);

		checkAlpha(host, "own context without a share context", kUnshared);
		checkAlpha(host, "own context sharing with the renderer's context", kShared);
		checkAlpha(host, "default context", kDefault);

		checkOpaqueLeavesAlpha(host, "own context without a share context", kUnshared);
		checkOpaqueLeavesAlpha(host, "own context sharing with the renderer's context", kShared);
		checkOpaqueLeavesAlpha(host, "default context", kDefault);

		checkWholeFrames(host, "own context without a share context", kUnshared);
		checkWholeFrames(host, "own context sharing with the renderer's context", kShared);

		CGLSetCurrentContext(NULL);
		CGLReleaseContext(host);
		CGLReleasePixelFormat(format);
	}
	if (failures == 0)
		printf("PASS\n");
	return failures ? 1 : 0;
}
