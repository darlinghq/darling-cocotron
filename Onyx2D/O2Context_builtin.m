/*
 * Copyright (c) 2007 The Khronos Group Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and /or associated documentation files
 * (the "Materials "), to deal in the Materials without restriction,
 * including without limitation the rights to use, copy, modify, merge,
 * publish, distribute, sublicense, and/or sell copies of the Materials,
 * and to permit persons to whom the Materials are furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Materials.
 *
 * THE MATERIALS ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE MATERIALS OR
 * THE USE OR OTHER DEALINGS IN THE MATERIALS.
 */
#import <Onyx2D/O2ClipPhase.h>
#import <Onyx2D/O2ClipState.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Context_builtin.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Image.h>
#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2Paint_axialGradient.h>
#import <Onyx2D/O2Paint_conicGradient.h>
#import <Onyx2D/O2Paint_color.h>
#import <Onyx2D/O2Paint_image.h>
#import <Onyx2D/O2Paint_pattern.h>
#import <Onyx2D/O2Paint_radialGradient.h>
#import <Onyx2D/O2Shading.h>
#import <Onyx2D/O2Surface.h>
#import <Onyx2D/VGPath.h>

#define MAX_SAMPLES COVERAGE_MULTIPLIER

void O2DContextClipAndFillEdges(O2Context_builtin *self, int fillRuleMask);

@implementation O2Context_builtin

+ (BOOL) canInitBitmap {
    return YES;
}

- (void) reallocateForSurface {
    size_t width = O2ImageGetWidth(_surface);

    if (self->_winding != NULL)
        free(self->_winding);
    // +1 is so we can modify the the next winding value without a bounds check
    self->_winding = calloc((width * MAX_SAMPLES) + 1, sizeof(int));
    if (self->_increase != NULL)
        free(self->_increase);
    self->_increase = malloc(width * sizeof(int));
    int i;
    for (i = 0; i < width; i++)
        self->_increase[i] = INT_MAX;
}

- initWithSurface: (O2Surface *) surface flipped: (BOOL) flipped {
    [super initWithSurface: surface flipped: flipped];

    _clipMask = nil;

    O2PaintRef paint =
            [[O2Paint_color alloc] initWithGray: 0
                                          alpha: 1
                        surfaceToPaintTransform: O2AffineTransformIdentity];

    O2ContextSetupPaintAndBlendMode(self, paint, kO2BlendModeNormal);

    O2PaintRelease(paint);

    _vpwidth = self->_vpheight = 0;

    _edgeCount = 0;
    _edgeCapacity = 256;
    _edges = NSZoneMalloc(NULL, self->_edgeCapacity * sizeof(Edge *));
    _sortCache =
            NSZoneMalloc(NULL, (self->_edgeCapacity / 2 + 1) * sizeof(Edge *));

    sampleSizeShift = 0;
    numSamples = 0;
    samplesWeight = 0;
    samplesX = NSZoneMalloc(NULL, MAX_SAMPLES * sizeof(O2Float));

    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(_surface),
                            O2ImageGetHeight(_surface));
    [self reallocateForSurface];
    return self;
}

- (void) dealloc {
    [_clipMask release];
    [_paint release];

    if (_edges != NULL) {
        int i;
        for (i = 0; i < _edgeCount; i++)
            NSZoneFree(NULL, _edges[i]);

        NSZoneFree(NULL, _edges);
    }
    if (_sortCache != NULL)
        NSZoneFree(NULL, _sortCache);

    if (_winding != NULL)
        free(_winding);
    if (_increase != NULL)
        free(_increase);
    if (samplesX != NULL)
        NSZoneFree(NULL, samplesX);

    [super dealloc];
}

- (O2Surface *) surface {
    return _surface;
}

- (void) setWidth: (size_t) width
                          height: (size_t) height
        reallocateOnlyIfRequired: (BOOL) roir
{
    [_surface setWidth: width height: height reallocateOnlyIfRequired: roir];
    [self reallocateForSurface];
    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(_surface),
                            O2ImageGetHeight(_surface));
    O2AffineTransform flip = {1, 0, 0, -1, 0, O2ImageGetHeight(_surface)};
    O2GStateSetDeviceSpaceCTM(O2ContextCurrentGState(self), flip);
}

- (O2Surface *) createSurfaceWithWidth: (size_t) width height: (size_t) height {
    return [[[self surfaceClass] alloc]
               initWithBytes: NULL
                       width: width
                      height: height
            bitsPerComponent: O2ImageGetBitsPerComponent(_surface)
                 bytesPerRow: 0
                  colorSpace: O2ImageGetColorSpace(_surface)
                  bitmapInfo: O2ImageGetBitmapInfo(_surface)];
}

- (O2Size) size {
    return O2SizeMake(O2ImageGetWidth(_surface), O2ImageGetHeight(_surface));
}

- (O2ContextRef) createCompatibleContextWithSize: (O2Size) size
                                          unused: (NSDictionary *) unused
{
    // A layer (a transparency layer, a CGLayer) holds content that is composited onto the context
    // afterwards, so it needs an alpha channel even where the context's own surface has none.
    O2BitmapInfo bitmapInfo = O2ImageGetBitmapInfo(_surface);
    O2BitmapInfo alphaInfo = bitmapInfo & kO2BitmapAlphaInfoMask;

    if (alphaInfo == kO2ImageAlphaNoneSkipFirst || alphaInfo == kO2ImageAlphaNone)
        bitmapInfo = (bitmapInfo & ~kO2BitmapAlphaInfoMask) | kO2ImageAlphaPremultipliedFirst;
    else if (alphaInfo == kO2ImageAlphaNoneSkipLast)
        bitmapInfo = (bitmapInfo & ~kO2BitmapAlphaInfoMask) | kO2ImageAlphaPremultipliedLast;

    O2Surface *surface = [[[self surfaceClass] alloc] initWithBytes: NULL
                                                              width: ceil(size.width)
                                                             height: ceil(size.height)
                                                   bitsPerComponent: O2ImageGetBitsPerComponent(_surface)
                                                        bytesPerRow: 0
                                                         colorSpace: O2ImageGetColorSpace(_surface)
                                                         bitmapInfo: bitmapInfo];
    O2ContextRef result = [[[self class] alloc] initWithSurface: surface
                                                        flipped: NO];
    [surface release];
    return result;
}

- (void) beginTransparencyLayerWithInfo: (NSDictionary *) unused {
    O2LayerRef layer = O2LayerCreateWithContext(self, [self size], unused);

    [self->_layerStack addObject: layer];
    O2LayerRelease(layer);
    O2ContextSaveGState(self);

    /**
     * From Cocoa doc :
     * graphics state parameters remain unchanged except for alpha (which is set
     * to 1), shadow (which is turned off), blend mode (which is set to normal),
     * and other parameters that affect the final composite.
     */
    O2GStateSetBlendMode(O2ContextCurrentGState(self), kO2BlendModeNormal);
    [O2ContextCurrentGState(self) setShadowOffset: O2SizeZero
                                             blur: 0.
                                            color: nil];
    O2GStateSetAlpha(O2ContextCurrentGState(self), 1.);
}

- (void) endTransparencyLayer {
    O2LayerRef layer = O2LayerRetain([self->_layerStack lastObject]);

    O2ContextRestoreGState(self);
    [self->_layerStack removeLastObject];

    O2Size size = [self size];

    // The layer holds device pixels: composite it without the current user CTM.
    O2GState *gState = O2ContextCurrentGState(self);
    O2AffineTransform base = O2AffineTransformConcat(
            O2AffineTransformInvert(gState->_userSpaceTransform),
            gState->_deviceSpaceTransform);
    O2ContextSaveGState(self);
    O2GStateSetUserSpaceCTM(O2ContextCurrentGState(self),
                            O2AffineTransformIdentity);
    O2GStateSetDeviceSpaceCTM(O2ContextCurrentGState(self), base);

    if (O2ContextCurrentGState(self)->_shadowKernel) {
        O2Surface *shadow =
                [self createSurfaceWithWidth: O2ImageGetWidth(_surface)
                                      height: O2ImageGetHeight(_surface)];

        O2SurfaceGaussianBlur(shadow, O2LayerGetSurface(layer),
                              O2ContextCurrentGState(self)->_shadowKernel,
                              O2ContextCurrentGState(self)->_shadowColor);
        O2ContextDrawImage(
                self,
                O2RectMake(O2ContextCurrentGState(self)->_shadowOffset.width,
                           O2ContextCurrentGState(self)->_shadowOffset.height,
                           size.width, size.height),
                shadow);
        [shadow release];
    }

    O2ContextDrawLayerInRect(self, O2RectMake(0, 0, size.width, size.height),
                             layer);
    O2ContextRestoreGState(self);
    O2LayerRelease(layer);
}

void O2ContextDeviceClipReset_builtin(O2Context_builtin *self) {
    O2RasterizerSetViewport(self, 0, 0, O2ImageGetWidth(self->_surface),
                            O2ImageGetHeight(self->_surface));
}

ONYX2D_STATIC void O2ContextClipViewportToPath(O2Context_builtin *self,
                                               O2Path *path)
{
    O2Rect viewport =
            O2RectMake(self->_vpx, self->_vpy, self->_vpwidth, self->_vpheight);
    O2Rect rect = O2PathGetBoundingBox(path);

    rect = O2RectIntegral(rect);

    viewport = O2RectIntersection(viewport, rect);

    self->_vpx = viewport.origin.x;
    self->_vpy = viewport.origin.y;
    self->_vpwidth = viewport.size.width;
    self->_vpheight = viewport.size.height;
}

