// Copyright (C) 2026 Lubos Dolezel
//
// A sublayer's position is in its parent's coordinate system, whose origin is
// the parent's bounds.origin. CARenderer must place the child by position
// minus that origin. The parent has bounds (20,30,20,20), the red 4x4 child
// sits at (30,40) in the parent's coordinates, so it belongs at frame (10,10).
// Needs a GL-capable backend (X11 on Xvfb).
// Exit 2/3: no GL context; 4: GL error; 5: child at the offset position
// (origin ignored); 6: child missing; 0: correct.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static BOOL isRed(const unsigned char *p) { return p[0] > 200 && p[1] < 20 && p[2] < 20; }
static BOOL isBlack(const unsigned char *p) { return p[0] < 20 && p[1] < 20 && p[2] < 20; }

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

        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        CALayer *root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, 64, 64);

        CALayer *parent = [CALayer layer];
        parent.anchorPoint = CGPointZero;
        parent.position = CGPointMake(0, 0);
        parent.bounds = CGRectMake(20, 30, 20, 20);

        CALayer *child = [CALayer layer];
        child.anchorPoint = CGPointZero;
        child.position = CGPointMake(30, 40);
        child.bounds = CGRectMake(0, 0, 4, 4);
        child.backgroundColor = red;
        CGColorRelease(red);

        [parent addSublayer: child];
        [root addSublayer: parent];

        CARenderer *renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj]
                                                          options: nil];
        renderer.bounds = CGRectMake(0, 0, 64, 64);
        renderer.layer = root;
        [renderer render];
        glFinish();

        unsigned char inside[4], offset[4];
        glReadPixels(12, 12, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, inside);
        glReadPixels(32, 42, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, offset);
        GLenum error = glGetError();
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];

        if (error != GL_NO_ERROR) {
            fprintf(stderr, "OpenGL error: %u\n", error);
            return 4;
        }
        if (isRed(offset)) {
            fprintf(stderr, "child placed without the parent's bounds origin\n");
            return 5;
        }
        if (!isRed(inside) || !isBlack(offset)) {
            fprintf(stderr, "inside=(%u,%u,%u) offset=(%u,%u,%u)\n", inside[0], inside[1],
                    inside[2], offset[0], offset[1], offset[2]);
            return 6;
        }
        puts("PASS: CARenderer sublayer bounds origin");
        return 0;
    }
}
