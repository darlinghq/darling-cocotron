// Copyright (C) 2026 Lubos Dolezel
//
// CALayer.zPosition is the layer's position on the z axis; its default is 0. The
// documentation says that changing it changes the front-to-back order of layers on
// screen, that a higher value puts the layer nearer the viewer than layers with a
// lower value, and that this can change which of two layers with overlapping
// frames is visible:
// https://developer.apple.com/documentation/quartzcore/calayer/zposition
// So of two overlapping siblings the one with the higher zPosition is on top,
// whatever its place in the sublayers array. Sublayers are otherwise composited
// back to front in array order, so with equal zPosition a later one is on top.
// The documentation does not define a NaN zPosition. This renderer treats it as 0
// (GUESS, pinned by the fourth pair below).
// Four overlapping pairs or triples on a 64x64 surface:
//   A (0,0):   red, zPosition 1, added first;  green, 0, added second   -> red
//   B (30,0):  blue, 0, added first;  yellow, 0, added second          -> yellow
//   C (0,30):  cyan, 0, added first;  magenta, -1, added second        -> cyan
//   D (30,30): blue, NaN, first;  white, 1, second;  green, 0, third    -> white
// Needs a GL-capable backend (X11 on Xvfb).
// Exit 2/3: no GL context; 4: GL error; 5: zPosition ignored (array order
// decided the first or third pair); 6: equal zPosition not in array order;
// 7: any other colour; 8: a NaN zPosition put its layer over a higher one; 0: correct.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

static BOOL is(const unsigned char *p, int r, int g, int b) {
    return (r ? p[0] > 200 : p[0] < 20) && (g ? p[1] > 200 : p[1] < 20) &&
           (b ? p[2] > 200 : p[2] < 20);
}

static CALayer *square(CGFloat x, CGFloat y, CGFloat r, CGFloat g, CGFloat b, CGFloat z) {
    CGColorRef color = CGColorCreateGenericRGB(r, g, b, 1);
    CALayer *layer = [CALayer layer];

    layer.anchorPoint = CGPointZero;
    layer.position = CGPointMake(x, y);
    layer.bounds = CGRectMake(0, 0, 20, 20);
    layer.backgroundColor = color;
    layer.zPosition = z;
    CGColorRelease(color);
    return layer;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, 64, 64);
        NSWindow *window = [[NSWindow alloc] initWithContentRect: frame
                                                      styleMask: NSBorderlessWindowMask
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];
        NSOpenGLView *view = [[NSOpenGLView alloc] initWithFrame: frame];
        [window setContentView: view];
        [view release];
        NSOpenGLContext *context = [view openGLContext];
        if (context == nil || [context CGLContextObj] == NULL)
            return 2;
        [view lockFocus];
        if (CGLGetCurrentContext() != [context CGLContextObj])
            return 3;

        glViewport(0, 0, 64, 64);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, 64, 0, 64, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);

        CALayer *root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, 64, 64);
        [root addSublayer: square(0, 0, 1, 0, 0, 1)];
        [root addSublayer: square(0, 0, 0, 1, 0, 0)];
        [root addSublayer: square(30, 0, 0, 0, 1, 0)];
        [root addSublayer: square(30, 0, 1, 1, 0, 0)];
        [root addSublayer: square(0, 30, 0, 1, 1, 0)];
        [root addSublayer: square(0, 30, 1, 0, 1, -1)];
        [root addSublayer: square(30, 30, 0, 0, 1, NAN)];
        [root addSublayer: square(30, 30, 1, 1, 1, 1)];
        [root addSublayer: square(30, 30, 0, 1, 0, 0)];

        CARenderer *renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj]
                                                          options: nil];
        renderer.bounds = CGRectMake(0, 0, 64, 64);
        renderer.layer = root;
        [renderer render];
        glFinish();

        unsigned char first[4], second[4], third[4], fourth[4];
        glReadPixels(10, 10, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, first);
        glReadPixels(40, 10, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, second);
        glReadPixels(10, 40, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, third);
        glReadPixels(40, 40, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, fourth);
        GLenum error = glGetError();
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];

        if (error != GL_NO_ERROR) {
            fprintf(stderr, "OpenGL error: %u\n", error);
            return 4;
        }
        if (is(first, 0, 1, 0) || is(third, 1, 0, 1)) {
            fprintf(stderr, "a lower zPosition was drawn over a higher one\n");
            return 5;
        }
        if (is(second, 0, 0, 1)) {
            fprintf(stderr, "equal zPosition was not drawn in array order\n");
            return 6;
        }
        if (is(fourth, 0, 0, 1) || is(fourth, 0, 1, 0)) {
            fprintf(stderr, "a NaN zPosition was not treated as 0\n");
            return 8;
        }
        if (!is(first, 1, 0, 0) || !is(second, 1, 1, 0) || !is(third, 0, 1, 1) ||
            !is(fourth, 1, 1, 1)) {
            fprintf(stderr, "first=(%u,%u,%u) second=(%u,%u,%u) third=(%u,%u,%u) fourth=(%u,%u,%u)\n",
                    first[0], first[1], first[2], second[0], second[1], second[2], third[0],
                    third[1], third[2], fourth[0], fourth[1], fourth[2]);
            return 7;
        }
        puts("PASS: CARenderer sibling zPosition order");
        return 0;
    }
}
