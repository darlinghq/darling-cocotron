// Copyright (C) 2026 Lubos Dolezel
//
// A layer tree drawn into a native child window cannot blend with the window under it, so CARenderer can be given a
// backdrop image (the parent window's pixels beneath the child window) that is drawn over the cleared frame before the
// layers. Without one the transparent parts of the tree stay the renderer's black. Checks: no backdrop leaves black;
// the backdrop fills the frame upright (top row at the top); layers are drawn over it and a half transparent layer
// blends with it. Needs a GL-capable backend (X11 on Xvfb). The backdrop hook is private
// (-[CARenderer _setBackdropImage:]).
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define W 40
#define H 40

@interface CARenderer (Backdrop)
- (void) _setBackdropImage: (CGImageRef) image;
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static unsigned char pixels[W * H * 4];

static void pixelAt(int x, int y, int *c) {
    for (int i = 0; i < 3; i++)
        c[i] = pixels[(y * W + x) * 4 + i];
}

static BOOL is(int x, int y, int r, int g, int b) {
    int c[3];
    pixelAt(x, y, c);
    return abs(c[0] - r) < 12 && abs(c[1] - g) < 12 && abs(c[2] - b) < 12;
}

static void render(CARenderer *renderer) {
    [renderer render];
    glFinish();
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

// Top half green, bottom half blue, opaque.
static CGImageRef makeBackdrop(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(ctx, 0, 1, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, H / 2, W, H / 2));
    CGContextSetRGBFillColor(ctx, 0, 0, 1, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, W, H / 2));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return image;
}

static CALayer *layer(CGRect frame, CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    CALayer *l = [CALayer layer];
    l.anchorPoint = CGPointZero;
    l.position = frame.origin;
    l.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    CGColorRef color = CGColorCreateGenericRGB(r, g, b, a);
    l.backgroundColor = color;
    CGColorRelease(color);
    return l;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, W, H);
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
        glViewport(0, 0, W, H);
        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        glOrtho(0, W, 0, H, -1, 1);
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glPixelStorei(GL_PACK_ALIGNMENT, 1);

        // A fully transparent root with a red layer at (4,4) and a half transparent gray one at (24,24).
        CALayer *root = layer(CGRectMake(0, 0, W, H), 0, 0, 0, 0);
        [root addSublayer: layer(CGRectMake(4, 4, 8, 8), 1, 0, 0, 1)];
        [root addSublayer: layer(CGRectMake(24, 24, 8, 8), 0.5, 0.5, 0.5, 0.5)];
        CARenderer *renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj] options: nil];
        renderer.bounds = CGRectMake(0, 0, W, H);
        renderer.layer = root;

        render(renderer);
        CHECK(is(20, 30, 0, 0, 0), "without a backdrop the transparent area is black");
        CHECK(is(8, 8, 255, 0, 0), "red layer");

        CGImageRef backdrop = makeBackdrop();
        [renderer _setBackdropImage: backdrop];
        render(renderer);
        CHECK(is(20, 36, 0, 255, 0), "backdrop top half is at the top (green)");
        CHECK(is(20, 4, 0, 0, 255), "backdrop bottom half is at the bottom (blue)");
        CHECK(is(8, 8, 255, 0, 0), "an opaque layer covers the backdrop");
        // gray 0.5 at alpha 0.5 over green: 0.5 * 0.5 + 0.5 * (0, 1, 0) = (64, 191, 64)
        CHECK(is(28, 28, 64, 191, 64), "a half transparent layer blends with the backdrop");

        // Taking the backdrop away restores the black.
        [renderer _setBackdropImage: NULL];
        render(renderer);
        CHECK(is(20, 36, 0, 0, 0), "backdrop removed");
        CGImageRelease(backdrop);

        CHECK(glGetError() == GL_NO_ERROR, "GL error");
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];
        if (failures == 0)
            puts("PASS: CARenderer backdrop");
        return failures != 0;
    }
}
