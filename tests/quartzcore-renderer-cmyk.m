// Copyright (C) 2026 Lubos Dolezel
//
// CMYK layer colors: CARenderer converts a layer's background color from the
// device CMYK color space to RGB. Without the conversion the background of a
// CMYK-colored layer is left undrawn. Thresholds are loose so that any
// sensible CMYK to RGB conversion passes: no ink is near white, full cyan has
// little red, full black is dark.
// Needs a GL-capable backend (X11 on Xvfb).
// Exit 2/3: no GL context; 4: GL error; 5: nothing drawn for a CMYK color;
// 6: wrong color; 0: correct.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

static BOOL isBlackish(const unsigned char *p) { return p[0] < 70 && p[1] < 70 && p[2] < 70; }

static void paint(CALayer *root, CGColorSpaceRef cmyk, CGFloat x, const CGFloat *components) {
    CGColorRef color = CGColorCreate(cmyk, components);
    CALayer *swatch = [CALayer layer];
    swatch.anchorPoint = CGPointZero;
    swatch.position = CGPointMake(x, 0);
    swatch.bounds = CGRectMake(0, 0, 16, 16);
    swatch.backgroundColor = color;
    CGColorRelease(color);
    [root addSublayer: swatch];
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

        CGColorSpaceRef cmyk = CGColorSpaceCreateDeviceCMYK();
        CALayer *root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, 64, 64);
        const CGFloat white[5] = {0, 0, 0, 0, 1};
        const CGFloat cyan[5] = {1, 0, 0, 0, 1};
        const CGFloat black[5] = {0, 0, 0, 1, 1};
        paint(root, cmyk, 0, white);
        paint(root, cmyk, 16, cyan);
        paint(root, cmyk, 32, black);
        CGColorSpaceRelease(cmyk);

        CARenderer *renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj]
                                                          options: nil];
        renderer.bounds = CGRectMake(0, 0, 64, 64);
        renderer.layer = root;
        [renderer render];
        glFinish();

        unsigned char w[4], c[4], k[4];
        glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, w);
        glReadPixels(24, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, c);
        glReadPixels(40, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, k);
        GLenum error = glGetError();
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];

        if (error != GL_NO_ERROR) {
            fprintf(stderr, "OpenGL error: %u\n", error);
            return 4;
        }
        if (isBlackish(w) && isBlackish(c)) {
            fprintf(stderr, "CMYK background not drawn\n");
            return 5;
        }
        if (!(w[0] > 230 && w[1] > 230 && w[2] > 230) ||
            !(c[0] < 60 && c[1] > 150 && c[2] > 150) || !isBlackish(k)) {
            fprintf(stderr, "white=(%u,%u,%u) cyan=(%u,%u,%u) black=(%u,%u,%u)\n", w[0], w[1],
                    w[2], c[0], c[1], c[2], k[0], k[1], k[2]);
            return 6;
        }
        puts("PASS: CARenderer CMYK colors");
        return 0;
    }
}
