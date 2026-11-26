/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// Context delegates: a context whose drawing operations go to client
// callbacks. The context is an Onyx2D context that keeps the graphics state
// like any other and, where a drawing context would rasterize, calls the
// delegate's callback for the operation instead.
//
// Delivered: path drawing (fills, strokes, rectangles, ellipses, clears and
// everything else drawn as a path) to deDrawPath, images (and CGLayers, as an
// image of the layer) to deDrawImage, glyphs (CGContextShowGlyphs* and
// CTFontDrawGlyphs) to deDrawGlyphs, and transparency layers to deBeginLayer
// and deEndLayer. Not delivered, and not drawn: shadings and gradients (there
// is no callback kind for them in the known set), and PDF pages other than
// through the paths, images and glyphs their content draws.

#import "CGContextInternal.h"
#import <CoreFoundation/CFRuntime.h>
#import <Onyx2D/O2BitmapContext.h>
#import <Onyx2D/O2Context.h>
#import <Onyx2D/O2GraphicsState.h>
#import <Onyx2D/O2Layer.h>
#import <Onyx2D/O2MutablePath.h>
#import <Onyx2D/O2PDFContext.h>
#import <Onyx2D/O2Surface.h>
#include <pthread.h>
#include <string.h>

// Callback kinds are small numbers; a kind outside the table is accepted and
// never called.
#define CGContextDelegateCallbackCount 64

struct CGContextDelegate {
    CFRuntimeBase base;
    void *info;
    CGContextDelegateCallback callbacks[CGContextDelegateCallbackCount];
};

static CFTypeID delegateTypeID;
static CFRuntimeClass delegateClass;
static pthread_once_t registerDelegateOnce = PTHREAD_ONCE_INIT;

static void registerDelegate(void) {
    memset(&delegateClass, 0, sizeof(delegateClass));
    delegateClass.version = 0;
    delegateClass.className = "CGContextDelegate";
    delegateTypeID = _CFRuntimeRegisterClass(&delegateClass);
}

CFTypeID CGContextDelegateGetTypeID(void) {
    pthread_once(&registerDelegateOnce, registerDelegate);
    return delegateTypeID;
}

CGContextDelegateRef CGContextDelegateCreate(void *info) {
    CGContextDelegateRef delegate = (CGContextDelegateRef) _CFRuntimeCreateInstance(
            NULL, CGContextDelegateGetTypeID(),
            sizeof(struct CGContextDelegate) - sizeof(CFRuntimeBase), NULL);
    if (delegate == NULL)
        return NULL;
    delegate->info = info;
    memset(delegate->callbacks, 0, sizeof(delegate->callbacks));
    return delegate;
}

CGContextDelegateRef CGContextDelegateRetain(CGContextDelegateRef delegate) {
    if (delegate == NULL)
        return NULL;
    return (CGContextDelegateRef) CFRetain(delegate);
}

void CGContextDelegateRelease(CGContextDelegateRef delegate) {
    if (delegate != NULL)
        CFRelease(delegate);
}

void *CGContextDelegateGetInfo(CGContextDelegateRef delegate) {
    return delegate != NULL ? delegate->info : NULL;
}

void CGContextDelegateSetCallback(CGContextDelegateRef delegate,
        CGContextDelegateCallbackName name, CGContextDelegateCallback callback)
{
    if (delegate == NULL || name < 0 || name >= CGContextDelegateCallbackCount)
        return;
    delegate->callbacks[name] = callback;
}

static CGContextDelegateCallback callbackFor(CGContextDelegateRef delegate,
        CGContextDelegateCallbackName name)
{
    return delegate->callbacks[name];
}

@interface CGContextDelegateContext : O2Context {
    CGContextDelegateRef _delegate;
    CGContextType _type;
    // transparency layers begun and not yet ended
    NSUInteger _layerDepth;
}

- initWithDelegate: (CGContextDelegateRef) delegate
              type: (CGContextType) type
       graphicsState: (O2GState *) state;
- (CGContextType) contextType;
- (void) beginLayerInRect: (O2Rect) rect info: (NSDictionary *) info;
- (void) deliverGlyphs: (const O2Glyph *) glyphs
             positions: (const CGPoint *) positions
                 count: (size_t) count;

@end

@implementation CGContextDelegateContext

- initWithDelegate: (CGContextDelegateRef) delegate
              type: (CGContextType) type
       graphicsState: (O2GState *) state
{
    if ([super initWithGraphicsState: state] == nil)
        return nil;
    _delegate = CGContextDelegateRetain(delegate);
    _type = type;
    return self;
}

- (void) dealloc {
    CGContextDelegateRelease(_delegate);
    [super dealloc];
}

- (CGContextType) contextType {
    return _type;
}

- (BOOL) isBitmapContext {
    return NO;
}

- (BOOL) supportsGlobalAlpha {
    return YES;
}

- (O2Size) size {
    return O2SizeMake(0, 0);
}

