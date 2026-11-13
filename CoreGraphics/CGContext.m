/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted,free of charge,to any person obtaining a copy of
this software and associated documentation files (the "Software"),to deal in the
Software without restriction,including without limitation the rights to
use,copy,modify,merge,publish,distribute,sublicense,and/or sell copies of the
Software,and to permit persons to whom the Software is furnished to do
so,subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS",WITHOUT WARRANTY OF ANY KIND,EXPRESS OR
IMPLIED,INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,DAMAGES OR OTHER LIABILITY,WHETHER IN
AN ACTION OF CONTRACT,TORT OR OTHERWISE,ARISING FROM,OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "CGConversions.h"
#import <CoreGraphics/CGContext.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2MutablePath.h>

CGContextRef CGContextRetain(CGContextRef context) {
    return (CGContextRef)O2ContextRetain((O2ContextRef)context);
}

void CGContextRelease(CGContextRef context) {
    O2ContextRelease((O2ContextRef)context);
}

void CGContextSetAllowsAntialiasing(CGContextRef context, bool yesOrNo) {
    O2ContextSetAllowsAntialiasing((O2ContextRef)context, yesOrNo);
}

void CGContextBeginTransparencyLayer(CGContextRef context,
                                     CFDictionaryRef unused)
{
    O2ContextBeginTransparencyLayer((O2ContextRef)context, (NSDictionary *) unused);
}

void CGContextEndTransparencyLayer(CGContextRef context) {
    O2ContextEndTransparencyLayer((O2ContextRef)context);
}

bool CGContextIsPathEmpty(CGContextRef context) {
    return O2ContextIsPathEmpty((O2ContextRef)context);
}

CGPoint CGContextGetPathCurrentPoint(CGContextRef context) {
    return O2ContextGetPathCurrentPoint((O2ContextRef)context);
}

CGRect CGContextGetPathBoundingBox(CGContextRef context) {
    return O2ContextGetPathBoundingBox((O2ContextRef)context);
}

bool CGContextSupportsGlobalAlpha(CGContextRef context) {
    return O2ContextSupportsGlobalAlpha((O2ContextRef)context);
}

bool CGContextIsBitmapContext(CGContextRef context) {
    return O2ContextIsBitmapContext((O2ContextRef)context);
}

bool CGContextPathContainsPoint(CGContextRef context, CGPoint point,
                                CGPathDrawingMode pathMode)
{
    return O2ContextPathContainsPoint((O2ContextRef)context, point, (O2PathDrawingMode)pathMode);
}

void CGContextBeginPath(CGContextRef context) {
    O2ContextBeginPath((O2ContextRef)context);
}

void CGContextClosePath(CGContextRef context) {
    O2ContextClosePath((O2ContextRef)context);
}

void CGContextMoveToPoint(CGContextRef context, CGFloat x, CGFloat y) {
    O2ContextMoveToPoint((O2ContextRef)context, x, y);
}

void CGContextAddLineToPoint(CGContextRef context, CGFloat x, CGFloat y) {
    O2ContextAddLineToPoint((O2ContextRef)context, x, y);
}

void CGContextAddCurveToPoint(CGContextRef context, CGFloat cx1, CGFloat cy1,
                              CGFloat cx2, CGFloat cy2, CGFloat x, CGFloat y)
{
    O2ContextAddCurveToPoint((O2ContextRef)context, cx1, cy1, cx2, cy2, x, y);
}

void CGContextAddQuadCurveToPoint(CGContextRef context, CGFloat cx1,
                                  CGFloat cy1, CGFloat x, CGFloat y)
{
    O2ContextAddQuadCurveToPoint((O2ContextRef)context, cx1, cy1, x, y);
}

void CGContextAddLines(CGContextRef context, const CGPoint *points,
                       unsigned count)
{
    O2ContextAddLines((O2ContextRef)context, points, count);
}

void CGContextAddRect(CGContextRef context, CGRect rect) {
    O2ContextAddRect((O2ContextRef)context, rect);
}

