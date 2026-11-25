/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <Onyx2D/O2GraphicsState.h>

#import <Foundation/NSArray.h>
#import <Onyx2D/O2ClipPhase.h>
#import <Onyx2D/O2ClipState.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2Exceptions.h>
#import <Onyx2D/O2Font.h>
#import <Onyx2D/O2Geometry.h>
#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2Surface.h>

@implementation O2GState

- initWithDeviceTransform: (O2AffineTransform) deviceTransform {
    _deviceSpaceTransform = deviceTransform;
    _userSpaceTransform = O2AffineTransformIdentity;
    _clipState = [[O2ClipState alloc] init];
    _strokeColor = [[O2Color alloc] init];
    _fillColor = [[O2Color alloc] init];
    _fillColorIsDirty = YES;
    _font = nil;
    _pointSize = 12.0;
    _fontIsDirty = YES;
    _encoding = nil;
    _pdfCharWidths = nil;
    _fontState = nil;
    _patternPhase = O2SizeMake(0, 0);
    _lineWidth = 1.0;
    _miterLimit = 10;
    _blendMode = kO2BlendModeNormal;
    _interpolationQuality = kO2InterpolationDefault;
    _shouldAntialias = YES;
    _antialiasingQuality = 64;
    // A new context reports font smoothing on, with style 0x30 (as observed
    // on macOS 26.7.3 for a bitmap context).
    _shouldSmoothFonts = YES;
    _fontSmoothingStyle = 0x30;
    _alpha = 1.;
    _baseCTM = O2AffineTransformIdentity;
    _style = NULL;
    _shouldAntialiasFonts = YES;
    _focusRingColor = nil;
    return self;
}

- initFlippedWithDeviceHeight: (O2Float) height {
    O2AffineTransform flip = {1, 0, 0, -1, 0, height};

    return [self initWithDeviceTransform: flip];
}

- initFlippedWithDeviceHeight: (O2Float) height
                       concat: (O2AffineTransform) concat
{
    O2AffineTransform flip = {1, 0, 0, -1, 0, height};

    return [self
            initWithDeviceTransform: O2AffineTransformConcat(flip, concat)];
}

- init {
    return [self initWithDeviceTransform: O2AffineTransformIdentity];
}

- (void) dealloc {
    [_clipState release];
    O2ColorRelease(_strokeColor);
    O2ColorRelease(_fillColor);
    [_font release];
    [_encoding release];
    [_pdfCharWidths release];
    [_fontState release];
    if (_dashLengths != NULL)
        NSZoneFree(NULL, _dashLengths);
    O2ColorRelease(_shadowColor);
    O2GaussianKernelRelease(_shadowKernel);
    if (_style != NULL)
        CFRelease(_style);
    O2ColorRelease(_focusRingColor);
    NSDeallocateObject(self);
    return;
    [super dealloc];
}

O2GState *O2GStateCopyWithZone(O2GState *self, NSZone *zone) {
    O2GState *copy = NSCopyObject(self, 0, zone);

    copy->_clipState = O2ClipStateCreateCopy(self->_clipState);
    copy->_strokeColor = O2ColorCreateCopy(self->_strokeColor);
    copy->_fillColor = O2ColorCreateCopy(self->_fillColor);
    copy->_font = [self->_font retain];
    copy->_encoding = [self->_encoding retain];
    copy->_pdfCharWidths = [self->_pdfCharWidths retain];
    copy->_fontState = [self->_fontState retain];
    if (self->_dashLengths != NULL) {
        int i;

        copy->_dashLengths =
                NSZoneMalloc(zone, sizeof(O2Float) * self->_dashLengthsCount);
        for (i = 0; i < self->_dashLengthsCount; i++)
            copy->_dashLengths[i] = self->_dashLengths[i];
    }

    copy->_shadowColor = O2ColorCreateCopy(self->_shadowColor);

    copy->_shadowKernel = O2GaussianKernelRetain(self->_shadowKernel);

    copy->_alpha = self->_alpha;

    if (self->_style != NULL)
        CFRetain(self->_style);
    O2ColorRetain(self->_focusRingColor);

    return copy;
}

