// Copyright (C) 2026 Lubos Dolezel
//
// CAShapeLayer renders its path through CARenderer: documented defaults, fill
// (non-zero and even-odd), stroke over fill, dashes, and an empty
// strokeStart/strokeEnd range that strokes nothing. The frame is cleared to
// mid grey so that "nothing drawn" differs from the default black fill.
// Needs a GL-capable backend (X11 on Xvfb).
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>

#define W 40
#define H 40

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static unsigned char pixels[W * H * 4];
static CARenderer *renderer;
static CALayer *root;

// Pixel in layer coordinates (y up), as r, g, b, a.
static void pixelAt(int x, int y, unsigned char *out) {
    memcpy(out, pixels + (y * W + x) * 4, 4);
}

static void render(void) {
    glClearColor(0.5, 0.5, 0.5, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    [renderer render];
    glFinish();
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

static BOOL near(unsigned char v, int want) { return abs((int) v - want) < 30; }
static BOOL isRed(int x, int y) { unsigned char p[4]; pixelAt(x, y, p); return near(p[0], 255) && near(p[1], 0) && near(p[2], 0); }
static BOOL isBlue(int x, int y) { unsigned char p[4]; pixelAt(x, y, p); return near(p[0], 0) && near(p[1], 0) && near(p[2], 255); }
static BOOL isBlack(int x, int y) { unsigned char p[4]; pixelAt(x, y, p); return near(p[0], 0) && near(p[1], 0) && near(p[2], 0); }
static BOOL isClear(int x, int y) { unsigned char p[4]; pixelAt(x, y, p); return near(p[0], 128) && near(p[1], 128) && near(p[2], 128); }

static CGPathRef rectPath(CGRect r) {
    CGMutablePathRef p = CGPathCreateMutable();
    CGPathAddRect(p, NULL, r);
    return p;
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

        CAShapeLayer *layer = [CAShapeLayer layer];
        layer.anchorPoint = CGPointZero;
        layer.position = CGPointZero;
        layer.bounds = CGRectMake(0, 0, W, H);
        root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, W, H);
        // CARenderer clears the frame to black itself; a gray root background gives "untouched" pixels a distinct value.
        CGColorRef gray = CGColorCreateGenericRGB(0.5, 0.5, 0.5, 1);
        root.backgroundColor = gray;
        CGColorRelease(gray);
        [root addSublayer: layer];
        renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj] options: nil];
        renderer.bounds = CGRectMake(0, 0, W, H);
        renderer.layer = root;

        // Documented defaults.
        CHECK(layer.path == NULL, "default path");
        CHECK(layer.fillColor != NULL, "fillColor defaults to opaque black");
        if (layer.fillColor) {
            const CGFloat *c = CGColorGetComponents(layer.fillColor);
            size_t n = CGColorGetNumberOfComponents(layer.fillColor);
            CHECK(n >= 2 && c[n - 1] == 1, "default fill alpha");
            for (size_t i = 0; i + 1 < n; i++)
                CHECK(c[i] == 0, "default fill component %zu", i);
        }
        CHECK(layer.strokeColor == NULL, "strokeColor defaults to none");
        CHECK(layer.lineWidth == 1, "lineWidth default %f", layer.lineWidth);
        CHECK(layer.miterLimit == 10, "miterLimit default %f", layer.miterLimit);
        CHECK(layer.strokeStart == 0 && layer.strokeEnd == 1, "stroke range default");
        CHECK([layer.fillRule isEqualToString: kCAFillRuleNonZero], "fillRule default");
        CHECK([layer.lineCap isEqualToString: kCALineCapButt], "lineCap default");
        CHECK([layer.lineJoin isEqualToString: kCALineJoinMiter], "lineJoin default");
        CHECK(layer.lineDashPhase == 0 && layer.lineDashPattern == nil, "dash defaults");

        // Fill with the default black, nothing outside the path.
        CGPathRef square = rectPath(CGRectMake(10, 10, 20, 20));
        layer.path = square;
        render();
        CHECK(isBlack(20, 20), "default fill is opaque black");
        CHECK(isClear(5, 5), "outside the path is untouched");

        // Red fill, no stroke.
        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        CGColorRef blue = CGColorCreateGenericRGB(0, 0, 1, 1);
        layer.fillColor = red;
        render();
        CHECK(isRed(20, 20) && isClear(5, 5), "red fill");

        // The path is copied: mutating the original afterwards changes nothing.
        CGMutablePathRef mutablePath = CGPathCreateMutable();
        CGPathAddRect(mutablePath, NULL, CGRectMake(10, 10, 20, 20));
        layer.path = mutablePath;
        CGPathAddRect(mutablePath, NULL, CGRectMake(0, 0, 5, 5));
        render();
        CHECK(isClear(2, 2), "path set is a copy");
        CGPathRelease(mutablePath);

        // Stroke on top of the fill, centred on the outline.
        layer.strokeColor = blue;
        layer.lineWidth = 4;
        render();
        CHECK(isBlue(10, 20), "stroke centred on the left edge");
        CHECK(isBlue(11, 20), "stroke covers the fill at the edge (stroke after fill)");
        CHECK(isRed(20, 20), "interior stays filled");
        CHECK(isClear(5, 20), "outside the stroke untouched");

        // No fill.
        layer.fillColor = NULL;
        render();
        CHECK(isClear(20, 20) && isBlue(10, 20), "stroke only");

        // An empty stroke range strokes nothing; a non-empty one strokes.
        layer.strokeStart = 0;
        layer.strokeEnd = 0;
        render();
        CHECK(isClear(10, 20), "strokeEnd 0 strokes nothing");
        layer.strokeStart = 0.5;
        layer.strokeEnd = 0.5;
        render();
        CHECK(isClear(10, 20), "strokeStart == strokeEnd strokes nothing");
        layer.strokeStart = 0;
        layer.strokeEnd = 1;
        render();
        CHECK(isBlue(10, 20), "full range strokes");

        // Even-odd fill leaves a hole where two subpaths overlap.
        CGMutablePathRef nested = CGPathCreateMutable();
        CGPathAddRect(nested, NULL, CGRectMake(5, 5, 30, 30));
        CGPathAddRect(nested, NULL, CGRectMake(15, 15, 10, 10));
        layer.path = nested;
        CGPathRelease(nested);
        layer.strokeColor = NULL;
        layer.fillColor = red;
        render();
        CHECK(isRed(20, 20), "non-zero fill covers the overlap");
        layer.fillRule = kCAFillRuleEvenOdd;
        render();
        CHECK(isClear(20, 20) && isRed(10, 10), "even-odd fill leaves a hole");

        // Dashes: a 4 on / 4 off pattern leaves gaps along a horizontal stroke.
        CGMutablePathRef line = CGPathCreateMutable();
        CGPathMoveToPoint(line, NULL, 0, 20);
        CGPathAddLineToPoint(line, NULL, 40, 20);
        layer.path = line;
        CGPathRelease(line);
        layer.fillColor = NULL;
        layer.strokeColor = blue;
        layer.lineWidth = 2;
        layer.lineDashPattern = @[ @4, @4 ];
        render();
        CHECK(isBlue(2, 20) && isClear(6, 20) && isBlue(10, 20), "dash pattern");

        CHECK(glGetError() == GL_NO_ERROR, "GL error");
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];
        CGColorRelease(red);
        CGColorRelease(blue);
        CGPathRelease(square);
        if (failures == 0) puts("PASS: CAShapeLayer drawing");
        return failures != 0;
    }
}