void CGContextAddRects(CGContextRef context, const CGRect *rects,
                       unsigned count)
{
    O2ContextAddRects((O2ContextRef)context, rects, count);
}

void CGContextAddArc(CGContextRef context, CGFloat x, CGFloat y, CGFloat radius,
                     CGFloat startRadian, CGFloat endRadian, bool clockwise)
{
    O2ContextAddArc((O2ContextRef)context, x, y, radius, startRadian, endRadian, clockwise);
}

void CGContextAddArcToPoint(CGContextRef context, CGFloat x1, CGFloat y1,
                            CGFloat x2, CGFloat y2, CGFloat radius)
{
    O2ContextAddArcToPoint((O2ContextRef)context, x1, y1, x2, y2, radius);
}

void CGContextAddEllipseInRect(CGContextRef context, CGRect rect) {
    O2ContextAddEllipseInRect((O2ContextRef)context, rect);
}

void CGContextAddPath(CGContextRef context, CGPathRef path) {
    O2ContextAddPath((O2ContextRef)context, (O2PathRef)path);
}

void CGContextReplacePathWithStrokedPath(CGContextRef context) {
    O2ContextReplacePathWithStrokedPath((O2ContextRef)context);
}

CGPathRef CGContextCopyPath(CGContextRef context) {
    return (CGPathRef)O2ContextCopyPath((O2ContextRef)context);
}

void CGContextSaveGState(CGContextRef context) {
    O2ContextSaveGState((O2ContextRef)context);
}

void CGContextRestoreGState(CGContextRef context) {
    O2ContextRestoreGState((O2ContextRef)context);
}

CGAffineTransform
CGContextGetUserSpaceToDeviceSpaceTransform(CGContextRef context)
{
    return CGAffineTransformFromO2(
            O2ContextGetUserSpaceToDeviceSpaceTransform((O2ContextRef)context));
}

CGAffineTransform CGContextGetCTM(CGContextRef context) {
    return CGAffineTransformFromO2(O2ContextGetCTM((O2ContextRef)context));
}

CGRect CGContextGetClipBoundingBox(CGContextRef context) {
    return O2ContextGetClipBoundingBox((O2ContextRef)context);
}

CGAffineTransform CGContextGetTextMatrix(CGContextRef context) {
    return CGAffineTransformFromO2(O2ContextGetTextMatrix((O2ContextRef)context));
}

CGInterpolationQuality CGContextGetInterpolationQuality(CGContextRef context) {
    return O2ContextGetInterpolationQuality((O2ContextRef)context);
}

CGPoint CGContextGetTextPosition(CGContextRef context) {
    return O2ContextGetTextPosition((O2ContextRef)context);
}

CGPoint CGContextConvertPointToDeviceSpace(CGContextRef context, CGPoint point)
{
    return O2ContextConvertPointToDeviceSpace((O2ContextRef)context, point);
}

CGPoint CGContextConvertPointToUserSpace(CGContextRef context, CGPoint point) {
    return O2ContextConvertPointToUserSpace((O2ContextRef)context, point);
}

CGSize CGContextConvertSizeToDeviceSpace(CGContextRef context, CGSize size) {
    return O2ContextConvertSizeToDeviceSpace((O2ContextRef)context, size);
}

CGSize CGContextConvertSizeToUserSpace(CGContextRef context, CGSize size) {
    return O2ContextConvertSizeToUserSpace((O2ContextRef)context, size);
}

CGRect CGContextConvertRectToDeviceSpace(CGContextRef context, CGRect rect) {
    return O2ContextConvertRectToDeviceSpace((O2ContextRef)context, rect);
}

CGRect CGContextConvertRectToUserSpace(CGContextRef context, CGRect rect) {
    return O2ContextConvertRectToUserSpace((O2ContextRef)context, rect);
}

void CGContextSetCTM(CGContextRef context, CGAffineTransform matrix) {
    O2ContextSetCTM((O2ContextRef)context, O2AffineTransformFromCG(matrix));
}

void CGContextConcatCTM(CGContextRef context, CGAffineTransform matrix) {
    O2ContextConcatCTM((O2ContextRef)context, O2AffineTransformFromCG(matrix));
}