- (O2AffineTransform) userSpaceToDeviceSpaceTransform {
    return _deviceSpaceTransform;
}

O2AffineTransform O2GStateUserSpaceTransform(O2GState *self) {
    return self->_userSpaceTransform;
}

// The bounding box of the clip in user space (CGContextGetClipBoundingBox). The documentation gives the box of
// the clipping path with the control points of curves included. The other cases are pinned to what was observed
// on macOS 26.7.3 and Mac OS X 10.14.4 (identical), tests coregraphics-context-clip-bounding-box:
//  - no clip: the bounds of the context;
//  - an empty or zero-size intersection: CGRectNull;
//  - a clip larger than the context: the context bounds;
//  - a mask: the intersection with the mask's rectangle; several paths or rectangles: the intersection of their
//    boxes (two rectangle subpaths in one clip give the box of their union; an even-odd hole is ignored);
//  - under a rotating transformation: the box, in user space, of the clip's rectangle in device space (not of
//    the rotated clip itself).
// The clip is kept in device space, so the device box of each phase is intersected first and the result moved
// back through the current transform. A context with no bounds of its own (bounds of zero size) has no
// device limit: with no clip the answer is then the zero rectangle.
- (O2Rect) clipBoundingBoxWithinDeviceBounds: (O2Rect) bounds {
    BOOL bounded = bounds.size.width > 0 && bounds.size.height > 0;
    NSArray *phases = [_clipState clipPhases];

    if (_deviceSpaceTransform.a * _deviceSpaceTransform.d - _deviceSpaceTransform.b * _deviceSpaceTransform.c == 0 ||
        (!bounded && [phases count] == 0))
        return O2RectZero;

    O2Float minX = 0, minY = 0, maxX = 0, maxY = 0;
    BOOL haveBox = NO;

    if (bounded) {
        minX = O2RectGetMinX(bounds);
        minY = O2RectGetMinY(bounds);
        maxX = O2RectGetMaxX(bounds);
        maxY = O2RectGetMaxY(bounds);
        haveBox = YES;
    }

    for (O2ClipPhase *phase in phases) {
        O2Rect box;

        if (O2ClipPhasePhaseType(phase) == O2ClipPhaseMask) {
            O2Rect rect = O2ClipPhaseRect(phase);
            O2AffineTransform transform = O2ClipPhaseTransform(phase);
            O2Point corners[4] = {
                O2PointApplyAffineTransform(O2PointMake(O2RectGetMinX(rect), O2RectGetMinY(rect)), transform),
                O2PointApplyAffineTransform(O2PointMake(O2RectGetMaxX(rect), O2RectGetMinY(rect)), transform),
                O2PointApplyAffineTransform(O2PointMake(O2RectGetMaxX(rect), O2RectGetMaxY(rect)), transform),
                O2PointApplyAffineTransform(O2PointMake(O2RectGetMinX(rect), O2RectGetMaxY(rect)), transform),
            };
            O2Float x0 = corners[0].x, x1 = x0, y0 = corners[0].y, y1 = y0;

            for (int i = 1; i < 4; i++) {
                x0 = MIN(x0, corners[i].x);
                x1 = MAX(x1, corners[i].x);
                y0 = MIN(y0, corners[i].y);
                y1 = MAX(y1, corners[i].y);
            }
            box = O2RectMake(x0, y0, x1 - x0, y1 - y0);
        } else
            box = O2PathGetBoundingBox(O2ClipPhaseObject(phase));

        if (!haveBox) {
            minX = O2RectGetMinX(box);
            minY = O2RectGetMinY(box);
            maxX = O2RectGetMaxX(box);
            maxY = O2RectGetMaxY(box);
            haveBox = YES;
        } else {
            minX = MAX(minX, O2RectGetMinX(box));
            minY = MAX(minY, O2RectGetMinY(box));
            maxX = MIN(maxX, O2RectGetMaxX(box));
            maxY = MIN(maxY, O2RectGetMaxY(box));
        }
    }

    if (!(maxX > minX) || !(maxY > minY))
        return O2RectMake(INFINITY, INFINITY, 0, 0);

    O2AffineTransform toUser = O2AffineTransformInvert(_deviceSpaceTransform);
    O2Point corners[4] = {
        O2PointApplyAffineTransform(O2PointMake(minX, minY), toUser),
        O2PointApplyAffineTransform(O2PointMake(maxX, minY), toUser),
        O2PointApplyAffineTransform(O2PointMake(maxX, maxY), toUser),
        O2PointApplyAffineTransform(O2PointMake(minX, maxY), toUser),
    };
    O2Float x0 = corners[0].x, x1 = x0, y0 = corners[0].y, y1 = y0;

    for (int i = 1; i < 4; i++) {
        x0 = MIN(x0, corners[i].x);
        x1 = MAX(x1, corners[i].x);
        y0 = MIN(y0, corners[i].y);
        y1 = MAX(y1, corners[i].y);
    }
    return O2RectMake(x0, y0, x1 - x0, y1 - y0);
}

