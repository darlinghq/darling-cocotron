// Copyright (C) 2026 Lubos Dolezel
//
// A layer's contents are drawn from a texture the layer owns. CALayerContext names the textures of
// its tree before it renders, but layout and display code that runs inside the render may add
// sublayers, which then have no name. CARenderer uploads a layer's image only when it changed since
// the last upload (or the layer has no name, or its texture does not exist yet), and glTexImage2D
// fills the texture bound to the target:
// https://registry.khronos.org/OpenGL-Refpages/gl2.1/xhtml/glTexImage2D.xml
// A layer without a texture of its own must therefore not be drawn through the texture bound from
// another layer: its upload would replace that picture, and the layer whose contents did not change
// would show the other layer's image from the next frame on. A layer displays its own contents:
// https://developer.apple.com/documentation/quartzcore/calayer/contents
// The root has blue contents and adds a red sublayer with its own contents while the frame is being
// laid out, so the sublayer is created after the context's naming pass. The tree is drawn twice
// through a CALayerContext; the second frame uploads nothing for the root and must look like the
// first. (A bare CARenderer names no layer and uploads every frame, so it cannot show this.)
// Needs a GL-capable backend (X11 on Xvfb).
// Exit 2/3: no GL context; 4: GL error; 5: second frame differs from the first;
// 6: first frame wrong; 7: no layer context; 0: correct.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CALayerContext.h>
#include <stdio.h>

#define SIZE 64

@interface CALayerContext (LateSublayerFixture)
- (void)_drawLayerTree:(CALayer *)layer inRect:(CGRect)rect topRowFirst:(BOOL)topRowFirst;
@end

static CGImageRef solidImage(CGFloat r, CGFloat g, CGFloat b) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, 4, 4, 8, 0, space,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(ctx, r, g, b, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, 4, 4));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return image;
}

@interface LateSublayerRoot : CALayer {
    BOOL _added;
}
@end

@implementation LateSublayerRoot
- (void)layoutSublayers {
    if (_added)
        return;
    _added = YES;
    CALayer *late = [CALayer layer];
    late.anchorPoint = CGPointZero;
    late.position = CGPointMake(SIZE / 2, 0);
    late.bounds = CGRectMake(0, 0, SIZE / 2, SIZE);
    CGImageRef red = solidImage(1, 0, 0);
    late.contents = (id)red;
    CGImageRelease(red);
    [self addSublayer:late];
}
@end

static BOOL isColor(const unsigned char *p, int r, int g, int b) {
    return p[0] > r - 20 && p[0] < r + 20 && p[1] > g - 20 && p[1] < g + 20 &&
           p[2] > b - 20 && p[2] < b + 20;
}

static void readColors(CALayerContext *layerContext, CALayer *root, unsigned char *left,
                       unsigned char *right) {
    [layerContext _drawLayerTree:root inRect:CGRectMake(0, 0, SIZE, SIZE) topRowFirst:NO];
    glFinish();
    glReadPixels(SIZE / 4, SIZE / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, left);
    glReadPixels(3 * SIZE / 4, SIZE / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, right);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, SIZE, SIZE);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:NSBorderlessWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame:frame];
        [window setContentView:view];
        [view release];
        NSOpenGLContext *context = [view openGLContext];
        if (context == nil || [context CGLContextObj] == NULL)
            return 2;
        [view lockFocus];
        if (CGLGetCurrentContext() != [context CGLContextObj])
            return 3;

        glViewport(0, 0, SIZE, SIZE);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, SIZE, 0, SIZE, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glPixelStorei(GL_PACK_ALIGNMENT, 1);

        LateSublayerRoot *root = [LateSublayerRoot layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, SIZE, SIZE);
        CGImageRef blue = solidImage(0, 0, 1);
        root.contents = (id)blue;
        CGImageRelease(blue);
        [root setNeedsLayout];

        CALayerContext *layerContext =
                [[CALayerContext alloc] initWithFrame:CGRectMake(0, 0, SIZE, SIZE)];
        if (layerContext == nil)
            return 7;
        [layerContext setLayer:root];

        unsigned char left1[4], right1[4], left2[4], right2[4];
        readColors(layerContext, root, left1, right1);
        readColors(layerContext, root, left2, right2);
        GLenum error = glGetError();
        [layerContext release];
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];

        if (error != GL_NO_ERROR) {
            fprintf(stderr, "OpenGL error: %u\n", error);
            return 4;
        }
        // The root is blue everywhere and the red sublayer covers its right half.
        if (!isColor(left1, 0, 0, 255) || !isColor(right1, 255, 0, 0)) {
            fprintf(stderr, "first frame: left=(%u,%u,%u) right=(%u,%u,%u)\n", left1[0], left1[1],
                    left1[2], right1[0], right1[1], right1[2]);
            return 6;
        }
        if (!isColor(left2, 0, 0, 255) || !isColor(right2, 255, 0, 0)) {
            fprintf(stderr, "second frame: left=(%u,%u,%u) right=(%u,%u,%u)\n", left2[0], left2[1],
                    left2[2], right2[0], right2[1], right2[2]);
            return 5;
        }
        puts("PASS: a sublayer added during layout draws from its own texture");
        return 0;
    }
}