void CGContextTranslateCTM(CGContextRef context, CGFloat tx, CGFloat ty) {
    O2ContextTranslateCTM((O2ContextRef)context, tx, ty);
}

void CGContextScaleCTM(CGContextRef context, CGFloat scalex, CGFloat scaley) {
    O2ContextScaleCTM((O2ContextRef)context, scalex, scaley);
}

void CGContextRotateCTM(CGContextRef context, CGFloat radians) {
    O2ContextRotateCTM((O2ContextRef)context, radians);
}

void CGContextClip(CGContextRef context) {
    O2ContextClip((O2ContextRef)context);
}

void CGContextEOClip(CGContextRef context) {
    O2ContextEOClip((O2ContextRef)context);
}

void CGContextClipToMask(CGContextRef context, CGRect rect, CGImageRef image) {
    O2ContextClipToMask((O2ContextRef)context, rect, (O2ImageRef)image);
}

void CGContextClipToRect(CGContextRef context, CGRect rect) {
    O2ContextClipToRect((O2ContextRef)context, rect);
}

void CGContextClipToRects(CGContextRef context, const CGRect *rects,
                          unsigned count)
{
    O2ContextClipToRects((O2ContextRef)context, rects, count);
}

void CGContextSetStrokeColorSpace(CGContextRef context,
                                  CGColorSpaceRef colorSpace)
{
    O2ContextSetStrokeColorSpace((O2ContextRef)context, (O2ColorSpaceRef)colorSpace);
}

void CGContextSetFillColorSpace(CGContextRef context,
                                CGColorSpaceRef colorSpace)
{
    O2ContextSetFillColorSpace((O2ContextRef)context, (O2ColorSpaceRef)colorSpace);
}

void CGContextSetStrokeColor(CGContextRef context, const CGFloat *components) {
    O2ContextSetStrokeColor((O2ContextRef)context, components);
}

void CGContextSetStrokeColorWithColor(CGContextRef context, CGColorRef color) {
    O2ContextSetStrokeColorWithColor((O2ContextRef)context, (O2ColorRef)color);
}

void CGContextSetGrayStrokeColor(CGContextRef context, CGFloat gray,
                                 CGFloat alpha)
{
    O2ContextSetGrayStrokeColor((O2ContextRef)context, gray, alpha);
}

void CGContextSetRGBStrokeColor(CGContextRef context, CGFloat r, CGFloat g,
                                CGFloat b, CGFloat alpha)
{
    O2ContextSetRGBStrokeColor((O2ContextRef)context, r, g, b, alpha);
}

void CGContextSetCMYKStrokeColor(CGContextRef context, CGFloat c, CGFloat m,
                                 CGFloat y, CGFloat k, CGFloat alpha)
{
    O2ContextSetCMYKStrokeColor((O2ContextRef)context, c, m, y, k, alpha);
}

void CGContextSetFillColor(CGContextRef context, const CGFloat *components) {
    O2ContextSetFillColor((O2ContextRef)context, components);
}

void CGContextSetFillColorWithColor(CGContextRef context, CGColorRef color) {
    O2ContextSetFillColorWithColor((O2ContextRef)context, (O2ColorRef)color);
}

void CGContextSetGrayFillColor(CGContextRef context, CGFloat gray,
                               CGFloat alpha)
{
    O2ContextSetGrayFillColor((O2ContextRef)context, gray, alpha);
}

void CGContextSetRGBFillColor(CGContextRef context, CGFloat r, CGFloat g,
                              CGFloat b, CGFloat alpha)
{
    O2ContextSetRGBFillColor((O2ContextRef)context, r, g, b, alpha);
}

void CGContextSetCMYKFillColor(CGContextRef context, CGFloat c, CGFloat m,
                               CGFloat y, CGFloat k, CGFloat alpha)
{
    O2ContextSetCMYKFillColor((O2ContextRef)context, c, m, y, k, alpha);
}