- (O2InterpolationQuality) interpolationQuality {
    return _interpolationQuality;
}

- (O2Point) convertPointToDeviceSpace: (O2Point) point {
    return O2PointApplyAffineTransform(point, _deviceSpaceTransform);
}

- (O2Point) convertPointToUserSpace: (O2Point) point {
    return O2PointApplyAffineTransform(
            point, O2AffineTransformInvert(_deviceSpaceTransform));
}

- (O2Size) convertSizeToDeviceSpace: (O2Size) size {
    return O2SizeApplyAffineTransform(size, _deviceSpaceTransform);
}

- (O2Size) convertSizeToUserSpace: (O2Size) size {
    return O2SizeApplyAffineTransform(
            size, O2AffineTransformInvert(_deviceSpaceTransform));
}

- (O2Rect) convertRectToDeviceSpace: (O2Rect) rect {
    O2UnimplementedMethod();
    return O2RectZero;
}

- (O2Rect) convertRectToUserSpace: (O2Rect) rect {
    O2UnimplementedMethod();
    return O2RectZero;
}

void O2GStateSetDeviceSpaceCTM(O2GState *self, O2AffineTransform transform) {
    self->_deviceSpaceTransform = transform;
    self->_fontIsDirty = YES;
}

void O2GStateSetUserSpaceCTM(O2GState *self, O2AffineTransform transform) {
    self->_userSpaceTransform = transform;
    self->_fontIsDirty = YES;
}

void O2GStateConcatCTM(O2GState *self, O2AffineTransform transform) {
    self->_deviceSpaceTransform =
            O2AffineTransformConcat(transform, self->_deviceSpaceTransform);
    self->_userSpaceTransform =
            O2AffineTransformConcat(transform, self->_userSpaceTransform);
    self->_fontIsDirty = YES;
}

O2ClipState *O2GStateClipState(O2GState *self) {
    return self->_clipState;
}

void O2GStateResetClip(O2GState *self) {
    O2ClipStateReset(self->_clipState);
}

void O2GStateAddClipToPath(O2GState *self, O2Path *path) {
    [self->_clipState addNonZeroWindingPath: path];
}

void O2GStateAddEvenOddClipToPath(O2GState *self, O2Path *path) {
    [self->_clipState addEvenOddWindingPath: path];
}

void O2GStateAddClipToMask(O2GState *self, O2Image *image, O2Rect rect) {
    [self->_clipState addMask: image
                       inRect: rect
                    transform: self->_deviceSpaceTransform];
}

O2ColorRef O2GStateStrokeColor(O2GState *self) {
    return self->_strokeColor;
}

O2ColorRef O2GStateFillColor(O2GState *self) {
    return self->_fillColor;
}

void O2GStateSetStrokeColor(O2GState *self, O2ColorRef color) {
    color = [color retain];
    [self->_strokeColor release];
    self->_strokeColor = color;
}

void O2GStateSetFillColor(O2GState *self, O2ColorRef color) {
    color = [color retain];
    [self->_fillColor release];
    self->_fillColor = color;
    self->_fillColorIsDirty = YES;
}

