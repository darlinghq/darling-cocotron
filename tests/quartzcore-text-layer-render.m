// Copyright (C) 2026 Lubos Dolezel
//
// CATextLayer renders its string through CARenderer: documented defaults,
// drawing from the top of the bounds, alignment, wrapping, truncation, a CRLF counting as
// one line break, and a font given as a name, a CGFont or a CTFont.
// Needs a GL-capable backend (X11 on Xvfb).
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <string.h>

#define W 120
#define H 100

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static unsigned char pixels[W * H * 4];
static CARenderer *renderer;

// Draws the layer tree and reads the frame back (row 0 is the bottom).
static void render(void) {
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    [renderer render];
    glFinish();
    glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
}

// Extent of the pixels brighter than a threshold; returns the lit pixel count.
static int litExtent(int *minX, int *maxX, int *minY, int *maxY) {
    int count = 0;
    *minX = W; *maxX = -1; *minY = H; *maxY = -1;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++) {
            const unsigned char *p = pixels + (y * W + x) * 4;
            if (p[0] > 100 && p[1] > 100 && p[2] > 100) {
                count++;
                if (x < *minX) *minX = x;
                if (x > *maxX) *maxX = x;
                if (y < *minY) *minY = y;
                if (y > *maxY) *maxY = y;
            }
        }
    return count;
}


// Lit pixels in the columns x0..x1 of the upper part of the text line (where
// the stems of capital letters are and an ellipsis, which sits on the baseline, is not).
static int stemPixels(int x0, int x1) {
    int count = 0;
    for (int y = H - 12; y < H; y++)
        for (int x = x0; x <= x1; x++) {
            const unsigned char *p = pixels + (y * W + x) * 4;
            if (p[0] > 100 && p[1] > 100 && p[2] > 100)
                count++;
        }
    return count;
}

static CATextLayer *textLayer;