void CGContextSetAlpha(CGContextRef context, CGFloat alpha) {
    O2ContextSetAlpha((O2ContextRef)context, alpha);
}

void CGContextSetPatternPhase(CGContextRef context, CGSize phase) {
    O2ContextSetPatternPhase((O2ContextRef)context, phase);
}

void CGContextSetStrokePattern(CGContextRef context, CGPatternRef pattern,
                               const CGFloat *components)
{
    O2ContextSetStrokePattern((O2ContextRef)context, (O2PatternRef)pattern, components);
}

void CGContextSetFillPattern(CGContextRef context, CGPatternRef pattern,
                             const CGFloat *components)
{
    O2ContextSetFillPattern((O2ContextRef)context, (O2PatternRef)pattern, components);
}

void CGContextSetTextMatrix(CGContextRef context, CGAffineTransform matrix) {
    O2ContextSetTextMatrix((O2ContextRef)context, O2AffineTransformFromCG(matrix));
}

void CGContextSetTextPosition(CGContextRef context, CGFloat x, CGFloat y) {
    O2ContextSetTextPosition((O2ContextRef)context, x, y);
}

void CGContextSetCharacterSpacing(CGContextRef context, CGFloat spacing) {
    O2ContextSetCharacterSpacing((O2ContextRef)context, spacing);
}

void CGContextSetTextDrawingMode(CGContextRef context,
                                 CGTextDrawingMode textMode)
{
    O2ContextSetTextDrawingMode((O2ContextRef)context, textMode);
}

void CGContextSetFont(CGContextRef context, CGFontRef font) {
    O2ContextSetFont((O2ContextRef)context, (O2FontRef)font);
}

void CGContextSetFontSize(CGContextRef context, CGFloat size) {
    O2ContextSetFontSize((O2ContextRef)context, size);
}

void CGContextSelectFont(CGContextRef context, const char *name, CGFloat size,
                         CGTextEncoding encoding)
{
    O2ContextSelectFont((O2ContextRef)context, name, size, encoding);
}

void CGContextSetShouldSmoothFonts(CGContextRef context, bool yesOrNo) {
    O2ContextSetShouldSmoothFonts((O2ContextRef)context, yesOrNo);
}

void CGContextSetLineWidth(CGContextRef context, CGFloat width) {
    O2ContextSetLineWidth((O2ContextRef)context, width);
}

void CGContextSetLineCap(CGContextRef context, CGLineCap lineCap) {
    O2ContextSetLineCap((O2ContextRef)context, lineCap);
}

void CGContextSetLineJoin(CGContextRef context, CGLineJoin lineJoin) {
    O2ContextSetLineJoin((O2ContextRef)context, lineJoin);
}

void CGContextSetMiterLimit(CGContextRef context, CGFloat miterLimit) {
    O2ContextSetMiterLimit((O2ContextRef)context, miterLimit);
}

void CGContextSetLineDash(CGContextRef context, CGFloat phase,
                          const CGFloat *lengths, unsigned count)
{
    O2ContextSetLineDash((O2ContextRef)context, phase, lengths, count);
}

void CGContextSetRenderingIntent(CGContextRef context,
                                 CGColorRenderingIntent renderingIntent)
{
    O2ContextSetRenderingIntent((O2ContextRef)context, renderingIntent);
}

void CGContextSetBlendMode(CGContextRef context, CGBlendMode blendMode) {
    O2ContextSetBlendMode((O2ContextRef)context, blendMode);
}

void CGContextSetFlatness(CGContextRef context, CGFloat flatness) {
    O2ContextSetFlatness((O2ContextRef)context, flatness);
}

void CGContextSetInterpolationQuality(CGContextRef context,
                                      CGInterpolationQuality quality)
{
    O2ContextSetInterpolationQuality((O2ContextRef)context, quality);
}

void CGContextSetShadowWithColor(CGContextRef context, CGSize offset,
                                 CGFloat blur, CGColorRef color)
{
    O2ContextSetShadowWithColor((O2ContextRef)context, offset, blur, (O2ColorRef)color);
}