O2Size O2GStatePatternPhase(O2GState *self) {
    return self->_patternPhase;
}

void O2GStateSetPatternPhase(O2GState *self, O2Size value) {
    self->_patternPhase = value;
}

- (void) setStrokePattern: (O2Pattern *) pattern
               components: (const O2Float *) components
{
}

- (void) setFillPattern: (O2Pattern *) pattern
             components: (const O2Float *) components
{
}

- (void) setTextDrawingMode: (int) textMode {
    _textDrawingMode = textMode;
}

O2FontRef O2GStateFont(O2GState *self) {
    return self->_font;
}

O2Float O2GStatePointSize(O2GState *self) {
    return self->_pointSize;
}

O2Encoding *O2GStateEncoding(O2GState *self) {
    return self->_encoding;
}

O2PDFCharWidths *O2GStateCharWidths(O2GState *self) {
    return self->_pdfCharWidths;
}

- (O2Encoding *) encoding {
    return _encoding;
}

- (O2PDFCharWidths *) pdfCharWidths {
    return _pdfCharWidths;
}

- (void) setPDFCharWidths: (O2PDFCharWidths *) value {
    value = [value retain];
    [_pdfCharWidths release];
    _pdfCharWidths = value;
}

void O2GStateClearFontIsDirty(O2GState *self) {
    self->_fontIsDirty = NO;
}

- (id) fontState {
    return _fontState;
}

- (void) setFontState: (id) fontState {
    fontState = [fontState retain];
    [_fontState release];
    _fontState = fontState;
}

void O2GStateSetFont(O2GState *self, O2Font *font) {
    if (font != self->_font) {
        font = [font retain];
        [self->_font release];
        self->_font = font;

        O2Encoding *encoding = [self->_font
                createEncodingForTextEncoding: kO2EncodingFontSpecific];
        O2GStateSetFontEncoding(self, encoding);
        [encoding release];

        self->_fontIsDirty = YES;
    }
}

void O2GStateSetFontSize(O2GState *self, O2Float size) {
    if (self->_pointSize != size) {
        self->_pointSize = size;
        self->_fontIsDirty = YES;
    }
}

void O2GStateSetFontEncoding(O2GState *self, O2Encoding *encoding) {
    encoding = [encoding retain];
    [self->_encoding release];
    self->_encoding = encoding;
}

- (void) selectFontWithName: (const char *) name
                       size: (O2Float) size
                   encoding: (O2TextEncoding) textEncoding
{
    O2Font *font = O2FontCreateWithFontName(
            [NSString stringWithCString: name encoding: NSUTF8StringEncoding]);

    O2GStateSetFont(self, font);
    O2GStateSetFontSize(self, size);
    O2Encoding *encoding = [_font createEncodingForTextEncoding: textEncoding];
    O2GStateSetFontEncoding(self, encoding);
    [encoding release];
}

O2Float O2GStateCharacterSpacing(O2GState *self) {
    return self->_characterSpacing;
}

O2Float O2GStateWordSpacing(O2GState *self) {
    return self->_wordSpacing;
}

O2Float O2GStateTextLeading(O2GState *self) {
    return self->_textLeading;
}

O2Float O2GStateTextRise(O2GState *self) {
    return self->_textRise;
}

O2Float O2GStateTextHorizontalScaling(O2GState *self) {
    return self->_textHorizontalScaling;
}

void O2GStateSetCharacterSpacing(O2GState *self, O2Float value) {
    self->_characterSpacing = value;
}

void O2GStateSetWordSpacing(O2GState *self, O2Float value) {
    self->_wordSpacing = value;
}

void O2GStateSetTextLeading(O2GState *self, O2Float value) {
    self->_textLeading = value;
}

void O2GStateSetTextRise(O2GState *self, O2Float value) {
    self->_textRise = value;
}

void O2GStateSetTextHorizontalScaling(O2GState *self, O2Float value) {
    self->_textHorizontalScaling = value;
}

- (void) setShouldSmoothFonts: (BOOL) yesOrNo {
    _shouldSmoothFonts = yesOrNo;
    _fontIsDirty = YES;
}

