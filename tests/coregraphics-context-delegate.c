// Copyright (C) 2026 Lubos Dolezel
//
// Context delegates (CGContextDelegatePrivate.h): a context created with
// CGContextCreateWithDelegate hands its drawing to the delegate's callbacks,
// each given the delegate and the graphics state, and draws nothing itself.
// The callback kinds and what they are given follow the declarations WebKit
// (BSD licensed) makes for this private interface; the expected values are
// those of Darling's implementation, not observations of macOS.
#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CoreGraphicsPrivate.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, msg) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: %s\n", __LINE__, msg); \
            failures++; \
        } \
    } while (0)

static int near(CGFloat a, CGFloat b) {
    return fabs((double) a - (double) b) < 1e-4;
}

typedef struct {
    int paths, images, glyphRuns, layersBegun, layersEnded;
    CGPathDrawingMode lastMode;
    CGRect lastPathBounds;
    CGAffineTransform lastCTM;
    CGFloat lastAlpha;
    CGFloat lastFill[4];
    CGFloat lastStroke[4];
    CGRect lastImageRect;
    size_t lastImageWidth;
    size_t glyphCount;
    CGGlyph glyphs[8];
    CGPoint positions[8];
    CGAffineTransform textMatrix;
    CGRect lastLayerRect;
    CGFloat layerAlpha;
    CGFontRef lastFont;
    CGFloat lastFontSize;
} Recorder;

static void copyColor(CGColorRef color, CGFloat *out) {
    memset(out, 0, 4 * sizeof(CGFloat));
    if (color == NULL)
        return;
    size_t n = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    for (size_t i = 0; i < n && i < 4; i++)
        out[i] = c[i];
}

static Recorder *recorderOf(CGContextDelegateRef delegate) {
    return (Recorder *) CGContextDelegateGetInfo(delegate);
}

static CGError drawPath(CGContextDelegateRef delegate, CGRenderingStateRef rstate, CGGStateRef gstate,
                        CGPathDrawingMode mode, CGPathRef path) {
    Recorder *r = recorderOf(delegate);
    r->paths++;
    r->lastMode = mode;
    r->lastPathBounds = CGPathGetBoundingBox(path);
    r->lastCTM = *CGGStateGetCTM(gstate);
    r->lastAlpha = CGGStateGetAlpha(gstate);
    copyColor(CGGStateGetFillColor(gstate), r->lastFill);
    copyColor(CGGStateGetStrokeColor(gstate), r->lastStroke);
    return kCGErrorSuccess;
}

static CGError drawImage(CGContextDelegateRef delegate, CGRenderingStateRef rstate, CGGStateRef gstate,
                         CGRect rect, CGImageRef image) {
    Recorder *r = recorderOf(delegate);
    r->images++;
    r->lastImageRect = rect;
    r->lastImageWidth = CGImageGetWidth(image);
    return kCGErrorSuccess;
}

static CGError drawGlyphs(CGContextDelegateRef delegate, CGRenderingStateRef rstate, CGGStateRef gstate,
                          const CGAffineTransform *tm, const CGGlyph glyphs[], const CGPoint positions[],
                          size_t count) {
    Recorder *r = recorderOf(delegate);
    r->glyphRuns++;
    r->glyphCount = count;
    for (size_t i = 0; i < count && i < 8; i++) {
        r->glyphs[i] = glyphs[i];
        r->positions[i] = positions[i];
    }
    r->textMatrix = *tm;
    r->lastFont = CGGStateGetFont(gstate);
    r->lastFontSize = CGGStateGetFontSize(gstate);
    return kCGErrorSuccess;
}

static CGContextDelegateRef beginLayer(CGContextDelegateRef delegate, CGRenderingStateRef rstate,
                                       CGGStateRef gstate, CGRect rect, CFDictionaryRef info,
                                       CGContextDelegateRef layerDelegate) {
    Recorder *r = recorderOf(delegate);
    r->layersBegun++;
    r->lastLayerRect = rect;
    r->layerAlpha = CGGStateGetAlpha(gstate);
    return delegate;
}

static CGContextDelegateRef endLayer(CGContextDelegateRef delegate, CGRenderingStateRef rstate,
                                     CGGStateRef gstate) {
    Recorder *r = recorderOf(delegate);
    r->layersEnded++;
    r->layerAlpha = CGGStateGetAlpha(gstate);
    return delegate;
}