/* Clipping to a path keeps the area the path covers, with the coverage of its
   edge pixels, in the per pixel clip mask that masks and earlier paths also
   use. An axis aligned rectangle only narrows the viewport, as before, so
   the common rectangular clips need no mask. The path is in device space. */
ONYX2D_STATIC void O2ContextClipToPathShape(O2Context_builtin *self,
                                            O2Path *path, BOOL evenOdd)
{
    O2Rect rect;

    if (O2PathIsRect(path, &rect)) {
        O2ContextClipViewportToPath(self, path);
        return;
    }
    O2ContextClipViewportToPath(self, path);

    size_t width = O2ImageGetWidth(self->_surface);
    size_t height = O2ImageGetHeight(self->_surface);

    if (width == 0 || height == 0)
        return;

    if (self->_clipMask == nil) {
        O2ColorSpaceRef gray = O2ColorSpaceCreateDeviceGray();

        self->_clipMask = [[O2Surface alloc] initWithBytes: NULL
                                                     width: width
                                                    height: height
                                          bitsPerComponent: 8
                                               bytesPerRow: 0
                                                colorSpace: gray
                                                bitmapInfo: kO2ImageAlphaNone];
        O2ColorSpaceRelease(gray);
        if (self->_clipMask == nil)
            return;
        memset(O2SurfaceGetPixelBytes(self->_clipMask), 0xFF,
               O2SurfaceGetBytesPerRow(self->_clipMask) * height);
    }

    uint8_t *bytes = O2SurfaceGetPixelBytes(self->_clipMask);
    size_t bytesPerRow = O2SurfaceGetBytesPerRow(self->_clipMask);

    // The area the path can cover, in whole pixels of the surface.
    O2Rect box = O2PathGetBoundingBox(path);
    long x0 = MAX(0, (long) floor(box.origin.x));
    long y0 = MAX(0, (long) floor(box.origin.y));
    long x1 = MIN((long) width, (long) ceil(box.origin.x + box.size.width));
    long y1 = MIN((long) height, (long) ceil(box.origin.y + box.size.height));
    long boxWidth = x1 - x0, boxHeight = y1 - y0;

    // Everything outside the area is clipped away.
    for (long y = 0; y < (long) height; y++) {
        uint8_t *line = bytes + y * bytesPerRow;

        if (y < y0 || y >= y1 || boxWidth <= 0) {
            memset(line, 0, width);
        } else {
            memset(line, 0, x0);
            memset(line + x1, 0, width - x1);
        }
    }
    if (boxWidth <= 0 || boxHeight <= 0)
        return;

    // Coverage of the path, rendered white on black by the context's own
    // anti-aliasing rasterizer into a surface of the area's size.
    O2ColorSpaceRef gray = O2ColorSpaceCreateDeviceGray();
    O2Surface *coverage = [[O2Surface alloc] initWithBytes: NULL
                                                     width: boxWidth
                                                    height: boxHeight
                                          bitsPerComponent: 8
                                               bytesPerRow: 0
                                                colorSpace: gray
                                                bitmapInfo: kO2ImageAlphaNone];

    O2ColorSpaceRelease(gray);
    if (coverage == nil)
        return;
    memset(O2SurfaceGetPixelBytes(coverage), 0,
           O2SurfaceGetBytesPerRow(coverage) * boxHeight);

    // The path is in device space, which is what the coverage surface is in as
    // well: its context must not flip it a second time.
    O2Context_builtin *context = [[[self class] alloc] initWithSurface: coverage
                                                               flipped: YES];
    O2MutablePathRef moved = O2PathCreateMutableCopy(path);

    O2PathApplyTransform(moved, O2AffineTransformMakeTranslation(-x0, -y0));
    O2ContextAddPath(context, moved);
    O2ContextSetGrayFillColor(context, 1, 1);
    if (evenOdd)
        O2ContextEOFillPath(context);
    else
        O2ContextFillPath(context);
    O2PathRelease(moved);

    uint8_t *source = O2SurfaceGetPixelBytes(coverage);
    size_t sourceBytesPerRow = O2SurfaceGetBytesPerRow(coverage);

    for (long y = 0; y < boxHeight; y++) {
        uint8_t *line = bytes + (y0 + y) * bytesPerRow + x0;
        uint8_t *from = source + y * sourceBytesPerRow;

        for (long x = 0; x < boxWidth; x++)
            line[x] = (line[x] * (unsigned) from[x] + 127) / 255;
    }
    O2ContextRelease(context);
    [coverage release];
}

void O2ContextDeviceClipToNonZeroPath_builtin(O2Context_builtin *self,
                                              O2Path *path)
{
    O2ContextClipToPathShape(self, path, NO);
}

void O2ContextDeviceClipToEvenOddPath_builtin(O2Context_builtin *self,
                                              O2Path *path)
{
    O2ContextClipToPathShape(self, path, YES);
}

static void O2ContextDeviceClipToMask_builtin(O2Context_builtin *self,
                                              O2ClipPhase *phase);

- (void) clipToState: (O2ClipState *) clipState {
    O2GState *gState = O2ContextCurrentGState(self);
    NSArray *phases = [O2GStateClipState(gState) clipPhases];
    int i, count = [phases count];

    O2ContextDeviceClipReset_builtin(self);
    [_clipMask release];
    _clipMask = nil;

    for (i = 0; i < count; i++) {
        O2ClipPhase *phase = [phases objectAtIndex: i];
        O2Path *path;

        switch (O2ClipPhasePhaseType(phase)) {

        case O2ClipPhaseNonZeroPath:;
            path = O2ClipPhaseObject(phase);
            O2ContextDeviceClipToNonZeroPath_builtin(self, path);
            break;

        case O2ClipPhaseEOPath:;
            path = O2ClipPhaseObject(phase);
            O2ContextDeviceClipToEvenOddPath_builtin(self, path);
            break;

        case O2ClipPhaseMask:
            O2ContextDeviceClipToMask_builtin(self, phase);
            break;
        }
    }
}

ONYX2D_STATIC O2Paint *paintFromColor(O2Context_builtin *self, O2ColorRef color,
                                      O2AffineTransform surfaceToPaintMatrix)
{
    O2Paint *result = nil;
    O2PatternRef pattern = O2ColorGetPattern(color);

    // A color of a profiled space is converted to the space of the surface.
    O2ColorRef converted = NULL;
    if (pattern == NULL) {
        O2ColorSpaceRef surfaceSpace = O2ImageGetColorSpace(self->_surface);
        O2ColorSpaceRef colorSpace = O2ColorGetColorSpace(color);
        O2ColorProfile surfaceProfile, colorProfile;
        CFStringRef surfaceName = O2ColorSpaceGetName(surfaceSpace);
        CFStringRef colorName = O2ColorSpaceGetName(colorSpace);
        if (surfaceName != NULL && colorName != NULL &&
            !CFEqual(surfaceName, colorName) &&
            O2ColorSpaceGetColorProfile(surfaceSpace, &surfaceProfile) &&
            O2ColorSpaceGetColorProfile(colorSpace, &colorProfile)) {
            converted = O2ColorCreateCopyByMatchingToColorSpace(surfaceSpace,
                                                                color);
            if (converted != NULL)
                color = converted;
        }
    }

    if (pattern != NULL) {
        O2GState *gState = O2ContextCurrentGState(self);
        O2Size size = [pattern bounds].size;
        O2Surface *surface = [self createSurfaceWithWidth: size.width
                                                   height: size.height];
        O2BitmapContext *context =
                [[[self class] alloc] initWithSurface: surface flipped: NO];

        O2ContextClearRect(context, O2RectMake(0, 0, size.width, size.height));
        // do save/restore? probably pointless
        [pattern drawInContext: context];

        result = [[O2Paint_pattern alloc]
                          initWithImage: surface
                surfaceToPaintTransform: surfaceToPaintMatrix
                                  phase: O2GStatePatternPhase(gState)];

        O2ContextRelease(context);
        [surface release];
    } else {
        size_t count = O2ColorGetNumberOfComponents(color);
        const O2Float *components = O2ColorGetComponents(color);

        if (count == 2)
            result = [[O2Paint_color alloc] initWithGray: components[0]
                                                   alpha: components[1]
                                 surfaceToPaintTransform: surfaceToPaintMatrix];
        else if (count == 4)
            result = [[O2Paint_color alloc] initWithRed: components[0]
                                                  green: components[1]
                                                   blue: components[2]
                                                  alpha: components[3]
                                surfaceToPaintTransform: surfaceToPaintMatrix];
        else
            result = [[O2Paint_color alloc] initWithGray: 0
                                                   alpha: 1
                                 surfaceToPaintTransform: surfaceToPaintMatrix];
    }

    O2ColorRelease(converted);
    return result;
}