void CGContextSetShadow(CGContextRef context, CGSize offset, CGFloat blur) {
    O2ContextSetShadow((O2ContextRef)context, offset, blur);
}

void CGContextSetShouldAntialias(CGContextRef context, bool yesOrNo) {
    O2ContextSetShouldAntialias((O2ContextRef)context, yesOrNo);
}

void CGContextStrokeLineSegments(CGContextRef context, const CGPoint *points,
                                 unsigned count)
{
    O2ContextStrokeLineSegments((O2ContextRef)context, points, count);
}

void CGContextStrokeRect(CGContextRef context, CGRect rect) {
    O2ContextStrokeRect((O2ContextRef)context, rect);
}

void CGContextStrokeRectWithWidth(CGContextRef context, CGRect rect,
                                  CGFloat width)
{
    O2ContextStrokeRectWithWidth((O2ContextRef)context, rect, width);
}

void CGContextStrokeEllipseInRect(CGContextRef context, CGRect rect) {
    O2ContextStrokeEllipseInRect((O2ContextRef)context, rect);
}

void CGContextFillRect(CGContextRef context, CGRect rect) {
    O2ContextFillRect((O2ContextRef)context, rect);
}

void CGContextFillRects(CGContextRef context, const CGRect *rects,
                        unsigned count)
{
    O2ContextFillRects((O2ContextRef)context, rects, count);
}

void CGContextFillEllipseInRect(CGContextRef context, CGRect rect) {
    O2ContextFillEllipseInRect((O2ContextRef)context, rect);
}

void CGContextDrawPath(CGContextRef context, CGPathDrawingMode pathMode) {
    O2ContextDrawPath((O2ContextRef)context, pathMode);
}

void CGContextStrokePath(CGContextRef context) {
    O2ContextStrokePath((O2ContextRef)context);
}

void CGContextFillPath(CGContextRef context) {
    O2ContextFillPath((O2ContextRef)context);
}

void CGContextEOFillPath(CGContextRef context) {
    O2ContextEOFillPath((O2ContextRef)context);
}

void CGContextClearRect(CGContextRef context, CGRect rect) {
    O2ContextClearRect((O2ContextRef)context, rect);
}

void CGContextShowGlyphs(CGContextRef context, const CGGlyph *glyphs,
                         unsigned count)
{
    O2ContextShowGlyphs((O2ContextRef)context, glyphs, count);
}

void CGContextShowGlyphsAtPoint(CGContextRef context, CGFloat x, CGFloat y,
                                const CGGlyph *glyphs, unsigned count)
{
    O2ContextShowGlyphsAtPoint((O2ContextRef)context, x, y, glyphs, count);
}

void CGContextShowGlyphsWithAdvances(CGContextRef context,
                                     const CGGlyph *glyphs,
                                     const CGSize *advances, unsigned count)
{
    O2ContextShowGlyphsWithAdvances((O2ContextRef)context, glyphs, advances, count);
}

void CGContextShowText(CGContextRef context, const char *text, unsigned count) {
    O2ContextShowText((O2ContextRef)context, text, count);
}

void CGContextShowTextAtPoint(CGContextRef context, CGFloat x, CGFloat y,
                              const char *text, unsigned count)
{
    O2ContextShowTextAtPoint((O2ContextRef)context, x, y, text, count);
}

void CGContextDrawShading(CGContextRef context, CGShadingRef shading) {
    O2ContextDrawShading((O2ContextRef)context, (O2ShadingRef)shading);
}

void CGContextDrawImage(CGContextRef context, CGRect rect, CGImageRef image) {
    O2ContextDrawImage((O2ContextRef)context, rect, (O2ImageRef)image);
}

void CGContextDrawLayerAtPoint(CGContextRef context, CGPoint point,
                               CGLayerRef layer)
{
    O2ContextDrawLayerAtPoint((O2ContextRef)context, point, (O2LayerRef)layer);
}

void CGContextDrawLayerInRect(CGContextRef context, CGRect rect,
                              CGLayerRef layer)
{
    O2ContextDrawLayerInRect((O2ContextRef)context, rect, (O2LayerRef)layer);
}

