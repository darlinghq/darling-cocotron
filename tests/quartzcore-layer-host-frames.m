// Copyright (C) 2026 Lubos Dolezel
//
// Showing a remote CAContext with a CALayerHost:
//  - the hosted frame looks as the tree looks when it is drawn directly, also
//    after many frames (the frames alternate between two surfaces, each bound
//    to a texture of its own);
//  - nothing is drawn for a hidden host layer or a hidden context: frames that
//    arrive meanwhile start no composite, and showing it again draws the latest
//    frame.
//
// The remote context renders into a texture that is bound to its IOSurface, so
// no pixels are read back and copied; the frames are checked through the pixels
// a host draws.
//
// Needs a GL-capable backend (Xvfb for X11, a compositor for Wayland).
// Exit 2/3: no GL context; otherwise the number of failures.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <QuartzCore/CALayerContext.h>
#include <stdio.h>
#include <stdlib.h>

typedef uint32_t CAContextID;

@interface CAContext : NSObject
+ (instancetype) remoteContext;
@property(readonly) CAContextID contextId;
@property(retain) CALayer *layer;
@end

@interface CALayerHost : CALayer
@property CAContextID contextId;
@end

static int failures;

#define CHECK(cond, ...) do { if (!(cond)) { fprintf(stderr, "FAIL %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); failures++; } } while (0)

enum { kSize = 64 };

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static CALayer *makeTree(CGFloat red, CGFloat green) {
    CALayer *root = [CALayer layer];
    root.anchorPoint = CGPointZero;
    root.position = CGPointZero;
    root.bounds = CGRectMake(0, 0, kSize, kSize);
    CGColorRef background = CGColorCreateGenericRGB(0, 0, 1, 1);
    root.backgroundColor = background;
    CGColorRelease(background);

    CALayer *child = [CALayer layer];
    child.name = @"child";
    child.anchorPoint = CGPointZero;
    child.position = CGPointMake(4, 8);
    child.bounds = CGRectMake(0, 0, 24, 16);
    CGColorRef color = CGColorCreateGenericRGB(red, green, 0, 1);
    child.backgroundColor = color;
    CGColorRelease(color);
    [root addSublayer: child];
    return root;
}

static void setChildColor(CALayer *root, CGFloat red, CGFloat green) {
    CGColorRef color = CGColorCreateGenericRGB(red, green, 0, 1);
    [[root sublayers] firstObject].backgroundColor = color;
    CGColorRelease(color);
}

// Draws layer with a renderer into the current context's drawable and reads
// the sample points back (RGBA each).
static void drawAndRead(CGLContextObj gl, CALayer *layer, unsigned char samples[][4], const int points[][2],
                        int count) {
    glViewport(0, 0, kSize, kSize);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0, kSize, 0, kSize, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    CARenderer *renderer = [CARenderer rendererWithCGLContext: gl options: nil];
    renderer.bounds = CGRectMake(0, 0, kSize, kSize);
    renderer.layer = layer;
    [renderer beginFrameAtTime: CACurrentMediaTime() timeStamp: NULL];
    [renderer render];
    [renderer endFrame];
    glFinish();
    for (int i = 0; i < count; i++)
        glReadPixels(points[i][0], points[i][1], 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, samples[i]);
    renderer.layer = nil;
}

static const int kPoints[][2] = {{2, 2}, {10, 12}, {20, 20}, {40, 10}, {50, 50}, {61, 61}, {5, 30}, {30, 60}};
enum { kPointCount = sizeof(kPoints) / sizeof(kPoints[0]) };

static BOOL near(const unsigned char *a, const unsigned char *b) {
    for (int i = 0; i < 4; i++)
        if (abs((int) a[i] - (int) b[i]) > 3)
            return NO;
    return YES;
}

// What a layer tree draws directly and what a host of the same tree in a
// remote context draws agree at every sample point.
static void expectSameImage(CGLContextObj gl, CALayer *tree, CALayerHost *host, const char *what) {
    unsigned char direct[kPointCount][4], hosted[kPointCount][4];
    drawAndRead(gl, tree, direct, kPoints, kPointCount);
    drawAndRead(gl, host, hosted, kPoints, kPointCount);
    for (int i = 0; i < kPointCount; i++)
        CHECK(near(direct[i], hosted[i]), "%s: (%d,%d) direct (%u,%u,%u,%u) hosted (%u,%u,%u,%u)", what,
              kPoints[i][0], kPoints[i][1], direct[i][0], direct[i][1], direct[i][2], direct[i][3], hosted[i][0],
              hosted[i][1], hosted[i][2], hosted[i][3]);
}