- (void) drawPath: (O2PathDrawingMode) drawingMode {
    O2GState *gState = O2ContextCurrentGState(self);

    O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                   gState->_antialiasingQuality);

    /* Path construction is affected by the CTM, and the stroke pen is affected
     * by the CTM , this means path points and the stroke can be affected by
     * different transforms as the CTM can change during path construction and
     * before stroking. For example, creation of transformed shapes which are
     * drawn using an untransformed pen. The current tesselator expects
     * everything to be in user coordinates and it tesselates from there into
     * device space, but the path points are already in base coordinates. So,
     * path points are brought from base coordinates into the active coordinate
     * space using an inverted transform and then everything is tesselated using
     * the CTM into device space.  */

    O2AffineTransform userToSurfaceMatrix = gState->_deviceSpaceTransform;

    O2PathApplyTransform(_path,
                         O2AffineTransformInvert(gState->_userSpaceTransform));
    VGPath *vgPath = [[VGPath alloc] initWithKGPath: _path];

    if (drawingMode != kO2PathStroke) {
        O2AffineTransform surfaceToPaintMatrix =
                userToSurfaceMatrix; // context->m_pathUserToSurface *
                                     // context->m_fillPaintToUser;

        surfaceToPaintMatrix = O2AffineTransformInvert(surfaceToPaintMatrix);

        O2Paint *paint =
                paintFromColor(self, gState->_fillColor, surfaceToPaintMatrix);

        O2ContextSetupPaintAndBlendMode(self, paint, gState->_blendMode);
        O2PaintRelease(paint);

        VGPathFill(vgPath, userToSurfaceMatrix, self);

        VGFillRuleMask fillRule =
                (drawingMode == kO2PathFill || drawingMode == kO2PathFillStroke)
                        ? VG_NON_ZERO
                        : VG_EVEN_ODD;

        O2DContextClipAndFillEdges(self, fillRule);
    }

    if (drawingMode >= kO2PathStroke) {
        if (gState->_lineWidth > 0.0f) {
            O2AffineTransform surfaceToPaintMatrix =
                    userToSurfaceMatrix; // = context->m_pathUserToSurface *
                                         // context->m_strokePaintToUser;

            surfaceToPaintMatrix =
                    O2AffineTransformInvert(surfaceToPaintMatrix);

            O2Paint *paint = paintFromColor(self, gState->_strokeColor,
                                            surfaceToPaintMatrix);
            O2ContextSetupPaintAndBlendMode(self, paint, gState->_blendMode);
            O2PaintRelease(paint);

            O2RasterizerClear(self);

            VGPathStroke(vgPath, userToSurfaceMatrix, self,
                         gState->_dashLengths, gState->_dashLengthsCount,
                         gState->_dashPhase,
                         YES /* context->m_strokeDashPhaseReset ? YES : NO*/,
                         gState->_lineWidth, gState->_lineCap,
                         gState->_lineJoin, RI_MAX(gState->_miterLimit, 1.0f));

            O2DContextClipAndFillEdges(self, VG_NON_ZERO);
        }
    }

    O2ContextSetPaint(self, nil);
    [vgPath release];
    O2RasterizerClear(self);
    O2PathReset(_path);
}

- (void) showGlyphs: (const O2Glyph *) glyphs
           advances: (const O2Size *) advances
              count: (NSUInteger) count
{
#if 0
   O2FontRef font=O2ContextCurrentGState(self)->_font;
   int i;
   
   for(i=0;i<count;i++){
    O2Glyph    glyph=glyphs[i];
    O2ImageRef stencil;
   }
#endif
}

// A coordinate as a whole device pixel, clamped far beyond any surface so that
// a huge value cannot overflow; NO for NaN.
static BOOL copyBitsPixel(O2Float value, long *pixel) {
    if (isnan(value))
        return NO;
    *pixel = lround(MAX(MIN(value, (O2Float) 1e9), (O2Float) -1e9));
    return YES;
}

// What NSCopyBits and so -[NSView scrollRect:by:] ask for: the pixels of rect
// are copied to the rectangle of the same size at point, both in user space,
// by whole device pixels (the offset is rounded to them). What would land off
// the surface is left out; the clip is not consulted. The rectangle is taken in
// the context's current state: Darling keeps no graphics state under the number
// gState, so the documented source state cannot be looked up. A rotation other
// than a quarter turn moves the device bounding box of rect.
- (void) copyBitsInRect: (O2Rect) rect
                toPoint: (O2Point) point
                 gState: (int) gState
{
    O2Surface *surface = [_layerStack count] > 0
            ? O2LayerGetSurface([_layerStack lastObject])
            : _surface;
    O2AffineTransform toDevice = O2ContextGetUserSpaceToDeviceSpaceTransform(self);
    uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    size_t bitsPerPixel = O2ImageGetBitsPerPixel((O2ImageRef) surface);

    if (pixels == NULL || bitsPerPixel == 0 || bitsPerPixel % 8 != 0)
        return;

    size_t bytesPerPixel = bitsPerPixel / 8;
    size_t bytesPerRow = O2SurfaceGetBytesPerRow(surface);
    long width = (long) O2ImageGetWidth((O2ImageRef) surface);
    long height = (long) O2ImageGetHeight((O2ImageRef) surface);

    // the device box of rect, and the offset as the linear part of the
    // transform makes it
    O2Point corners[4] = {
        O2PointApplyAffineTransform(O2PointMake(O2RectGetMinX(rect), O2RectGetMinY(rect)), toDevice),
        O2PointApplyAffineTransform(O2PointMake(O2RectGetMaxX(rect), O2RectGetMinY(rect)), toDevice),
        O2PointApplyAffineTransform(O2PointMake(O2RectGetMaxX(rect), O2RectGetMaxY(rect)), toDevice),
        O2PointApplyAffineTransform(O2PointMake(O2RectGetMinX(rect), O2RectGetMaxY(rect)), toDevice),
    };
    O2Float minX = corners[0].x, maxX = corners[0].x;
    O2Float minY = corners[0].y, maxY = corners[0].y;
    for (int i = 1; i < 4; i++) {
        minX = fmin(minX, corners[i].x);
        maxX = fmax(maxX, corners[i].x);
        minY = fmin(minY, corners[i].y);
        maxY = fmax(maxY, corners[i].y);
    }
    O2Float offsetX = point.x - rect.origin.x, offsetY = point.y - rect.origin.y;
    long left, right, top, bottom, dx, dy;

    if (!copyBitsPixel(minX, &left) || !copyBitsPixel(maxX, &right) ||
        !copyBitsPixel(minY, &top) || !copyBitsPixel(maxY, &bottom) ||
        !copyBitsPixel(toDevice.a * offsetX + toDevice.c * offsetY, &dx) ||
        !copyBitsPixel(toDevice.b * offsetX + toDevice.d * offsetY, &dy))
        return;

    if (dx == 0 && dy == 0)
        return;

    // the pixels of the box that exist and land on the surface
    long fromLeft = MAX(MAX(left, 0L), -dx), fromRight = MIN(MIN(right, width), width - dx);
    long fromTop = MAX(MAX(top, 0L), -dy), fromBottom = MIN(MIN(bottom, height), height - dy);

    if (fromLeft >= fromRight || fromTop >= fromBottom)
        return;

    // rows are copied in the order that never reads one already written
    for (long i = 0; i < fromBottom - fromTop; i++) {
        long row = dy > 0 ? fromBottom - 1 - i : fromTop + i;

        memmove(pixels + (row + dy) * bytesPerRow + (fromLeft + dx) * bytesPerPixel,
                pixels + row * bytesPerRow + fromLeft * bytesPerPixel,
                (fromRight - fromLeft) * bytesPerPixel);
    }
}

- (void) drawShading: (O2Shading *) shading {
    O2GState *gState = O2ContextCurrentGState(self);
    O2ClipState *clipState = O2GStateClipState(gState);
    O2Paint *paint;

    O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                   gState->_antialiasingQuality);

    if ([shading isConic]) {
        paint = [[O2Paint_conicGradient alloc]
                initWithShading: shading
                deviceTransform: gState->_deviceSpaceTransform];
        // a colour space the ramp cannot turn into colours draws nothing
        if (paint == nil)
            return;
    } else if ([shading isAxial])
        paint = [[O2Paint_axialGradient alloc]
                initWithShading: shading
                deviceTransform: gState->_deviceSpaceTransform];
    else
        paint = [[O2Paint_radialGradient alloc]
                initWithShading: shading
                deviceTransform: gState->_deviceSpaceTransform];

    O2ContextSetupPaintAndBlendMode(self, paint, gState->_blendMode);
    O2PaintRelease(paint);

    switch (O2ClipStateGetType(clipState)) {

    case O2ClipStateTypeOnePath:
    case O2ClipStateTypeOneRectOnePath:;
        VGPath *vgPath =
                [[VGPath alloc] initWithKGPath: O2ClipStateOnePath(clipState)];
        VGPathFill(vgPath, O2AffineTransformIdentity, self);
        // the edges are copies, the path is not needed past the fill
        [vgPath release];
        break;

    default:
    case O2ClipStateTypeNone:
    case O2ClipStateTypeOneRect:
    case O2ClipStateTypeOneRectManyPaths:
    case O2ClipStateTypeManyPaths:
    case O2ClipStateTypeManyPathsAndMasks:
        O2DContextAddEdge(self, O2PointMake(0, 0),
                          O2PointMake(0, O2ImageGetHeight(_surface)));
        O2DContextAddEdge(self, O2PointMake(O2ImageGetWidth(_surface), 0),
                          O2PointMake(O2ImageGetWidth(_surface),
                                      O2ImageGetHeight(_surface)));
        break;
    }

    O2DContextClipAndFillEdges(self, VG_NON_ZERO);
    O2ContextSetPaint(self, nil);
    O2RasterizerClear(self);
}

static inline O2AffineTransform
createImageToSurfaceTransform(O2ImageRef image, O2Rect rect,
                              O2AffineTransform deviceTransform)
{
    O2AffineTransform result =
            O2AffineTransformMakeTranslation(rect.origin.x, rect.origin.y);

    result = O2AffineTransformScale(
            result, rect.size.width / (O2Float) O2ImageGetWidth(image),
            rect.size.height / (O2Float) O2ImageGetHeight(image));
    result = O2AffineTransformConcat(result, deviceTransform);

    O2AffineTransform i2u =
            O2AffineTransformMakeTranslation(0, O2ImageGetHeight(image));
    i2u = O2AffineTransformScale(i2u, 1, -1);

    result = O2AffineTransformConcat(i2u, result);

    return result;
}