static void configure(id string) {
    textLayer.string = string;
    render();
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

        textLayer = [CATextLayer layer];
        textLayer.anchorPoint = CGPointZero;
        textLayer.position = CGPointZero;
        textLayer.bounds = CGRectMake(0, 0, W, H);
        CALayer *root = [CALayer layer];
        root.anchorPoint = CGPointZero;
        root.position = CGPointZero;
        root.bounds = CGRectMake(0, 0, W, H);
        [root addSublayer: textLayer];
        renderer = [CARenderer rendererWithCGLContext: [context CGLContextObj] options: nil];
        renderer.bounds = CGRectMake(0, 0, W, H);
        renderer.layer = root;

        // Documented defaults.
        CHECK(textLayer.fontSize == 36, "default fontSize %f", textLayer.fontSize);
        CHECK(!textLayer.wrapped, "default wrapped");
        CHECK([textLayer.alignmentMode isEqualToString: kCAAlignmentNatural], "default alignmentMode");
        CHECK([textLayer.truncationMode isEqualToString: kCATruncationNone], "default truncationMode");
        const CGFloat *fg = CGColorGetComponents(textLayer.foregroundColor);
        size_t fgCount = CGColorGetNumberOfComponents(textLayer.foregroundColor);
        CHECK(fgCount >= 2 && fg[0] == 1 && fg[fgCount - 1] == 1, "foregroundColor defaults to opaque white");

        int minX, maxX, minY, maxY, n;

        // Empty string draws nothing.
        configure(@"");
        CHECK(litExtent(&minX, &maxX, &minY, &maxY) == 0, "empty string draws nothing");

        // The first line is at the top of the bounds; nothing at the bottom.
        textLayer.fontSize = 20;
        textLayer.alignmentMode = kCAAlignmentLeft;
        configure(@"HH");
        n = litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(n > 20, "string drawn (%d lit pixels)", n);
        CHECK(minY > H / 2, "text starts at the top (lowest lit row %d)", minY);
        CHECK(minX < 10, "left aligned (leftmost lit column %d)", minX);
        CHECK(maxX < W / 2, "short text stays on the left (rightmost %d)", maxX);

        // Alignment.
        textLayer.alignmentMode = kCAAlignmentRight;
        render();
        n = litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(n > 20 && minX > W / 2 && maxX > W - 10, "right aligned (%d..%d)", minX, maxX);
        textLayer.alignmentMode = kCAAlignmentCenter;
        render();
        n = litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(n > 20 && minX > 20 && maxX < W - 20, "centred (%d..%d)", minX, maxX);

        // An attributed string is drawn as its text.
        textLayer.alignmentMode = kCAAlignmentLeft;
        configure([[[NSAttributedString alloc] initWithString: @"HH"] autorelease]);
        CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 20, "attributed string drawn");

        // A CRLF is one line break, as a bare LF is.
        configure(@"H\nH");
        int lfCount = litExtent(&minX, &maxX, &minY, &maxY);
        int lfLow = minY;
        unsigned char lfPixels[sizeof pixels];
        memcpy(lfPixels, pixels, sizeof pixels);
        configure(@"H\r\nH");
        int crlfCount = litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(lfCount == crlfCount && lfLow == minY && memcmp(lfPixels, pixels, sizeof pixels) == 0,
              "CRLF renders like LF (%d vs %d lit pixels)", lfCount, crlfCount);
        configure(@"H");
        litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(lfLow < minY, "second line is below the first");

        // Wrapping breaks at spaces to fit the width.
        textLayer.bounds = CGRectMake(0, 0, 40, H);
        textLayer.wrapped = NO;
        configure(@"HH HH HH HH HH");
        litExtent(&minX, &maxX, &minY, &maxY);
        int unwrappedLow = minY;
        textLayer.wrapped = YES;
        render();
        litExtent(&minX, &maxX, &minY, &maxY);
        CHECK(minY < unwrappedLow, "wrapped text uses more lines (%d vs %d)", minY, unwrappedLow);
        textLayer.bounds = CGRectMake(0, 0, W, H);
        textLayer.wrapped = NO;

        // Truncation: a line too wide for an unwrapped layer is cut where the
        // mode says and an ellipsis marks the cut, which sits on the baseline,
        // so the stems of the capitals end up on the side that is kept.
        textLayer.bounds = CGRectMake(0, 0, 60, H);
        textLayer.wrapped = NO;
        textLayer.alignmentMode = kCAAlignmentLeft;
        textLayer.truncationMode = kCATruncationNone;
        configure(@"HHHHHHHHHH");
        CHECK(stemPixels(0, 4) > 0 && stemPixels(52, 59) > 0, "no truncation: stems on both sides");
        textLayer.truncationMode = kCATruncationEnd;
        render();
        CHECK(stemPixels(0, 4) > 0, "end: the beginning is kept");
        CHECK(stemPixels(52, 59) == 0 && litExtent(&minX, &maxX, &minY, &maxY) > 0 && maxX > 40,
              "end: an ellipsis, no stem, at the right edge");
        textLayer.truncationMode = kCATruncationStart;
        render();
        CHECK(stemPixels(0, 6) == 0, "start: an ellipsis, no stem, at the left edge");
        // The truncated line is left aligned and narrower than the layer, so its
        // right edge is where the lit pixels end, not at the edge of the layer.
        CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 0 && maxX < 60 && stemPixels(maxX - 8, maxX) > 0,
              "start: the end is kept");
        textLayer.truncationMode = kCATruncationMiddle;
        render();
        CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 0 && maxX < 60 && stemPixels(0, 4) > 0 &&
              stemPixels(maxX - 8, maxX) > 0, "middle: both ends are kept");
        // The truncated line is aligned by alignmentMode like any other: it is
        // about 49 px wide here (two capitals and the ellipsis), so flush right
        // leaves the left edge bare and centred leaves a few pixels on each side.
        textLayer.truncationMode = kCATruncationEnd;
        textLayer.alignmentMode = kCAAlignmentRight;
        configure(@"HHHHHHHHHH");
        CHECK(stemPixels(0, 9) == 0 && stemPixels(10, 24) > 0, "end, right aligned: the truncated line is flush right");
        textLayer.alignmentMode = kCAAlignmentCenter;
        render();
        CHECK(stemPixels(0, 4) == 0 && stemPixels(5, 14) > 0, "end, centred: the truncated line is centred");
        textLayer.alignmentMode = kCAAlignmentLeft;
        // A wrapped layer is not truncated: a single word wider than it is drawn whole,
        // so its stems reach the right edge where truncation would leave an ellipsis.
        textLayer.wrapped = YES;
        configure(@"HHHHHHHHHH");
        CHECK(stemPixels(52, 59) > 0, "wrapped: a long word is not truncated");
        textLayer.wrapped = NO;
        configure(@"HHHHHHHHHH");
        CHECK(stemPixels(52, 59) == 0, "unwrapped again: truncated");
        // A line that fits is not changed by the mode.
        configure(@"H");
        unsigned char fitting[sizeof pixels];
        memcpy(fitting, pixels, sizeof pixels);
        textLayer.truncationMode = kCATruncationNone;
        render();
        CHECK(memcmp(fitting, pixels, sizeof pixels) == 0, "a line that fits is drawn as without truncation");
        textLayer.bounds = CGRectMake(0, 0, W, H);
        textLayer.alignmentMode = kCAAlignmentLeft;

        // Foreground color.
        CGColorRef green = CGColorCreateGenericRGB(0, 1, 0, 1);
        textLayer.foregroundColor = green;
        configure(@"HH");
        {
            int greenPixels = 0;
            for (int i = 0; i < W * H; i++) {
                const unsigned char *p = pixels + i * 4;
                if (p[1] > 150 && p[0] < 60 && p[2] < 60) greenPixels++;
            }
            CHECK(greenPixels > 20, "green text (%d pixels)", greenPixels);
        }
        CGColorRelease(green);
        textLayer.foregroundColor = CGColorCreateGenericRGB(1, 1, 1, 1);

        // The font as a name, a CGFont and a CTFont all draw text.
        textLayer.font = @"Helvetica";
        configure(@"HH");
        CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 20, "font given as a name");
        CGFontRef cgFont = CGFontCreateWithFontName(CFSTR("Helvetica"));
        if (cgFont != NULL) {
            textLayer.font = cgFont;
            configure(@"HH");
            CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 20, "font given as a CGFont");
            CTFontRef ctFont = CTFontCreateWithGraphicsFont(cgFont, 20, NULL, NULL);
            textLayer.font = ctFont;
            configure(@"HH");
            CHECK(litExtent(&minX, &maxX, &minY, &maxY) > 20, "font given as a CTFont");
            CFRelease(ctFont);
            CGFontRelease(cgFont);
        }

        CHECK(glGetError() == GL_NO_ERROR, "GL error");
        [view unlockFocus];
        [NSOpenGLContext clearCurrentContext];
        [window release];
        if (failures == 0) puts("PASS: CATextLayer drawing");
        return failures != 0;
    }
}