- (void) clipToState: (O2ClipState *) clipState {
}

- (void) copyBitsInRect: (O2Rect) rect
                toPoint: (O2Point) point
                 gState: (int) gState
{
}

- (NSData *) captureBitmapInRect: (NSRect) rect {
    return nil;
}

// A CGLayer made for this context draws into a bitmap; drawing the layer
// hands an image of it to the delegate.
- (O2ContextRef) createCompatibleContextWithSize: (O2Size) size
                                          unused: (NSDictionary *) unused
{
    size_t width = size.width > 0 ? (size_t) ceil(size.width) : 1;
    size_t height = size.height > 0 ? (size_t) ceil(size.height) : 1;
    O2ColorSpaceRef space = O2ColorSpaceCreateDeviceRGB();
    O2ContextRef result = O2BitmapContextCreate(NULL, width, height, 8, 0, space,
            kO2BitmapByteOrder32Little | kO2ImageAlphaPremultipliedFirst);
    O2ColorSpaceRelease(space);
    return result;
}

- (void) drawPath: (O2PathDrawingMode) pathMode {
    CGContextDelegateDrawPathCallback callback =
            (CGContextDelegateDrawPathCallback) callbackFor(_delegate, deDrawPath);

    if (callback != NULL && !O2PathIsEmpty(_path)) {
        O2PathRef path = O2PathCreateCopy(_path);
        callback(_delegate, NULL, (CGGStateRef) O2ContextCurrentGState(self),
                 (CGPathDrawingMode) pathMode, (CGPathRef) path);
        O2PathRelease(path);
    }
    O2PathReset(_path);
}

- (void) drawImage: (O2Image *) image inRect: (O2Rect) rect {
    CGContextDelegateDrawImageCallback callback =
            (CGContextDelegateDrawImageCallback) callbackFor(_delegate, deDrawImage);

    if (callback != NULL && image != nil)
        callback(_delegate, NULL, (CGGStateRef) O2ContextCurrentGState(self),
                 rect, (CGImageRef) image);
}

- (void) drawLayer: (O2LayerRef) layer inRect: (O2Rect) rect {
    O2Surface *surface = O2LayerGetSurface(layer);
    if (surface == nil)
        return;
    O2ImageRef image = O2SurfaceCreateImage(surface);
    [self drawImage: image inRect: rect];
    O2ImageRelease(image);
}

// No callback kind takes a shading; it is not drawn.
- (void) drawShading: (O2Shading *) shading {
}

- (void) deliverGlyphs: (const O2Glyph *) glyphs
             positions: (const CGPoint *) positions
                 count: (size_t) count
{
    CGContextDelegateDrawGlyphsCallback callback =
            (CGContextDelegateDrawGlyphsCallback) callbackFor(_delegate, deDrawGlyphs);

    if (callback == NULL || count == 0)
        return;
    CGAffineTransform textMatrix = {_textMatrix.a, _textMatrix.b, _textMatrix.c,
                                    _textMatrix.d, _textMatrix.tx, _textMatrix.ty};
    callback(_delegate, NULL, (CGGStateRef) O2ContextCurrentGState(self),
             &textMatrix, glyphs, positions, count);
}

// Glyphs drawn at the text position: they are given positions in text space
// starting at the origin (the text matrix holds the text position), each the
// previous one plus its advance, and the text position moves past them.
- (void) showGlyphs: (const O2Glyph *) glyphs
           advances: (const O2Size *) advances
              count: (NSUInteger) count
{
    if (glyphs == NULL || count == 0)
        return;
    if (count > SIZE_MAX / (sizeof(O2Size) + sizeof(CGPoint)))
        return;

    O2Size *defaultAdvances = NULL;
    if (advances == NULL) {
        defaultAdvances = calloc(count, sizeof(O2Size));
        if (defaultAdvances == NULL)
            return;
        if (O2GStateFont(O2ContextCurrentGState(self)) != nil)
            O2ContextGetDefaultAdvances(self, glyphs, defaultAdvances, count);
        advances = defaultAdvances;
    }
    CGPoint *positions = malloc(count * sizeof(CGPoint));
    if (positions != NULL) {
        CGPoint position = CGPointZero;
        for (NSUInteger i = 0; i < count; i++) {
            positions[i] = position;
            position.x += advances[i].width;
            position.y += advances[i].height;
        }
        [self deliverGlyphs: glyphs positions: positions count: count];
        free(positions);
    }
    O2ContextConcatAdvancesToTextMatrix(self, advances, count);
    free(defaultAdvances);
}