- (BOOL) shouldSmoothFonts {
    return _shouldSmoothFonts;
}

- (uint32_t) fontSmoothingStyle {
    return _fontSmoothingStyle;
}

- (void) setFontSmoothingStyle: (uint32_t) style {
    _fontSmoothingStyle = style;
}

void O2GStateSetLineWidth(O2GState *self, O2Float width) {
    self->_lineWidth = width;
}

void O2GStateSetLineCap(O2GState *self, int lineCap) {
    self->_lineCap = lineCap;
}

void O2GStateSetLineJoin(O2GState *self, int lineJoin) {
    self->_lineJoin = lineJoin;
}

void O2GStateSetMiterLimit(O2GState *self, O2Float limit) {
    self->_miterLimit = limit;
}

void O2GStateSetLineDash(O2GState *self, O2Float phase, const O2Float *lengths,
                         size_t count)
{
    self->_dashPhase = phase;
    self->_dashLengthsCount = count;

    if (self->_dashLengths != NULL)
        NSZoneFree(NULL, self->_dashLengths);

    if (lengths == NULL || count == 0)
        self->_dashLengths = NULL;
    else {
        int i;

        self->_dashLengths = NSZoneMalloc(NULL, sizeof(O2Float) * count);
        for (i = 0; i < count; i++)
            self->_dashLengths[i] = lengths[i];
    }
}

- (void) setRenderingIntent: (O2ColorRenderingIntent) intent {
    _renderingIntent = intent;
}

O2BlendMode O2GStateBlendMode(O2GState *self) {
    return self->_blendMode;
}

void O2GStateSetBlendMode(O2GState *self, O2BlendMode mode) {
    self->_blendMode = mode;
}

O2Float O2GStateAlpha(O2GState *self) {
    return self->_alpha;
}

void O2GStateSetAlpha(O2GState *self, O2Float alpha) {
    self->_alpha = alpha;
}

- (void) setFlatness: (O2Float) flatness {
    _flatness = flatness;
}

- (void) setInterpolationQuality: (O2InterpolationQuality) quality {
    _interpolationQuality = quality;
}

- (void) setShadowOffset: (O2Size) offset
                    blur: (O2Float) blur
                   color: (O2ColorRef) color
{
    _shadowOffset = offset;
    _shadowBlur = blur;
    color = [color retain];
    [_shadowColor release];
    _shadowColor = color;
    O2GaussianKernelRelease(_shadowKernel);
    _shadowKernel = (_shadowColor == nil)
                            ? NULL
                            : O2CreateGaussianKernelWithDeviation(blur);
}

- (void) setShadowOffset: (O2Size) offset blur: (O2Float) blur {
    O2ColorSpaceRef colorSpace = O2ColorSpaceCreateDeviceRGB();
    O2Float components[4] = {0, 0, 0, 1.0 / 3.0};
    O2ColorRef color = O2ColorCreate(colorSpace, components);

    [self setShadowOffset: offset blur: blur color: color];
    [color release];
    [colorSpace release];
}

- (void) setShouldAntialias: (BOOL) flag {
    _shouldAntialias = flag;
}

O2AffineTransform O2GStateGetBaseCTM(O2GState *self) {
    return self->_baseCTM;
}

void O2GStateSetBaseCTM(O2GState *self, O2AffineTransform transform) {
    self->_baseCTM = transform;
}

CFTypeRef O2GStateGetStyle(O2GState *self) {
    return self->_style;
}

void O2GStateSetStyle(O2GState *self, CFTypeRef style) {
    if (style != NULL)
        CFRetain(style);
    if (self->_style != NULL)
        CFRelease(self->_style);
    self->_style = style;
}

void O2GStateSetFocusRing(O2GState *self, O2ColorRef color, O2Float radius,
                          int ordering)
{
    O2ColorRetain(color);
    O2ColorRelease(self->_focusRingColor);
    self->_focusRingColor = color;
    self->_focusRingRadius = radius;
    self->_focusRingOrdering = ordering;
}

// temporary

- (void) setAntialiasingQuality: (int) value {
    _antialiasingQuality = value;
}

@end