/* An image drawn pixel for pixel (moved by whole pixels, perhaps flipped)
   and clipped to a rectangle, as a GL frame or a window's contents are: its
   rows are copied, not resampled and blended a pixel at a time. Images in
   the surface's order (BGRA) are copied as they are, RGBA ones swapped. */
ONYX2D_STATIC BOOL drawImagePixelForPixel(O2Context_builtin *self,
                                          O2Image *image,
                                          O2AffineTransform imageToSurface)
{
    O2GState *gState = O2ContextCurrentGState(self);
    O2Surface *surface = self->_surface;
    const O2Float epsilon = 1.0e-4;

    if (O2ImageGetMask(image) != NULL || O2ImageIsMask(image) ||
        O2ImageGetDecode(image) != NULL || self->_clipMask != nil ||
        [self->_layerStack count] > 0 || gState->_alpha != 1 ||
        (gState->_blendMode != kO2BlendModeNormal &&
         gState->_blendMode != kO2BlendModeCopy))
        return NO;
    if (fabs(imageToSurface.a - 1) > epsilon || imageToSurface.b != 0 ||
        imageToSurface.c != 0 || fabs(fabs(imageToSurface.d) - 1) > epsilon)
        return NO;
    int tx = (int) lround(imageToSurface.tx);
    int ty = (int) lround(imageToSurface.ty);
    if (fabs(imageToSurface.tx - tx) > epsilon ||
        fabs(imageToSurface.ty - ty) > epsilon)
        return NO;
    BOOL flipped = imageToSurface.d < 0;

    O2BitmapInfo surfaceInfo = O2ImageGetBitmapInfo(surface);
    O2BitmapInfo surfaceAlpha = surfaceInfo & kO2BitmapAlphaInfoMask;
    if (O2ImageGetBitsPerPixel(surface) != 32 ||
        (surfaceInfo & kO2BitmapByteOrderMask) != kO2BitmapByteOrder32Little ||
        (surfaceAlpha != kO2ImageAlphaPremultipliedFirst &&
         surfaceAlpha != kO2ImageAlphaNoneSkipFirst))
        return NO;

    O2BitmapInfo info = O2ImageGetBitmapInfo(image);
    O2BitmapInfo alpha = info & kO2BitmapAlphaInfoMask;
    O2BitmapInfo order = info & kO2BitmapByteOrderMask;
    BOOL swap, opaque;
    if (O2ImageGetBitsPerComponent(image) != 8 ||
        O2ImageGetBitsPerPixel(image) != 32 ||
        O2ColorSpaceGetModel(O2ImageGetColorSpace(image)) !=
                kO2ColorSpaceModelRGB)
        return NO;
    if (order == kO2BitmapByteOrder32Little &&
        (alpha == kO2ImageAlphaPremultipliedFirst ||
         alpha == kO2ImageAlphaNoneSkipFirst)) {
        swap = NO;
        opaque = alpha == kO2ImageAlphaNoneSkipFirst;
    } else if ((order == kO2BitmapByteOrderDefault ||
                order == kO2BitmapByteOrder32Big) &&
               (alpha == kO2ImageAlphaPremultipliedLast ||
                alpha == kO2ImageAlphaNoneSkipLast)) {
        swap = YES;
        opaque = alpha == kO2ImageAlphaNoneSkipLast;
    } else
        return NO;

    int width = (int) O2ImageGetWidth(image);
    int height = (int) O2ImageGetHeight(image);
    size_t bytesPerRow = O2ImageGetBytesPerRow(image);
    const uint8_t *bytes = [image directBytes];
    if (bytes == NULL || [[image directData] length] < bytesPerRow * height)
        return NO;

    /* The image's pixels in the surface, within the clip. */
    int top = flipped ? ty - height : ty;
    int x0 = MAX(tx, MAX(self->_vpx, 0));
    int x1 = MIN(tx + width,
                 MIN(self->_vpx + self->_vpwidth, (int) O2ImageGetWidth(surface)));
    int y0 = MAX(top, MAX(self->_vpy, 0));
    int y1 = MIN(top + height, MIN(self->_vpy + self->_vpheight,
                                   (int) O2ImageGetHeight(surface)));
    if (x0 >= x1 || y0 >= y1)
        return YES;

    uint8_t *pixels = O2SurfaceGetPixelBytes(surface);
    size_t surfaceBytesPerRow = O2ImageGetBytesPerRow(surface);
    BOOL blend = !opaque && gState->_blendMode == kO2BlendModeNormal;
    int count = x1 - x0;

    for (int y = y0; y < y1; y++) {
        int row = flipped ? ty - y - 1 : y - ty;
        const uint32_t *from =
                (const uint32_t *) (bytes + row * bytesPerRow) + (x0 - tx);
        uint32_t *to = (uint32_t *) (pixels + y * surfaceBytesPerRow) + x0;

        /* One plain loop per case, so the compiler can vectorize them. */
        if (!swap && !opaque && !blend)
            memcpy(to, from, count * 4);
        else if (!swap && opaque)
            for (int i = 0; i < count; i++)
                to[i] = from[i] | 0xFF000000;
        else if (opaque)
            for (int i = 0; i < count; i++) {
                uint32_t pixel = from[i];
                to[i] = (pixel & 0x0000FF00) | ((pixel & 0xFF) << 16) |
                        ((pixel >> 16) & 0xFF) | 0xFF000000;
            }
        else if (!blend)
            for (int i = 0; i < count; i++) {
                uint32_t pixel = from[i];
                to[i] = (pixel & 0xFF00FF00) | ((pixel & 0xFF) << 16) |
                        ((pixel >> 16) & 0xFF);
            }
        else
            for (int i = 0; i < count; i++) {
                uint32_t pixel = from[i];
                if (swap)
                    pixel = (pixel & 0xFF00FF00) | ((pixel & 0xFF) << 16) |
                            ((pixel >> 16) & 0xFF);
                uint32_t a = pixel >> 24;
                if (a == 255) {
                    to[i] = pixel;
                    continue;
                }
                if (pixel == 0)
                    continue;
                /* Premultiplied source over: each channel s + d * (1 - a). */
                uint32_t under = to[i], keep = 255 - a;
                uint32_t rb = (under & 0x00FF00FF) * keep + 0x00800080;
                rb = ((rb + ((rb >> 8) & 0x00FF00FF)) >> 8) & 0x00FF00FF;
                uint32_t ag = ((under >> 8) & 0x00FF00FF) * keep + 0x00800080;
                ag = (ag + ((ag >> 8) & 0x00FF00FF)) & 0xFF00FF00;
                to[i] = pixel + rb + ag;
            }
    }
    return YES;
}

// The coverage that a sample of a mask image gives to the pixels it covers:
// the alpha of an image that has one, the value of a gray image, and the
// inverse of an image mask (whose sample 0 marks the area to paint).
static uint8_t O2ClipMaskCoverage(O2Image *image, O2argb8u pixel) {
    if (O2ImageIsMask(image))
        return 255 - pixel.r;

    switch (O2ImageGetAlphaInfo(image)) {
    case kO2ImageAlphaPremultipliedLast:
    case kO2ImageAlphaPremultipliedFirst:
    case kO2ImageAlphaLast:
    case kO2ImageAlphaFirst:
    case kO2ImageAlphaOnly:
        return pixel.a;
    default:
        return (pixel.r + pixel.g + pixel.b) / 3;
    }
}

// Clipping to a mask keeps only the area of the mask image, weighted by its
// coverage, so the result is kept per device pixel and multiplied into what
// earlier masks left. Where a pixel of the surface falls outside the image
// nothing is painted.
static void O2ContextDeviceClipToMask_builtin(O2Context_builtin *self,
                                              O2ClipPhase *phase)
{
    O2Image *image = O2ClipPhaseObject(phase);
    size_t imageWidth = O2ImageGetWidth(image);
    size_t imageHeight = O2ImageGetHeight(image);
    size_t width = O2ImageGetWidth(self->_surface);
    size_t height = O2ImageGetHeight(self->_surface);
    O2Rect rect = O2ClipPhaseRect(phase);

    if (width == 0 || height == 0)
        return;

    if (self->_clipMask == nil) {
        O2ColorSpaceRef gray = O2ColorSpaceCreateDeviceGray();

        self->_clipMask = [[O2Surface alloc] initWithBytes: NULL
                                                     width: width
                                                    height: height
                                          bitsPerComponent: 8
                                               bytesPerRow: 0
                                                colorSpace: gray
                                                bitmapInfo: kO2ImageAlphaNone];
        O2ColorSpaceRelease(gray);
        if (self->_clipMask == nil)
            return;
        memset(O2SurfaceGetPixelBytes(self->_clipMask), 0xFF,
               O2SurfaceGetBytesPerRow(self->_clipMask) * height);
    }

    uint8_t *bytes = O2SurfaceGetPixelBytes(self->_clipMask);
    size_t bytesPerRow = O2SurfaceGetBytesPerRow(self->_clipMask);
    O2AffineTransform imageToSurface = createImageToSurfaceTransform(
            image, rect, O2ClipPhaseTransform(phase));
    O2AffineTransform surfaceToImage = O2AffineTransformInvert(imageToSurface);

    BOOL degenerate = imageWidth == 0 || imageHeight == 0 ||
                      rect.size.width == 0 || rect.size.height == 0;

    // The area of the image on the surface, in whole pixels.
    O2Point corners[4] = {
        O2PointMake(0, 0), O2PointMake(imageWidth, 0),
        O2PointMake(imageWidth, imageHeight), O2PointMake(0, imageHeight)};
    O2Float minX = 0, maxX = 0, minY = 0, maxY = 0;
    for (int i = 0; i < 4; i++) {
        O2Point p = O2PointApplyAffineTransform(corners[i], imageToSurface);
        if (i == 0 || p.x < minX)
            minX = p.x;
        if (i == 0 || p.x > maxX)
            maxX = p.x;
        if (i == 0 || p.y < minY)
            minY = p.y;
        if (i == 0 || p.y > maxY)
            maxY = p.y;
    }
    long x0 = degenerate ? 0 : MAX(0, (long) floor(minX));
    long x1 = degenerate ? 0 : MIN((long) width, (long) ceil(maxX));
    long y0 = degenerate ? 0 : MAX(0, (long) floor(minY));
    long y1 = degenerate ? 0 : MIN((long) height, (long) ceil(maxY));

    O2argb8u *row = malloc(imageWidth * sizeof(O2argb8u));
    long rowIndex = -1;

    for (long y = 0; y < (long) height; y++) {
        uint8_t *line = bytes + y * bytesPerRow;

        if (y < y0 || y >= y1) {
            memset(line, 0, width);
            continue;
        }
        for (long x = 0; x < (long) width; x++) {
            if (x < x0 || x >= x1) {
                line[x] = 0;
                continue;
            }

            O2Point p = O2PointApplyAffineTransform(
                    O2PointMake(x + 0.5, y + 0.5), surfaceToImage);
            long u = (long) floor(p.x);
            long v = (long) floor(p.y);

            if (u < 0 || v < 0 || u >= (long) imageWidth ||
                v >= (long) imageHeight)
            {
                line[x] = 0;
                continue;
            }

            if (v != rowIndex) {
                O2argb8u *direct =
                        O2Image_read_argb8u(image, 0, (int) v, row,
                                            (int) imageWidth);
                if (direct != NULL)
                    memcpy(row, direct, imageWidth * sizeof(O2argb8u));
                rowIndex = v;
            }
            line[x] = (line[x] * (unsigned) O2ClipMaskCoverage(image, row[u]) +
                       127) / 255;
        }
    }
    free(row);
}