static CGContextRef makeContext(Recorder *recorder, CGContextDelegateRef *outDelegate) {
    CGContextDelegateRef delegate = CGContextDelegateCreate(recorder);
    CGContextDelegateSetCallback(delegate, deDrawPath, (CGContextDelegateCallback) drawPath);
    CGContextDelegateSetCallback(delegate, deDrawImage, (CGContextDelegateCallback) drawImage);
    CGContextDelegateSetCallback(delegate, deDrawGlyphs, (CGContextDelegateCallback) drawGlyphs);
    CGContextDelegateSetCallback(delegate, deBeginLayer, (CGContextDelegateCallback) beginLayer);
    CGContextDelegateSetCallback(delegate, deEndLayer, (CGContextDelegateCallback) endLayer);
    CGContextRef context = CGContextCreateWithDelegate(delegate, kCGContextTypeUnknown, NULL, NULL);
    if (outDelegate != NULL)
        *outDelegate = delegate;
    else
        CGContextDelegateRelease(delegate);
    return context;
}

static void testDelegateObject(void) {
    int info;
    CGContextDelegateRef delegate = CGContextDelegateCreate(&info);
    CHECK(delegate != NULL, "a delegate is created");
    CHECK(CFGetTypeID(delegate) == CGContextDelegateGetTypeID(), "the delegate is a CF object of its type");
    CHECK(CGContextDelegateGetInfo(delegate) == &info, "the info is kept");
    CHECK(CGContextDelegateGetInfo(NULL) == NULL, "NULL delegate has no info");
    // out of range kinds and NULL delegates are ignored
    CGContextDelegateSetCallback(delegate, (CGContextDelegateCallbackName) -1, (CGContextDelegateCallback) drawPath);
    CGContextDelegateSetCallback(delegate, (CGContextDelegateCallbackName) 100000, (CGContextDelegateCallback) drawPath);
    CGContextDelegateSetCallback(NULL, deDrawPath, (CGContextDelegateCallback) drawPath);
    CHECK(CGContextDelegateRetain(delegate) == delegate, "retain returns the delegate");
    CGContextDelegateRelease(delegate);
    CGContextDelegateRelease(delegate);
    CGContextDelegateRelease(NULL);
    CHECK(CGContextDelegateRetain(NULL) == NULL, "retaining NULL gives NULL");

    CHECK(CGContextCreateWithDelegate(NULL, kCGContextTypeUnknown, NULL, NULL) == NULL,
          "no context without a delegate");
}

static void testContextType(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextDelegateRef delegate = CGContextDelegateCreate(&r);
    CGContextRef c = CGContextCreateWithDelegate(delegate, kCGContextTypeDisplayList, NULL, NULL);
    CHECK(CGContextGetType(c) == kCGContextTypeDisplayList, "the type given at creation is reported");
    CGContextRelease(c);
    c = CGContextCreateWithDelegate(delegate, (CGContextType) 1000, NULL, NULL);
    CHECK(CGContextGetType(c) == kCGContextTypeUnknown, "an unknown type is reported as unknown");
    CGContextRelease(c);
    CGContextDelegateRelease(delegate);

    CHECK(CGContextGetType(NULL) == kCGContextTypeUnknown, "NULL context is unknown");
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, 2, 2, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CHECK(CGContextGetType(bitmap) == kCGContextTypeBitmap, "a bitmap context is a bitmap context");
    CGContextRelease(bitmap);
    CGColorSpaceRelease(space);

    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    CGDataConsumerRef consumer = CGDataConsumerCreateWithCFData(data);
    CGRect box = CGRectMake(0, 0, 100, 100);
    CGContextRef pdf = CGPDFContextCreate(consumer, &box, NULL);
    CHECK(CGContextGetType(pdf) == kCGContextTypePDF, "a PDF context is a PDF context");
    CGContextRelease(pdf);
    CGDataConsumerRelease(consumer);
    CFRelease(data);
}