// The callback is given the state the layer is begun in (its alpha, shadow
// and blend mode are those the layer is composited with); inside the layer
// they start over, as for any transparency layer.
- (void) beginLayerInRect: (O2Rect) rect info: (NSDictionary *) info {
    CGContextDelegateBeginLayerCallback callback =
            (CGContextDelegateBeginLayerCallback) callbackFor(_delegate, deBeginLayer);

    // The delegate the callback returns, meant for the drawing inside the
    // layer, is not used: the layer's drawing goes to this context's delegate.
    if (callback != NULL)
        callback(_delegate, NULL, (CGGStateRef) O2ContextCurrentGState(self),
                 rect, (CFDictionaryRef) info, _delegate);

    O2ContextSaveGState(self);
    O2GState *gState = O2ContextCurrentGState(self);
    O2GStateSetAlpha(gState, 1);
    O2GStateSetBlendMode(gState, kO2BlendModeNormal);
    [gState setShadowOffset: O2SizeMake(0, 0) blur: 0 color: nil];
    O2GStateSetStyle(gState, NULL);
    O2GStateSetFocusRing(gState, nil, 0, 0);
    _layerDepth++;
}

- (void) beginTransparencyLayerWithInfo: (NSDictionary *) info {
    [self beginLayerInRect: O2ContextGetClipBoundingBox(self) info: info];
}

- (void) endTransparencyLayer {
    if (_layerDepth == 0)
        return;
    _layerDepth--;
    O2ContextRestoreGState(self);

    CGContextDelegateEndLayerCallback callback =
            (CGContextDelegateEndLayerCallback) callbackFor(_delegate, deEndLayer);
    if (callback != NULL)
        callback(_delegate, NULL, (CGGStateRef) O2ContextCurrentGState(self));
}

@end

CGContextRef CGContextCreateWithDelegate(CGContextDelegateRef delegate,
        CGContextType type, CGRenderingStateRef renderingState, CGGStateRef gstate)
{
    (void) renderingState;
    if (delegate == NULL)
        return NULL;
    if ((int) type < 0 || type >= kCGContextTypeCount)
        type = kCGContextTypeUnknown;

    O2GState *state = gstate != NULL
            ? O2GStateCopyWithZone((O2GState *) gstate, NULL)
            : [[O2GState alloc] init];
    CGContextDelegateContext *context =
            [[CGContextDelegateContext alloc] initWithDelegate: delegate
                                                          type: type
                                                 graphicsState: state];
    [state release];
    return (CGContextRef) context;
}

bool _CGContextDelegateShowGlyphsAtPositions(CGContextRef context,
        const CGGlyph *glyphs, const CGPoint *positions, size_t count)
{
    id object = (id) context;
    if (![object isKindOfClass: [CGContextDelegateContext class]])
        return false;
    [(CGContextDelegateContext *) object deliverGlyphs: glyphs
                                             positions: positions
                                                 count: count];
    return true;
}

bool _CGContextDelegateBeginLayer(CGContextRef context, CGRect rect,
        CFDictionaryRef auxiliaryInfo)
{
    id object = (id) context;
    if (![object isKindOfClass: [CGContextDelegateContext class]])
        return false;
    [(CGContextDelegateContext *) object beginLayerInRect: rect
                                                     info: (NSDictionary *) auxiliaryInfo];
    return true;
}

// Window contexts are bitmap contexts in Darling (Onyx2D draws windows into
// bitmaps), so they report kCGContextTypeBitmap.
CGContextType CGContextGetType(CGContextRef context) {
    id object = (id) context;

    if (object == nil)
        return kCGContextTypeUnknown;
    if ([object isKindOfClass: [CGContextDelegateContext class]])
        return [(CGContextDelegateContext *) object contextType];
    if (_CGIOSurfaceContextIsIOSurfaceContext(context))
        return kCGContextTypeIOSurface;
    if ([object isKindOfClass: [O2PDFContext class]])
        return kCGContextTypePDF;
    if ([object isKindOfClass: [O2BitmapContext class]])
        return kCGContextTypeBitmap;
    return kCGContextTypeUnknown;
}

CGFloat CGGStateGetAlpha(CGGStateRef gstate) {
    return gstate != NULL ? O2GStateAlpha((O2GState *) gstate) : 0;
}

CGFontRef CGGStateGetFont(CGGStateRef gstate) {
    return gstate != NULL ? (CGFontRef) O2GStateFont((O2GState *) gstate) : NULL;
}

CGFloat CGGStateGetFontSize(CGGStateRef gstate) {
    return gstate != NULL ? O2GStatePointSize((O2GState *) gstate) : 0;
}

// The CTM as CGContextGetCTM reports it. O2AffineTransform has the layout of
// CGAffineTransform (six CGFloat fields in the same order).
const CGAffineTransform *CGGStateGetCTM(CGGStateRef gstate) {
    if (gstate == NULL)
        return NULL;
    return (const CGAffineTransform *) &((O2GState *) gstate)->_userSpaceTransform;
}

CGColorRef CGGStateGetFillColor(CGGStateRef gstate) {
    return gstate != NULL ? (CGColorRef) O2GStateFillColor((O2GState *) gstate) : NULL;
}

CGColorRef CGGStateGetStrokeColor(CGGStateRef gstate) {
    return gstate != NULL ? (CGColorRef) O2GStateStrokeColor((O2GState *) gstate) : NULL;
}