ONYX2D_STATIC void releaseConvertedBytes(void *info, const void *data, size_t size) {
    free(info);
}

/* The colour profile an image or surface is interpreted in: its own for the named spaces, sRGB for an unnamed RGB
   (device) space. Spaces without a profile (device gray, CMYK, indexed ...) are not converted. */
ONYX2D_STATIC BOOL profileForImageSpace(O2ColorSpaceRef space,
                                        CFStringRef *name,
                                        O2ColorProfile *profile)
{
    *name = O2ColorSpaceGetName(space);
    if (*name != NULL)
        return O2ColorSpaceGetColorProfile(space, profile);
    if (O2ColorSpaceGetModel(space) != kO2ColorSpaceModelRGB)
        return NO;
    *name = CFSTR("kCGColorSpaceSRGB");
    return O2ColorProfileForName("kCGColorSpaceSRGB", profile);
}

/* An image drawn into a surface of another profiled space is converted to the surface's space first, as a colour
   is (see paintFromColor). Returns the converted copy, or NULL when the image can be drawn as it is. The copy is
   8-bit premultiplied RGBA; for a gray surface every channel holds the converted gray value. */
ONYX2D_STATIC O2ImageRef createImageInSurfaceSpace(O2Context_builtin *self,
                                                   O2ImageRef image)
{
    O2ColorSpaceRef surfaceSpace = O2ImageGetColorSpace(self->_surface);
    O2ColorSpaceRef imageSpace = O2ImageGetColorSpace(image);
    CFStringRef surfaceName, imageName;
    O2ColorProfile surfaceProfile, imageProfile;

    if (imageSpace == NULL || surfaceSpace == NULL || O2ImageGetMask(image) != NULL)
        return NULL;
    if (!profileForImageSpace(surfaceSpace, &surfaceName, &surfaceProfile) ||
        !profileForImageSpace(imageSpace, &imageName, &imageProfile) ||
        CFEqual(surfaceName, imageName))
        return NULL;

    size_t width = O2ImageGetWidth(image), height = O2ImageGetHeight(image);
    if (width == 0 || height == 0 || width > SIZE_MAX / 4 / height)
        return NULL;

    uint8_t *bytes = malloc(width * height * 4);
    O2argb32f *span = malloc(width * sizeof(O2argb32f));
    if (bytes == NULL || span == NULL) {
        free(bytes);
        free(span);
        return NULL;
    }

    for (size_t y = 0; y < height; y++) {
        O2argb32f *row = O2Image_read_argb32f(image, 0, (int) y, span, (int) width);
        if (row == NULL)
            row = span;
        uint8_t *out = bytes + y * width * 4;

        for (size_t x = 0; x < width; x++, out += 4) {
            O2argb32f pixel = row[x];
            double in[3] = {0, 0, 0}, result[3] = {0, 0, 0};

            if (pixel.a > 0) {
                in[0] = pixel.r / pixel.a;
                in[1] = imageProfile.isGray ? 0 : pixel.g / pixel.a;
                in[2] = imageProfile.isGray ? 0 : pixel.b / pixel.a;
                O2ColorProfileConvert(&imageProfile, &surfaceProfile, in, result);
            }
            if (surfaceProfile.isGray)
                result[1] = result[2] = result[0];
            for (int i = 0; i < 3; i++)
                out[i] = O2ByteFromFloat(RI_CLAMP(result[i], 0.0, 1.0) * pixel.a);
            out[3] = O2ByteFromFloat(pixel.a);
        }
    }
    free(span);

    O2ColorSpaceRef resultSpace = surfaceProfile.isGray ? O2ColorSpaceCreateDeviceRGB()
                                                        : O2ColorSpaceRetain(surfaceSpace);
    O2DataProviderRef provider = O2DataProviderCreateWithData(bytes, bytes, width * height * 4, releaseConvertedBytes);
    O2ImageRef converted = O2ImageCreate(width, height, 8, 32, width * 4, resultSpace, kO2ImageAlphaPremultipliedLast,
                                         provider, NULL, O2ImageGetShouldInterpolate(image),
                                         kO2RenderingIntentDefault);
    O2DataProviderRelease(provider);
    O2ColorSpaceRelease(resultSpace);
    return converted;
}

- (void) drawImage: (O2Image *) image inRect: (O2Rect) rect {
    O2ImageRef converted = createImageInSurfaceSpace(self, image);

    if (converted != NULL) {
        [self drawImageAsIs: converted inRect: rect];
        O2ImageRelease(converted);
        return;
    }
    [self drawImageAsIs: image inRect: rect];
}

- (void) drawImageAsIs: (O2Image *) image inRect: (O2Rect) rect {
    O2GState *gState = O2ContextCurrentGState(self);
    O2ImageRef softMask = O2ImageGetMask(image);

    O2AffineTransform imageToSurface = createImageToSurfaceTransform(
            image, rect, gState->_deviceSpaceTransform);
    if (drawImagePixelForPixel(self, image, imageToSurface))
        return;
    O2AffineTransform maskToSurface;

    if (softMask == NULL)
        maskToSurface = O2AffineTransformIdentity;
    else
        maskToSurface = createImageToSurfaceTransform(
                softMask, rect, gState->_deviceSpaceTransform);

    // transform image corners into the surface space
    O2Point p0 = O2PointMake(0, 0);
    O2Point p1 = O2PointMake(0, (O2Float) O2ImageGetHeight(image));
    O2Point p2 = O2PointMake((O2Float) O2ImageGetWidth(image),
                             (O2Float) O2ImageGetHeight(image));
    O2Point p3 = O2PointMake((O2Float) O2ImageGetWidth(image), 0);
    p0 = O2PointApplyAffineTransform(p0, imageToSurface);
    p1 = O2PointApplyAffineTransform(p1, imageToSurface);
    p2 = O2PointApplyAffineTransform(p2, imageToSurface);
    p3 = O2PointApplyAffineTransform(p3, imageToSurface);

    O2RasterizerSetShouldAntialias(self, gState->_shouldAntialias,
                                   gState->_antialiasingQuality);

    // FIX, adjustable, do we even need this ??
    O2AffineTransform fillPaintToUser = O2AffineTransformIdentity;

    O2AffineTransform surfaceToPaintMatrix =
            O2AffineTransformConcat(imageToSurface, fillPaintToUser);

    surfaceToPaintMatrix = O2AffineTransformInvert(surfaceToPaintMatrix);

    O2Paint *paint =
            paintFromColor(self, gState->_fillColor, surfaceToPaintMatrix);
    O2InterpolationQuality iq;
    if (gState->_interpolationQuality == kO2InterpolationDefault)
        iq = kO2InterpolationLow;
    else
        iq = gState->_interpolationQuality;

    O2Paint *imagePaint = [[O2Paint_image allocWithZone: NULL]
                   initWithImage: image
                            mask: softMask
                            mode: VG_DRAW_IMAGE_NORMAL
                           paint: paint
            interpolationQuality: iq
                  surfaceToImage: O2AffineTransformInvert(imageToSurface)
                   surfaceToMask: O2AffineTransformInvert(maskToSurface)];

    if ([imagePaint isKindOfClass: [O2Paint_image class]]) {
        [(O2Paint_image *)imagePaint setAlpha: gState->_alpha];
    }

    O2ContextSetupPaintAndBlendMode(self, imagePaint, gState->_blendMode);

    O2PaintRelease(paint);
    O2PaintRelease(imagePaint);

    O2DContextAddEdge(self, p0, p1);
    O2DContextAddEdge(self, p1, p2);
    O2DContextAddEdge(self, p2, p3);
    O2DContextAddEdge(self, p3, p0);
    O2DContextClipAndFillEdges(self, VG_EVEN_ODD);

    O2ContextSetPaint(self, nil);

    O2RasterizerClear(self);
}