void CGContextDrawPDFPage(CGContextRef context, CGPDFPageRef page) {
    O2ContextDrawPDFPage((O2ContextRef)context, (O2PDFPageRef)page);
}

void CGContextFlush(CGContextRef context) {
    O2ContextFlush((O2ContextRef)context);
}

void CGContextSynchronize(CGContextRef context) {
    O2ContextSynchronize((O2ContextRef)context);
}

void CGContextBeginPage(CGContextRef context, const CGRect *mediaBox) {
    O2ContextBeginPage((O2ContextRef)context, mediaBox);
}

void CGContextEndPage(CGContextRef context) {
    O2ContextEndPage((O2ContextRef)context);
}

/// temporary hacks

void CGContextResetClip(CGContextRef context) {
    O2ContextResetClip((O2ContextRef)context);
}

void CGContextCopyBits(CGContextRef context, CGRect rect, CGPoint point,
                       int gState)
{
    O2ContextCopyBits((O2ContextRef)context, rect, point, gState);
}

CFDataRef CGContextCaptureBitmap(CGContextRef context, CGRect rect) {
    return (CFDataRef) O2ContextCaptureBitmap((O2ContextRef)context, rect);
}

void CGContextSetAllowsFontSmoothing(CGContextRef context,
                                     bool allowsFontSmoothing)
{
    O2ContextSetAllowsFontSmoothing((O2ContextRef) context,
                                    allowsFontSmoothing);
}

void CGContextSetAllowsFontSubpixelQuantization(
        CGContextRef context, bool allowsFontSubpixelQuantization)
{
    O2ContextSetAllowsFontSubpixelQuantization((O2ContextRef) context,
                                               allowsFontSubpixelQuantization);
}

void CGContextSetShouldSubpixelQuantizeFonts(CGContextRef context,
                                             bool shouldSubpixelQuantizeFonts)
{
    O2ContextSetShouldSubpixelQuantizeFonts((O2ContextRef) context,
                                            shouldSubpixelQuantizeFonts);
}

void CGContextSetAllowsFontSubpixelPositioning(
        CGContextRef context, bool allowsFontSubpixelPositioning)
{
    O2ContextSetAllowsFontSubpixelPositioning((O2ContextRef) context,
                                              allowsFontSubpixelPositioning);
}

void CGContextSetShouldSubpixelPositionFonts(CGContextRef context,
                                             bool shouldSubpixelPositionFonts)
{
    O2ContextSetShouldSubpixelPositionFonts((O2ContextRef) context,
                                            shouldSubpixelPositionFonts);
}

void CGContextDrawLinearGradient(CGContextRef c,
                                 CGGradientRef gradient, CGPoint startPoint, CGPoint endPoint,
                                 CGGradientDrawingOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

void CGContextDrawRadialGradient(CGContextRef c,
                                 CGGradientRef gradient, CGPoint startCenter, CGFloat startRadius,
                                 CGPoint endCenter, CGFloat endRadius, CGGradientDrawingOptions options)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

void CGContextDrawTiledImage(CGContextRef c, CGRect rect, CGImageRef image)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

void CGContextShowGlyphsAtPositions(CGContextRef c,
                                    const CGGlyph *glyphs, const CGPoint *positions,
                                    size_t count)
{
    if (c == NULL || glyphs == NULL || positions == NULL)
        return;
    // Each position is in text space: the text matrix is applied to it to
    // find where the glyph origin lands (a shear or translation in the text
    // matrix moves the glyph). The text matrix and text position are left as
    // they were.
    CGAffineTransform matrix = CGContextGetTextMatrix(c);
    CGPoint saved = CGContextGetTextPosition(c);
    for (size_t i = 0; i < count; i++) {
        CGPoint origin = CGPointApplyAffineTransform(positions[i], matrix);
        CGContextShowGlyphsAtPoint(c, origin.x, origin.y, glyphs + i, 1);
    }
    CGContextSetTextMatrix(c, matrix);
    CGContextSetTextPosition(c, saved.x, saved.y);
}
