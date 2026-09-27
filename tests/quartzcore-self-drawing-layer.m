// Non-GUI regression test for the CALayer self-draw hook
// (-_drawLayerContents:bounds:opacity:), the path CAMetalLayer uses to get its
// GPU-rendered texture composited.
//
// Renders offscreen into an FBO and checks that a layer which overrides the hook
// is reached even though its contents is NULL (the case the contents-based path
// used to skip), and that layers which do not override it are unaffected.

#define GL_GLEXT_PROTOTYPES 1
#import <OpenGL/OpenGL.h>
#import <OpenGL/glext.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

// Declared instead of imported: CALayerInternal.h is private to the QuartzCore
// build, and all this needs is the selector to override.
@interface CALayer (SelfDrawHookTest)
- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity;
@end

// Draws a solid blue quad over the whole layer and records the call.
@interface SelfDrawingLayer : CALayer {
	NSUInteger _drawCount;
	CGFloat _lastOpacity;
}
@property(readonly) NSUInteger drawCount;
@property(readonly) CGFloat lastOpacity;
@end

@implementation SelfDrawingLayer
@synthesize drawCount = _drawCount;
@synthesize lastOpacity = _lastOpacity;

- (BOOL) _drawLayerContents: (CGRect) bounds opacity: (CGFloat) opacity {
	_drawCount++;
	_lastOpacity = opacity;

	const GLfloat vertices[4 * 2] = {0, 0, bounds.size.width, 0,
									 0, bounds.size.height,
									 bounds.size.width, bounds.size.height};

	glDisable(GL_TEXTURE_2D);
	glVertexPointer(2, GL_FLOAT, 0, vertices);
	glColor4f(0, 0, opacity, opacity);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

	return YES;
}
@end

#define kSide 32
#define kWidth (kSide * 3)
#define kHeight kSide

static int failures = 0;

static void expect(int condition, const char *what) {
	if (condition)
		return;
	fprintf(stderr, "FAIL: %s\n", what);
	failures++;
}

static void readPixel(GLint x, GLint y, unsigned char *pixel) {
	glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
}

static int pixelIs(const unsigned char *pixel, int r, int g, int b) {
	return pixel[0] == r && pixel[1] == g && pixel[2] == b && pixel[3] == 255;
}

static CALayer *makeLayer(CGFloat x) {
	CALayer *layer = [CALayer layer];
	layer.bounds = CGRectMake(0, 0, kSide, kSide);
	layer.anchorPoint = CGPointZero;
	layer.position = CGPointMake(x, 0);
	return layer;
}

static CGImageRef makeGreenImage(void) {
	CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(
			NULL, kSide, kSide, 8, 0, space,
			kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
	CGColorSpaceRelease(space);
	if (context == NULL)
		return NULL;

	CGContextSetRGBFillColor(context, 0, 1, 0, 1);
	CGContextFillRect(context, CGRectMake(0, 0, kSide, kSide));

	CGImageRef image = CGBitmapContextCreateImage(context);
	CGContextRelease(context);
	return image;
}

int main(void) {
	@autoreleasepool {
		CGLPixelFormatAttribute attributes[1] = {0};
		CGLPixelFormatObj pixelFormat;
		GLint visualCount = 0;

		if (CGLChoosePixelFormat(attributes, &pixelFormat, &visualCount) != kCGLNoError
				|| visualCount == 0) {
			fprintf(stderr, "CGLChoosePixelFormat failed\n");
			return 1;
		}

		CGLContextObj context;
		if (CGLCreateContext(pixelFormat, NULL, &context) != kCGLNoError) {
			fprintf(stderr, "CGLCreateContext failed\n");
			return 2;
		}
		CGLSetCurrentContext(context);

		GLuint target, fbo;
		glGenTextures(1, &target);
		glBindTexture(GL_TEXTURE_2D, target);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, kWidth, kHeight, 0, GL_RGBA,
					 GL_UNSIGNED_BYTE, NULL);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

		glGenFramebuffers(1, &fbo);
		glBindFramebuffer(GL_FRAMEBUFFER, fbo);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
							  target, 0);

		if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
			fprintf(stderr, "framebuffer incomplete\n");
			return 3;
		}

		glPixelStorei(GL_PACK_ALIGNMENT, 1);

		// A self-drawing layer, nested under a half-opaque parent so the
		// accumulated opacity can be checked too.
		CALayer *root = makeLayer(0);

		CALayer *parent = makeLayer(0);
		parent.opacity = 0.5;
		[root addSublayer: parent];

		SelfDrawingLayer *selfDrawing = [[SelfDrawingLayer alloc] init];
		selfDrawing.bounds = CGRectMake(0, 0, kSide, kSide);
		selfDrawing.anchorPoint = CGPointZero;
		selfDrawing.position = CGPointZero;
		[parent addSublayer: selfDrawing];

		// A layer that does not override the hook and has no contents: the
		// contents path must still skip it.
		CALayer *empty = makeLayer(kSide);
		[root addSublayer: empty];

		// A layer that does not override the hook and does have contents: the
		// upload path must still run.
		CALayer *image = makeLayer(kSide * 2);
		CGImageRef green = makeGreenImage();
		image.contents = (id) green;
		[root addSublayer: image];

		CARenderer *renderer = [CARenderer rendererWithCGLContext: context
														  options: nil];
		renderer.bounds = CGRectMake(0, 0, kWidth, kHeight);
		renderer.layer = root;
		[renderer render];
		glFinish();

		unsigned char drawn[4], skipped[4], uploaded[4];
		readPixel(kSide / 2, kSide / 2, drawn);
		readPixel(kSide + kSide / 2, kSide / 2, skipped);
		readPixel(kSide * 2 + kSide / 2, kSide / 2, uploaded);

		GLenum glError = glGetError();

		[selfDrawing release];
		if (green != NULL)
			CGImageRelease(green);
		[root release];

		expect(glError == GL_NO_ERROR, "rendering left a GL error");
		expect(selfDrawing.drawCount == 1, "the overriding layer's hook ran exactly once");
		expect(selfDrawing.lastOpacity == 0.5, "the hook got the accumulated opacity");
		expect(selfDrawing.contents == nil, "the overriding layer has no contents");
		expect(pixelIs(drawn, 0, 0, 255), "the overriding layer drew, despite contents == NULL");
		expect(pixelIs(skipped, 0, 0, 0), "a non-overriding layer with no contents still draws nothing");
		expect(pixelIs(uploaded, 0, 255, 0), "a non-overriding layer still uploads its contents");

		CGLSetCurrentContext(NULL);
		CGLDestroyContext(context);

		return failures == 0 ? 0 : 1;
	}
}