- (void) drawLayer: (O2LayerRef) layer inRect: (O2Rect) rect {
    O2ImageRef image = O2LayerGetSurface(layer);

    [self drawImage: image inRect: rect];
}

void O2RasterizerSetViewport(O2Context_builtin *self, int x, int y, int width,
                             int height)
{
    RI_ASSERT(vpwidth >= 0 && vpheight >= 0);
    self->_vpx = x;
    self->_vpy = y;
    self->_vpwidth = width;
    self->_vpheight = height;
}

void O2RasterizerClear(O2Context_builtin *self) {
    int i;
    for (i = 0; i < self->_edgeCount; i++)
        NSZoneFree(NULL, self->_edges[i]);

    self->_edgeCount = 0;
}

void O2DContextAddEdge(O2Context_builtin *self, const O2Point v0,
                       const O2Point v1)
{

    if (v0.y == v1.y)
        return; // skip horizontal edges (they don't affect rasterization since
                // we scan horizontally)

    if (v0.y < self->_vpy && v1.y < self->_vpy) // ignore below miny
        return;

    int MaxY = self->_vpy + self->_vpheight;

    if (v0.y >= MaxY && v1.y >= MaxY) // ignore above maxy
        return;

    Edge *edge = NSZoneMalloc(NULL, sizeof(Edge));
    if (self->_edgeCount + 1 >= self->_edgeCapacity) {
        self->_edgeCapacity *= 2;
        self->_edges = NSZoneRealloc(NULL, self->_edges,
                                     self->_edgeCapacity * sizeof(Edge *));
        self->_sortCache =
                NSZoneRealloc(NULL, self->_sortCache,
                              (self->_edgeCapacity / 2 + 1) * sizeof(Edge *));
    }
    self->_edges[self->_edgeCount] = edge;
    self->_edgeCount++;

    if (v0.y < v1.y) { // edge is going upward
        edge->v0 = v0;
        edge->v1 = v1;
        edge->direction = 1;
    } else { // edge is going downward
        edge->v0 = v1;
        edge->v1 = v0;
        edge->direction = -1;
    }

    edge->next = NULL;
}

// Returns a radical inverse of a given integer for Hammersley point set.
ONYX2D_STATIC double radicalInverseBase2(unsigned int i) {
    if (i == 0)
        return 0.0;
    double p = 0.0;
    double f = 0.5f;
    double ff = f;
    unsigned int j;
    for (j = 0; j < 32; j++) {
        if (i & (1 << j))
            p += f;
        f *= ff;
    }
    return p;
}

void O2RasterizerSetShouldAntialias(O2Context_builtin *self, BOOL antialias,
                                    int quality)
{
    quality = RI_INT_CLAMP(quality, 1, MAX_SAMPLES);

    self->alias = (!antialias || quality == 1) ? YES : NO;

#if 0
   {
    self->numSamples=1;
			self->samplesX[0] = 0.5;
			self->samplesInitialY = 0.5;
			self->samplesDeltaY = 0;
			self->samplesWeight = MAX_SAMPLES;
   }
   else
#endif

    if (self->numSamples == quality)
        return;

    int shift;
    int numberOfSamples = 1;

    for (shift = 0; numberOfSamples < quality; shift++)
        numberOfSamples <<= 1;

    // quality is a hint and may not match the number of samples, recheck for
    // optimization
    if (self->numSamples == numberOfSamples)
        return;

    self->sampleSizeShift = shift;
    self->numSamples = numberOfSamples;

    self->samplesInitialY = ((O2Float)(0.5f)) / (O2Float) numberOfSamples;
    self->samplesDeltaY = ((O2Float)(1.0f)) / (O2Float) numberOfSamples;

    int i;
    for (i = 0; i < numberOfSamples; i++) {
        self->samplesX[i] = (O2Float) radicalInverseBase2(i);
        self->samplesWeight = MAX_SAMPLES / numberOfSamples;
    }
}

ONYX2D_STATIC void O2ApplyCoverageAndMaskToSpan_largb32f_PRE(O2argb32f *dst,
                                                             int icoverage,
                                                             O2Float *mask,
                                                             O2argb32f *src,
                                                             int length)
{
    int i;

    for (i = 0; i < length; i++) {
        O2argb32f r = src[i];
        O2argb32f d = dst[i];
        O2Float coverage = zeroToOneFromCoverage(icoverage);
        O2Float cov = mask[i] * coverage;

        dst[i] = O2argb32fAdd(O2argb32fMultiplyByFloat(r, cov),
                              O2argb32fMultiplyByFloat(d, (1.0f - cov)));
    }
}

ONYX2D_STATIC void O2ApplyCoverageToSpan_largb32f_PRE(O2argb32f *dst,
                                                      int icoverage,
                                                      O2argb32f *src,
                                                      int length)
{
    int i;
    O2Float coverage = zeroToOneFromCoverage(icoverage);

    for (i = 0; i < length; i++) {
        O2argb32f r = src[i];
        O2argb32f d = dst[i];

        dst[i] = O2argb32fAdd(O2argb32fMultiplyByFloat(r, coverage),
                              O2argb32fMultiplyByFloat(d, (1.0f - coverage)));
    }
}

/* Paint functions can selectively paint or not paint at all, e.g. gradients
 * with extend turned off, they do this by returning a negative chunk for a
 * pixels which aren't generated and positive chunk for pixels that are. We need
 * to make sure we cover the entire span so we loop until the span is complete.
 */
ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Normal(
        O2Surface *surface, O2Surface *mask, O2Paint *paint, int x, int y,
        int coverage, int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            O2argb8u_sover_by_coverage(src, dst, coverage, chunk);
            // FIXME: doesnt handle mask if present

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }
        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void O2RasterizeWriteCoverageSpan8888_Copy(
        O2Surface *surface, O2Surface *mask, O2Paint *paint, int x, int y,
        int coverage, int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            O2argb8u_copy_by_coverage(src, dst, coverage, chunk);
            // FIXME: doesnt handle mask if present

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }

        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void
O2RasterizeWriteCoverageSpan8888(O2Surface *surface, O2Surface *mask,
                                 O2Paint *paint, int x, int y, int coverage,
                                 int length, O2BlendSpan_argb8u blendFunction)
{
    O2argb8u *dst = __builtin_alloca(length * sizeof(O2argb8u));
    O2argb8u *direct = surface->_read_argb8u(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb8u *src = __builtin_alloca(length * sizeof(O2argb8u));

    while (YES) {
        int chunk = O2PaintReadSpan_argb8u_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            blendFunction(src, dst, chunk);

            // apply masking
            if (mask == NULL)
                O2ApplyCoverageToSpan_largb8u_PRE(dst, coverage, src, chunk);
            else {
                uint8_t maskSpan[chunk];

                O2Image_read_a8u(mask, x, y, maskSpan, chunk);
                O2ApplyCoverageAndMaskToSpan_largb8u_PRE(dst, coverage,
                                                         maskSpan, src, chunk);
            }

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_argb8u_PRE(surface, x, y, dst, chunk);
            }
        }

        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void
O2RasterizeWriteCoverageSpanffff(O2Surface *surface, O2Surface *mask,
                                 O2Paint *paint, int x, int y, int coverage,
                                 int length, O2BlendSpan_argb32f blendFunction)
{
    O2argb32f *dst = __builtin_alloca(length * sizeof(O2argb32f));
    O2argb32f *direct = O2Image_read_argb32f(surface, x, y, dst, length);

    if (direct != NULL)
        dst = direct;

    O2argb32f *src = __builtin_alloca(length * sizeof(O2argb32f));

    while (YES) {
        int chunk = O2PaintReadSpan_largb32f_PRE(paint, x, y, src, length);

        if (chunk < 0) // skip
            chunk = -chunk;
        else {
            blendFunction(src, dst, chunk);

            // apply masking
            if (mask == NULL)
                O2ApplyCoverageToSpan_largb32f_PRE(dst, coverage, src, chunk);
            else {
                O2Float maskSpan[length];

                O2ImageReadSpan_Af_MASK(mask, x, y, maskSpan, chunk);
                O2ApplyCoverageAndMaskToSpan_largb32f_PRE(dst, coverage,
                                                          maskSpan, src, chunk);
            }

            if (direct == NULL) {
                // write result to the destination surface
                O2SurfaceWriteSpan_largb32f_PRE(surface, x, y, dst, chunk);
            }
        }

        length -= chunk;
        if (length == 0)
            break;

        x += chunk;
        src += chunk;
        dst += chunk;
    }
}

ONYX2D_STATIC_INLINE void sortEdgesByMinY(Edge **edges, int count, Edge **B) {
    int h, i, j, k, l, m, n = count;
    Edge *A;

    for (h = 1; h < n; h += h) {
        for (m = n - 1 - h; m >= 0; m -= h + h) {
            l = m - h + 1;
            if (l < 0)
                l = 0;

            for (i = 0, j = l; j <= m; i++, j++)
                B[i] = edges[j];

            for (i = 0, k = l; k < j && j <= m + h; k++) {
                A = edges[j];
                if (A->v0.y > B[i]->v0.y)
                    edges[k] = B[i++];
                else {
                    edges[k] = A;
                    j++;
                }
            }

            while (k < j)
                edges[k++] = B[i++];
        }
    }
}

ONYX2D_STATIC_INLINE void initEdgeForAET(O2Context_builtin *self, Edge *edge,
                                         int scany)
{
    // compute edge min and max x-coordinates for this scanline

    O2Point vd = Vector2Subtract(edge->v1, edge->v0);
    O2Float wl = 1.0f / vd.y;
    edge->vdxwl = vd.x * wl;

    if (edge->v0.x < edge->v1.x) {
        edge->isVertical = 0;
        edge->bminx = edge->v0.x;
        edge->bmaxx = edge->v1.x;
    } else {
        edge->isVertical = (edge->v0.x == edge->v1.x) ? 1 : 0;
        edge->bminx = edge->v1.x;
        edge->bmaxx = edge->v0.x;
    }

    edge->sxPre = edge->v0.x - (edge->v0.y * edge->vdxwl);
    edge->exPre = edge->sxPre;
    edge->sxPre += (scany - 1) * edge->vdxwl;
    edge->exPre += (scany + 1) * edge->vdxwl;

    O2Float autosx = RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
    O2Float autoex = RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx);
    O2Float minx = RI_MIN(autosx, autoex);

    edge->minx = MAX(self->_vpx, minx);
    edge->samples = NSZoneMalloc(NULL, sizeof(O2Float) * self->numSamples);

    O2Float *pre = edge->samples;
    int i, numberOfSamples = self->numSamples;
    O2Float sampleY = self->samplesInitialY;
    O2Float deltaY = self->samplesDeltaY;
    O2Float *samplesX = self->samplesX;

    O2Float normalX = edge->v0.y - edge->v1.y;
    O2Float normalY = edge->v0.x - edge->v1.x;
    O2Float min = 0, max = 0;

    for (i = 0; i < numberOfSamples; sampleY += deltaY, samplesX++, i++) {
        O2Float value = sampleY * normalY - *samplesX * normalX;

        *pre++ = value;

        if (i == 0)
            min = max = value;
        else {
            min = MIN(min, value);
            max = MAX(max, value);
        }
    }
    edge->minSample = min;
    edge->maxSample = max;
}