static void testPaths(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextRef c = makeContext(&r, NULL);
    CHECK(c != NULL, "a delegate context is created");
    CHECK(!CGContextIsBitmapContext(c), "a delegate context is not a bitmap context");

    CGContextTranslateCTM(c, 10, 20);
    CGContextScaleCTM(c, 2, 2);
    CGContextSetRGBFillColor(c, 1, 0.5, 0.25, 1);
    CGContextSetRGBStrokeColor(c, 0, 1, 0, 1);
    CGContextSetAlpha(c, 0.5);
    CGContextFillRect(c, CGRectMake(1, 1, 3, 3));
    CHECK(r.paths == 1, "a fill is one path");
    CHECK(r.lastMode == kCGPathFill, "a fill is delivered as kCGPathFill");
    CHECK(near(r.lastPathBounds.origin.x, 12) && near(r.lastPathBounds.origin.y, 22) &&
          near(r.lastPathBounds.size.width, 6) && near(r.lastPathBounds.size.height, 6),
          "the path has the CTM applied");
    CHECK(near(r.lastCTM.a, 2) && near(r.lastCTM.d, 2) && near(r.lastCTM.tx, 10) && near(r.lastCTM.ty, 20),
          "the state's CTM is the context's");
    CHECK(near(r.lastAlpha, 0.5), "the state's alpha is the context's");
    CHECK(near(r.lastFill[0], 1) && near(r.lastFill[1], 0.5) && near(r.lastFill[2], 0.25),
          "the state's fill colour is the context's");
    CHECK(near(r.lastStroke[1], 1) && near(r.lastStroke[0], 0), "the state's stroke colour is the context's");

    CGContextBeginPath(c);
    CGContextMoveToPoint(c, 0, 0);
    CGContextAddLineToPoint(c, 1, 0);
    CGContextAddLineToPoint(c, 1, 1);
    CGContextDrawPath(c, kCGPathEOFillStroke);
    CHECK(r.paths == 2 && r.lastMode == kCGPathEOFillStroke, "the drawing mode is passed on");
    CHECK(CGContextIsPathEmpty(c), "drawing consumes the current path");

    // an empty path is not delivered
    CGContextBeginPath(c);
    CGContextFillPath(c);
    CHECK(r.paths == 2, "an empty path is not delivered");

    // nothing is drawn for shadings, and nothing crashes
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat components[8] = {1, 0, 0, 1, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, NULL, 2);
    CGContextDrawLinearGradient(c, gradient, CGPointZero, CGPointMake(10, 0), 0);
    CHECK(r.paths == 2 && r.images == 0, "a gradient is not delivered");
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    CGContextRelease(c);
}

static void testImages(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextRef c = makeContext(&r, NULL);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, 3, 2, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGImageRef image = CGBitmapContextCreateImage(bitmap);
    CGContextDrawImage(c, CGRectMake(5, 6, 7, 8), image);
    CHECK(r.images == 1, "an image is delivered");
    CHECK(CGRectEqualToRect(r.lastImageRect, CGRectMake(5, 6, 7, 8)), "the rectangle is in user space");
    CHECK(r.lastImageWidth == 3, "the image is the one drawn");
    CGContextDrawImage(c, CGRectMake(0, 0, 1, 1), NULL);
    CHECK(r.images == 1, "a NULL image is not delivered");

    // a layer made for the context is delivered as an image of the layer
    CGLayerRef layer = CGLayerCreateWithContext(c, CGSizeMake(4, 5), NULL);
    CHECK(layer != NULL, "a layer can be made for a delegate context");
    if (layer != NULL) {
        CGContextDrawLayerInRect(c, CGRectMake(1, 2, 4, 5), layer);
        CHECK(r.images == 2 && CGRectEqualToRect(r.lastImageRect, CGRectMake(1, 2, 4, 5)),
              "a layer is delivered as an image");
        CGLayerRelease(layer);
    }
    CGImageRelease(image);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(space);
    CGContextRelease(c);
}

static void testGlyphs(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextRef c = makeContext(&r, NULL);
    CGGlyph glyphs[3] = {4, 5, 6};
    CGPoint positions[3] = {{0, 0}, {7, 0}, {15, 1}};
    CGContextSetTextMatrix(c, CGAffineTransformMakeTranslation(3, 4));
    CGContextShowGlyphsAtPositions(c, glyphs, positions, 3);
    CHECK(r.glyphRuns == 1 && r.glyphCount == 3, "a glyph run is delivered at once");
    CHECK(r.glyphs[2] == 6 && near(r.positions[1].x, 7) && near(r.positions[2].y, 1),
          "glyphs and positions are passed as given");
    CHECK(near(r.textMatrix.tx, 3) && near(r.textMatrix.ty, 4), "the text matrix is passed");
    CGAffineTransform after = CGContextGetTextMatrix(c);
    CHECK(near(after.tx, 3) && near(after.ty, 4), "the text matrix is left as it was");

    CGSize advances[2] = {{10, 0}, {12, 0}};
    CGContextSetTextMatrix(c, CGAffineTransformIdentity);
    CGContextSetTextPosition(c, 20, 30);
    CGContextShowGlyphsWithAdvances(c, glyphs, advances, 2);
    CHECK(r.glyphRuns == 2 && r.glyphCount == 2, "glyphs with advances are delivered");
    CHECK(near(r.positions[0].x, 0) && near(r.positions[1].x, 10), "positions follow the advances");
    CHECK(near(r.textMatrix.tx, 20) && near(r.textMatrix.ty, 30), "the text position is in the text matrix");
    CGPoint position = CGContextGetTextPosition(c);
    CHECK(near(position.x, 42), "the text position moves past the glyphs");

    CGContextShowGlyphsAtPositions(c, glyphs, positions, 0);
    CHECK(r.glyphRuns == 2, "an empty run is not delivered");

    CGFontRef font = CGFontCreateWithFontName(CFSTR("Helvetica"));
    if (font != NULL) {
        CGContextSetFont(c, font);
        CGContextSetFontSize(c, 17);
        CGContextShowGlyphsAtPositions(c, glyphs, positions, 1);
        CHECK(r.lastFont == font, "the state's font is the context's");
        CHECK(near(r.lastFontSize, 17), "the state's font size is the context's");
        CGFontRelease(font);
    }
    CGContextRelease(c);
}