static unsigned renders;

@interface CountingContext : CALayerContext
@end

@implementation CountingContext
- (void) render {
    renders++;
}
- (void) flush {
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect frame = NSMakeRect(0, 0, kSize, kSize);
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
        CGLContextObj gl = [context CGLContextObj];
        if (CGLGetCurrentContext() != gl)
            return 3;

        // The same tree: drawn directly, and as the tree of a remote context.
        CALayer *direct = makeTree(1, 0);
        CALayer *remoteRoot = makeTree(1, 0);
        CAContext *remote = [CAContext remoteContext];
        remote.layer = remoteRoot;
        CALayerHost *host = [CALayerHost layer];
        host.anchorPoint = CGPointZero;
        host.position = CGPointZero;
        host.bounds = CGRectMake(0, 0, kSize, kSize);
        host.contextId = remote.contextId;
        spin(0.6);

        expectSameImage(gl, direct, host, "first frame");

        // Many frames: each surface is shown, in turn, many times.
        for (int i = 0; i < 9; i++) {
            CGFloat green = (i % 3) * 0.5, red = 1 - green;
            setChildColor(direct, red, green);
            setChildColor(remoteRoot, red, green);
            spin(0.25);
            char what[32];
            snprintf(what, sizeof(what), "frame %d", i + 2);
            expectSameImage(gl, direct, host, what);
        }

        // A hidden host layer: frames that arrive change nothing that is
        // drawn, so they draw nothing; showing the layer draws the latest.
        {
            CountingContext *counting = [[CountingContext alloc] initWithFrame: CGRectMake(0, 0, kSize, kSize)];
            if (counting == nil)
                return 3;
            CALayer *hostRoot = [CALayer layer];
            CALayerHost *hidden = [CALayerHost layer];
            hidden.bounds = CGRectMake(0, 0, kSize, kSize);
            hidden.contextId = remote.contextId;
            [hostRoot addSublayer: hidden];
            counting.layer = hostRoot;
            spin(0.4);

            hidden.hidden = YES;
            spin(0.2);
            renders = 0;
            for (int i = 0; i < 6; i++) {
                setChildColor(remoteRoot, 0, (i % 2) ? 1 : 0.5);
                spin(0.15);
            }
            CHECK(renders == 0, "hidden host layer: %u composites for 6 frames", renders);

            // Hiding a superlayer hides the host layer too.
            hidden.hidden = NO;
            spin(0.2);
            hostRoot.hidden = YES;
            spin(0.2);
            renders = 0;
            for (int i = 0; i < 6; i++) {
                setChildColor(remoteRoot, (i % 2) ? 1 : 0.5, 0);
                spin(0.15);
            }
            CHECK(renders == 0, "hidden superlayer: %u composites for 6 frames", renders);

            hostRoot.hidden = NO;
            spin(0.2);
            CHECK(renders >= 1, "showing the layer again drew nothing");

            // Visible again, frames composite again.
            renders = 0;
            for (int i = 0; i < 4; i++) {
                setChildColor(remoteRoot, 0, (i % 2) ? 1 : 0.5);
                spin(0.15);
            }
            CHECK(renders >= 1, "visible host layer: no composites for 4 frames");

            // A hidden context draws nothing either, and draws again when shown.
            [counting setHidden: YES];
            spin(0.2);
            renders = 0;
            for (int i = 0; i < 4; i++) {
                setChildColor(remoteRoot, 1, (i % 2) ? 1 : 0.5);
                spin(0.15);
            }
            CHECK(renders == 0, "hidden context: %u composites for 4 frames", renders);
            [counting setHidden: NO];
            spin(0.2);
            CHECK(renders >= 1, "showing the context again drew nothing");
            [counting invalidate];
            [counting release];
        }

        // After being hidden, the host shows the latest frame.
        setChildColor(direct, 0.5, 1);
        setChildColor(remoteRoot, 0.5, 1);
        spin(0.3);
        expectSameImage(gl, direct, host, "after the hidden phases");

        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];

        if (failures == 0)
            puts("PASS: CALayerHost frames");
        return failures;
    }
}