ONYX2D_STATIC_INLINE void incrementEdgeForAET(Edge *edge, int vpx) {
    edge->sxPre += edge->vdxwl;
    edge->exPre += edge->vdxwl;

    O2Float autosx = RI_CLAMP(edge->sxPre, edge->bminx, edge->bmaxx);
    O2Float autoex = RI_CLAMP(edge->exPre, edge->bminx, edge->bmaxx);
    O2Float minx = RI_MIN(autosx, autoex);

    edge->minx = MAX(vpx, minx);
}

ONYX2D_STATIC_INLINE void removeEdgeFromAET(Edge *edge) {
    NSZoneFree(NULL, edge->samples);
}

typedef struct CoverageNode {
    struct CoverageNode *next;
    int scanx;
    int coverage;
    int length;
} CoverageNode;

void O2DContextFillEdgesOnSurface(O2Context_builtin *self, O2Surface *surface,
                                  O2Image *mask, O2Paint *paint,
                                  int fillRuleMask)
{
    int edgeCount = self->_edgeCount;
    Edge **edges = self->_edges;

    CoverageNode *freeCoverage = NULL;
    CoverageNode *currentCoverage = NULL;

    // The shortcuts for the usual blend modes paint a whole span with one
    // coverage; with a mask clipping the context the span is blended pixel by
    // pixel.
    void (*writeCoverage)() = self->_writeCoverageFunction;
    void (*blendFunction)() = self->_blendFunction;
    if (mask != nil && self->_writeCoverage_argb8u_PRE != NULL &&
        self->_blend_argb8u_PRE != NULL)
    {
        writeCoverage = O2RasterizeWriteCoverageSpan8888;
        blendFunction = self->_blend_argb8u_PRE;
    }

    sortEdgesByMinY(edges, edgeCount, self->_sortCache);

    int ylimit = self->_vpy + self->_vpheight;
    int xlimit = self->_vpx + self->_vpwidth;
    int firstY = self->_vpy;

    // Only the rows and columns the edges reach can change. Scanning the whole
    // viewport made the time to fill a small path grow with the size of the
    // surface: the edges that cover part of a row add their winding to every
    // pixel to the right of them up to the viewport's edge.
    if (edgeCount > 0) {
        O2Float minY = edges[0]->v0.y, maxY = edges[0]->v1.y, maxX = -INFINITY;
        int i;

        for (i = 0; i < edgeCount; i++) {
            minY = MIN(minY, MIN(edges[i]->v0.y, edges[i]->v1.y));
            maxY = MAX(maxY, MAX(edges[i]->v0.y, edges[i]->v1.y));
            maxX = MAX(maxX, MAX(edges[i]->v0.x, edges[i]->v1.x));
        }
        if (minY > firstY)
            firstY = MAX(self->_vpy, (int) floor(minY));
        if (maxY + 1 < ylimit)
            ylimit = MAX(firstY, (int) ceil(maxY) + 1);
        // one pixel more than the rightmost vertex for the pixel it lies in
        if (maxX + 2 < xlimit)
            xlimit = MAX(self->_vpx, (int) ceil(maxX) + 2);
    }

    Edge *activeRoot = NULL;
    int nextAvailableEdge = 0;

    int scany;

    int *winding = self->_winding;
    int numberOfSamples = self->numSamples;
    int shiftNumberOfSamples = self->sampleSizeShift;
    int totalActiveEdges = 0;
    int totalActiveVerticalEdgesFullCoverage = 0;

    for (scany = firstY; scany < ylimit; scany++) {
        Edge *edge, *previous = NULL;
        int unchangedActiveEdges = 1;

        // increment and remove edges out of range
        for (edge = activeRoot; edge != NULL; edge = edge->next) {
            if (edge->v1.y > scany) {
                incrementEdgeForAET(edge, self->_vpx);
                previous = edge;

                if (edge->isVertical) {
                    if (edge->v0.y < scany && edge->v1.y >= (scany + 1)) {
                        if (!edge->isFullCoverage) {
                            edge->isFullCoverage = 1;
                            unchangedActiveEdges = 0;
                            totalActiveVerticalEdgesFullCoverage++;
                        }
                    } else {
                        if (edge->isFullCoverage) {
                            edge->isFullCoverage = 0;
                            unchangedActiveEdges = 0;
                            totalActiveVerticalEdgesFullCoverage--;
                        }
                    }
                }
            } else {
                unchangedActiveEdges = 0;

                totalActiveEdges--;
                if (edge->isVertical && edge->isFullCoverage)
                    totalActiveVerticalEdgesFullCoverage--;

                removeEdgeFromAET(edge);
                if (previous == NULL)
                    activeRoot = edge->next;
                else
                    previous->next = edge->next;
            }
        }

        // load more available edges
        for (; nextAvailableEdge < edgeCount; nextAvailableEdge++) {
            edge = edges[nextAvailableEdge];

            if (edge->v0.y >= (scany + 1))
                break;

            unchangedActiveEdges = 0;
            edge->next = activeRoot;
            activeRoot = edge;
            initEdgeForAET(self, edge, scany);
            totalActiveEdges++;

            if (edge->isVertical) {
                if (edge->v0.y < scany && edge->v1.y >= (scany + 1)) {
                    edge->isFullCoverage = 1;
                    totalActiveVerticalEdgesFullCoverage++;
                } else {
                    edge->isFullCoverage = 0;
                }
            }
        }

        if (unchangedActiveEdges) {
            if (activeRoot == NULL && nextAvailableEdge == edgeCount)
                break;

            if (totalActiveVerticalEdgesFullCoverage == totalActiveEdges) {
                CoverageNode *node;

                for (node = currentCoverage; node != NULL; node = node->next) {
#if 0
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
                    writeCoverage(surface, mask, paint, node->scanx, scany,
                                  node->coverage, node->length,
                                  blendFunction);
                }
                continue;
            }
        }

        int minx = xlimit, maxx = 0;
        int *increase = self->_increase;

        for (edge = activeRoot; edge != NULL; edge = edge->next) {
            if (edge->minx >= xlimit) {
                maxx = MAX(maxx, xlimit);
                continue;
            }

            O2Float deltaY = self->samplesDeltaY;
            O2Float scanFloatY = scany + self->samplesInitialY;
            O2Float v0y = edge->v0.y;
            O2Float v1y = edge->v1.y;

            int belowY = 0;
            int aboveY;

            for (; scanFloatY < v0y && belowY < numberOfSamples;
                 scanFloatY += deltaY)
                belowY++;

            if (scany + 1 < v1y)
                aboveY = numberOfSamples;
            else {
                aboveY = belowY;
                for (; scanFloatY < v1y && aboveY < numberOfSamples;
                     scanFloatY += deltaY)
                    aboveY++;
            }

            // it is possible for the edge to be inside the scanline a tiny bit
            // and below/above first/last sample, skip it
            if (aboveY - belowY == 0)
                continue;

            int direction = edge->direction;
            int scanx = edge->minx;

            minx = MIN(minx, scanx);

            O2Float normalX = edge->v0.y - edge->v1.y;
            O2Float normalY = edge->v0.x - edge->v1.x;
            O2Float pcxnormal = (scanx - edge->v0.x) * normalX -
                                (scany - edge->v0.y) * normalY;

            int *windptr = winding + (scanx << shiftNumberOfSamples);

            O2Float *pre = edge->samples;

            for (;; pcxnormal += normalX, windptr += numberOfSamples) {
                /*
                  Some edges do have pcxnormal>edge->maxSample when the normalX
                  is less than zero we should be able to eliminate that
                  condition prior to the loop to avoid an iteration.

                  For now they just end up in the general loop
                 */

                if (increase[scanx] == INT_MAX)
                    increase[scanx] = 0;

                if (pcxnormal <= edge->minSample) {
                    windptr[belowY] += direction;

                    if (aboveY != numberOfSamples)
                        windptr[aboveY] -= direction;
                    else if (belowY == 0) {
                        increase[scanx] += direction;
                        break;
                    }
                } else {
                    int idx = belowY;

                    while (idx < aboveY) {
                        if (pcxnormal <= pre[idx]) {
                            windptr[idx] += direction;
                            windptr[idx + 1] -= direction;
                        }

                        idx++;
                    }

                    if (aboveY == numberOfSamples) {
                        // if we overwrote past the last value, undo it, this is
                        // cheaper than not writing it
                        if (pcxnormal <= pre[idx - 1])
                            windptr[idx] += direction;
                    }
                }

                scanx++;
                if (scanx == xlimit)
                    break;
            }

            maxx = MAX(maxx, scanx);
        }
        minx = MAX(self->_vpx, minx);
        maxx = MIN(xlimit, maxx + 1);

        int *maxAdvance = increase + maxx;

        increase += minx;
        for (; increase < maxAdvance; increase++)
            if (*increase != INT_MAX) {
                break;
            }

        int accum = 0;

        int *windptr = winding +
                       ((increase - self->_increase) << shiftNumberOfSamples);
        int *windend = windptr + numberOfSamples;

        CoverageNode *node;
        for (node = currentCoverage; node != NULL;) {
            CoverageNode *next = node->next;
            node->next = freeCoverage;
            freeCoverage = node;
            node = next;
        }
        currentCoverage = NULL;

        for (; increase < maxAdvance;) {
            int total = accum;
            int coverage = 0;

            if (fillRuleMask == 1) {
                do {
                    total += *windptr;

                    coverage += (total & 0x01);

                    *windptr++ = 0;
                } while (windptr < windend);
            } else {
                do {
                    total += *windptr;

                    coverage += total ? 1 : 0;

                    *windptr++ = 0;
                } while (windptr < windend);
            }

            int *advance = increase + 1;
            for (; advance < maxAdvance; advance++)
                if (*advance != INT_MAX) {
                    break;
                }

            if (coverage > 0) {

                if (self->alias)
                    coverage = 256;
                else
                    coverage *= self->samplesWeight;

                int scanx = increase - self->_increase;

                CoverageNode *node;

                if (freeCoverage == NULL)
                    node = NSZoneMalloc(NULL, sizeof(CoverageNode));
                else {
                    node = freeCoverage;
                    freeCoverage = freeCoverage->next;
                }
                node->next = currentCoverage;
                currentCoverage = node;
                node->scanx = scanx;
                node->coverage = coverage;
                node->length = (advance - increase);
            }

            windend += (advance - increase) << shiftNumberOfSamples;
            windptr = windend - numberOfSamples;

            accum += *increase;
            *increase = INT_MAX;
            increase = advance;
        }

        for (node = currentCoverage; node != NULL; node = node->next) {
#if 0
#warning viewport assert enabled
       if(node->scanx<self->_vpx || node->scanx+node->length>xlimit || scany>=ylimit || scany<self->_vpy){
        NSLog(@"drawing out of viewport, node %d %d %d",node->scanx,scany,node->length);
        NSLog(@"viewport=%d %d %d %d",self->_vpx,self->_vpy,self->_vpwidth,self->_vpheight);
        NSLog(@"xlimit=%d,ylimit=%d",xlimit,ylimit);
        }
#endif
            writeCoverage(surface, mask, paint, node->scanx, scany,
                          node->coverage, node->length, blendFunction);
        }
    }

    for (; activeRoot != NULL; activeRoot = activeRoot->next)
        removeEdgeFromAET(activeRoot);

    CoverageNode *node, *next;
    for (node = freeCoverage; node != NULL; node = next) {
        next = node->next;
        NSZoneFree(NULL, node);
    }
    for (node = currentCoverage; node != NULL; node = next) {
        next = node->next;
        NSZoneFree(NULL, node);
    }
}