static void testLayers(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextRef c = makeContext(&r, NULL);
    CGContextSetAlpha(c, 0.25);
    CGContextBeginTransparencyLayerWithRect(c, CGRectMake(1, 2, 3, 4), NULL);
    CHECK(r.layersBegun == 1, "beginning a layer is delivered");
    CHECK(CGRectEqualToRect(r.lastLayerRect, CGRectMake(1, 2, 3, 4)), "the layer's rectangle is passed");
    CHECK(near(r.layerAlpha, 0.25), "the layer is begun with the outer alpha");
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(near(r.lastAlpha, 1), "inside a layer the alpha starts at 1");
    CGContextEndTransparencyLayer(c);
    CHECK(r.layersEnded == 1 && near(r.layerAlpha, 0.25), "ending a layer is delivered with the outer state");
    CGContextEndTransparencyLayer(c);
    CHECK(r.layersEnded == 1, "an unbalanced end is ignored");

    CGContextBeginTransparencyLayer(c, NULL);
    CHECK(r.layersBegun == 2, "a layer without a rectangle is delivered too");
    CGContextEndTransparencyLayer(c);
    CHECK(r.layersEnded == 2, "and ended");
    CGContextRelease(c);
}

static void testMissingCallbacks(void) {
    Recorder r;
    memset(&r, 0, sizeof(r));
    CGContextDelegateRef delegate = CGContextDelegateCreate(&r);
    CGContextRef c = CGContextCreateWithDelegate(delegate, kCGContextTypeUnknown, NULL, NULL);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CGGlyph glyph = 1;
    CGPoint position = CGPointZero;
    CGContextShowGlyphsAtPositions(c, &glyph, &position, 1);
    CGContextBeginTransparencyLayer(c, NULL);
    CGContextEndTransparencyLayer(c);
    CHECK(r.paths == 0 && r.glyphRuns == 0 && r.layersBegun == 0, "a delegate without callbacks gets nothing");
    // a callback can be removed again
    CGContextDelegateSetCallback(delegate, deDrawPath, (CGContextDelegateCallback) drawPath);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CGContextDelegateSetCallback(delegate, deDrawPath, NULL);
    CGContextFillRect(c, CGRectMake(0, 0, 1, 1));
    CHECK(r.paths == 1, "a callback set and removed is called while set");
    CGContextRelease(c);
    CGContextDelegateRelease(delegate);
}

static void testGStateGetters(void) {
    CHECK(CGGStateGetAlpha(NULL) == 0, "NULL state: alpha 0");
    CHECK(CGGStateGetFont(NULL) == NULL, "NULL state: no font");
    CHECK(CGGStateGetFontSize(NULL) == 0, "NULL state: font size 0");
    CHECK(CGGStateGetCTM(NULL) == NULL, "NULL state: no CTM");
    CHECK(CGGStateGetFillColor(NULL) == NULL, "NULL state: no fill colour");
    CHECK(CGGStateGetStrokeColor(NULL) == NULL, "NULL state: no stroke colour");
    CHECK(CGGStateGetStyle(NULL) == NULL, "NULL state: no style");
}

int main(void) {
    testDelegateObject();
    testContextType();
    testPaths();
    testImages();
    testGlyphs();
    testLayers();
    testMissingCallbacks();
    testGStateGetters();
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