void O2DContextClipAndFillEdges(O2Context_builtin *self, int fillRuleMask) {
    O2Image *mask = self->_clipMask;
    O2Surface *surface;

    if ([self->_layerStack count] > 0)
        surface = O2LayerGetSurface([self->_layerStack lastObject]);
    else
        surface = self->_surface;

    O2DContextFillEdgesOnSurface(self, surface, mask, self->_paint,
                                 fillRuleMask);
}

void O2ContextSetupPaintAndBlendMode(O2Context_builtin *self, O2PaintRef paint,
                                     O2BlendMode blendMode)
{
    RI_ASSERT(blendMode >= kO2BlendModeNormal &&
              blendMode <= kO2BlendModePlusLighter);

    self->_blend_argb8u_PRE = NULL;
    self->_writeCoverage_argb8u_PRE = NULL;

    O2ContextSetPaint(self, paint);

    if (O2PaintIsOpaque(self->_paint) && (blendMode == kO2BlendModeNormal))
        blendMode = kO2BlendModeCopy;

    switch (blendMode) {

    case kO2BlendModeNormal:
        self->_blend_argb8u_PRE = O2BlendSpanNormal_8888;
        self->_blend_argb32f_PRE = O2BlendSpanNormal_ffff;
        self->_writeCoverage_argb8u_PRE =
                O2RasterizeWriteCoverageSpan8888_Normal;
        break;

    case kO2BlendModeMultiply:
        self->_blend_argb32f_PRE = O2BlendSpanMultiply_ffff;
        break;

    case kO2BlendModeScreen:
        self->_blend_argb32f_PRE = O2BlendSpanScreen_ffff;
        break;

    case kO2BlendModeOverlay:
        self->_blend_argb32f_PRE = O2BlendSpanOverlay_ffff;
        break;

    case kO2BlendModeDarken:
        self->_blend_argb32f_PRE = O2BlendSpanDarken_ffff;
        break;

    case kO2BlendModeLighten:
        self->_blend_argb32f_PRE = O2BlendSpanLighten_ffff;
        break;

    case kO2BlendModeColorDodge:
        self->_blend_argb32f_PRE = O2BlendSpanColorDodge_ffff;
        break;

    case kO2BlendModeColorBurn:
        self->_blend_argb32f_PRE = O2BlendSpanColorBurn_ffff;
        break;

    case kO2BlendModeHardLight:
        self->_blend_argb32f_PRE = O2BlendSpanHardLight_ffff;
        break;

    case kO2BlendModeSoftLight:
        self->_blend_argb32f_PRE = O2BlendSpanSoftLight_ffff;
        break;

    case kO2BlendModeDifference:
        self->_blend_argb32f_PRE = O2BlendSpanDifference_ffff;
        break;

    case kO2BlendModeExclusion:
        self->_blend_argb32f_PRE = O2BlendSpanExclusion_ffff;
        break;

    case kO2BlendModeHue:
        self->_blend_argb32f_PRE = O2BlendSpanHue_ffff;
        break;

    case kO2BlendModeSaturation:
        self->_blend_argb32f_PRE = O2BlendSpanSaturation_ffff;
        break;

    case kO2BlendModeColor:
        self->_blend_argb32f_PRE = O2BlendSpanColor_ffff;
        break;

    case kO2BlendModeLuminosity:
        self->_blend_argb32f_PRE = O2BlendSpanLuminosity_ffff;
        break;

    case kO2BlendModeClear:
        self->_blend_argb8u_PRE = O2BlendSpanClear_8888;
        self->_blend_argb32f_PRE = O2BlendSpanClear_ffff;
        break;

    case kO2BlendModeCopy:
        self->_blend_argb8u_PRE = O2BlendSpanCopy_8888;
        self->_blend_argb32f_PRE = O2BlendSpanCopy_ffff;
        self->_writeCoverage_argb8u_PRE = O2RasterizeWriteCoverageSpan8888_Copy;
        break;

    case kO2BlendModeSourceIn:
        self->_blend_argb8u_PRE = O2BlendSpanSourceIn_8888;
        self->_blend_argb32f_PRE = O2BlendSpanSourceIn_ffff;
        break;

    case kO2BlendModeSourceOut:
        self->_blend_argb32f_PRE = O2BlendSpanSourceOut_ffff;
        break;

    case kO2BlendModeSourceAtop:
        self->_blend_argb32f_PRE = O2BlendSpanSourceAtop_ffff;
        break;

    case kO2BlendModeDestinationOver:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationOver_ffff;
        break;

    case kO2BlendModeDestinationIn:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationIn_ffff;
        break;

    case kO2BlendModeDestinationOut:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationOut_ffff;
        break;

    case kO2BlendModeDestinationAtop:
        self->_blend_argb32f_PRE = O2BlendSpanDestinationAtop_ffff;
        break;

    case kO2BlendModeXOR:
        self->_blend_argb8u_PRE = O2BlendSpanXOR_8888;
        self->_blend_argb32f_PRE = O2BlendSpanXOR_ffff;
        break;

    case kO2BlendModePlusDarker:
        self->_blend_argb32f_PRE = O2BlendSpanPlusDarker_ffff;
        break;

    case kO2BlendModePlusLighter:
        self->_blend_argb8u_PRE = O2BlendSpanPlusLighter_8888;
        self->_blend_argb32f_PRE = O2BlendSpanPlusLighter_ffff;
        break;
    }

    if (self->_writeCoverage_argb8u_PRE != NULL) {
        self->_blendFunction = NULL;
        self->_writeCoverageFunction = self->_writeCoverage_argb8u_PRE;
    } else {
        if (self->_blend_argb8u_PRE != NULL) {
            self->_blendFunction = self->_blend_argb8u_PRE;
            self->_writeCoverageFunction = O2RasterizeWriteCoverageSpan8888;
        } else {
            self->_blendFunction = self->_blend_argb32f_PRE;
            self->_writeCoverageFunction = O2RasterizeWriteCoverageSpanffff;
        }
    }
}

void O2ContextSetPaint(O2Context_builtin *self, O2PaintRef paint) {
    paint = O2PaintRetain(paint);
    O2PaintRelease(self->_paint);
    self->_paint = paint;
}

@end
