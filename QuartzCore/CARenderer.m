#import <CoreVideo/CoreVideo.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CAMediaTimingFunction.h>
#import <QuartzCore/CARenderer.h>
#import "CALayerInternal.h"

NSString *const kCARendererColorSpace = @"kCARendererColorSpace";

@implementation CARenderer

- (CGRect) bounds {
    return _bounds;
}

- (void) setBounds: (CGRect) value {
    _bounds = value;
}

@synthesize layer = _rootLayer;

- initWithCGLContext: (void *) cglContext options: (NSDictionary *) options {
    _cglContext = cglContext;
    _bounds = CGRectZero;
    _rootLayer = nil;
    return self;
}

+ (CARenderer *) rendererWithCGLContext: (void *) cglContext
                                options: (NSDictionary *) options
{
    return [[[self alloc] initWithCGLContext: cglContext
                                     options: options] autorelease];
}

static void startAnimationsInLayer(CALayer *layer, CFTimeInterval currentTime) {
    NSArray *keys = [layer animationKeys];

    for (NSString *key in keys) {
        CAAnimation *check = [layer animationForKey: key];

        if ([check beginTime] == 0.0)
            [check setBeginTime: currentTime];
        if (currentTime > [check beginTime] + [check duration]) {
            [layer removeAnimationForKey: key];
        }
    }

    for (CALayer *child in layer.sublayers)
        startAnimationsInLayer(child, currentTime);
}

- (void) beginFrameAtTime: (CFTimeInterval) currentTime
                timeStamp: (CVTimeStamp *) timeStamp
{
    startAnimationsInLayer(_rootLayer, currentTime);
}

static inline CGFloat cubed(CGFloat value) {
    return value * value * value;
}

static inline CGFloat squared(CGFloat value) {
    return value * value;
}

static CGFloat applyMediaTimingFunction(CAMediaTimingFunction *function,
                                        CGFloat t)
{
    CGFloat result;
    CGFloat cp1[2];
    CGFloat cp2[2];

    [function getControlPointAtIndex: 1 values: cp1];
    [function getControlPointAtIndex: 2 values: cp2];

    double x = cubed(1.0 - t) * 0.0 + 3 * squared(1 - t) * t * cp1[0] +
               3 * (1 - t) * squared(t) * cp2[0] + cubed(t) * 1.0;
    double y = cubed(1.0 - t) * 0.0 + 3 * squared(1 - t) * t * cp1[1] +
               3 * (1 - t) * squared(t) * cp2[1] + cubed(t) * 1.0;

    // this is wrong
    return y;
}

static CGFloat mediaTimingScale(CAAnimation *animation,
                                CFTimeInterval currentTime)
{
    CFTimeInterval begin = [animation beginTime];
    CFTimeInterval duration = [animation duration];
    // beginTime is set by the first animation frame; a render before that
    // (e.g. from a view display) shows the start value. Clamp so a late render
    // can't extrapolate far past the end value.
    if (begin <= 0)
        return 0;
    if (duration <= 0)
        return 1;

    CFTimeInterval delta = currentTime - begin;
    double zeroToOne = MIN(MAX(delta / duration, 0.0), 1.0);
    CAMediaTimingFunction *function = [animation timingFunction];

    if (function == nil)
        function = [CAMediaTimingFunction
                functionWithName: kCAMediaTimingFunctionDefault];

    return applyMediaTimingFunction(function, zeroToOne);
}

static CGFloat interpolateFloatInLayerKey(CALayer *layer, NSString *key,
                                          CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil)
        return [[layer valueForKey: key] floatValue];

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGFloat fromFloat = [fromValue floatValue];
        CGFloat toFloat = [toValue floatValue];

        CGFloat resultFloat;
        double timingScale = mediaTimingScale(animation, currentTime);

        resultFloat = fromFloat + (toFloat - fromFloat) * timingScale;

        return resultFloat;
    }

    return 0;
}

static CGPoint interpolatePointInLayerKey(CALayer *layer, NSString *key,
                                          CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil)
        return [[layer valueForKey: key] pointValue];

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGPoint fromPoint = [fromValue pointValue];
        CGPoint toPoint = [toValue pointValue];

        CGPoint resultPoint;
        double timingScale = mediaTimingScale(animation, currentTime);

        resultPoint.x = fromPoint.x + (toPoint.x - fromPoint.x) * timingScale;
        resultPoint.y = fromPoint.y + (toPoint.y - fromPoint.y) * timingScale;

        return resultPoint;
    }

    return CGPointMake(0, 0);
}

static CGRect interpolateRectInLayerKey(CALayer *layer, NSString *key,
                                        CFTimeInterval currentTime)
{
    CAAnimation *animation = [layer animationForKey: key];

    if (animation == nil) {
        return [[layer valueForKey: key] rectValue];
    }

    if ([animation isKindOfClass: [CABasicAnimation class]]) {
        CABasicAnimation *basic = (CABasicAnimation *) animation;

        id fromValue = [basic fromValue];
        id toValue = [basic toValue];

        if (toValue == nil)
            toValue = [layer valueForKey: key];

        CGRect fromRect = [fromValue rectValue];
        CGRect toRect = [toValue rectValue];

        double timingScale = mediaTimingScale(animation, currentTime);

        CGRect resultRect;

        resultRect.origin.x =
                fromRect.origin.x +
                (toRect.origin.x - fromRect.origin.x) * timingScale;
        resultRect.origin.y =
                fromRect.origin.y +
                (toRect.origin.y - fromRect.origin.y) * timingScale;
        resultRect.size.width =
                fromRect.size.width +
                (toRect.size.width - fromRect.size.width) * timingScale;
        resultRect.size.height =
                fromRect.size.height +
                (toRect.size.height - fromRect.size.height) * timingScale;

        return resultRect;
    }

    return CGRectMake(0, 0, 0, 0);
}

static GLint interpolationFromName(NSString *name) {
    if (name == kCAFilterLinear)
        return GL_LINEAR;
    else if (name == kCAFilterNearest)
        return GL_NEAREST;
    else if ([name isEqualToString: kCAFilterLinear])
        return GL_LINEAR;
    else if ([name isEqualToString: kCAFilterNearest])
        return GL_NEAREST;
    else
        return GL_LINEAR;
}

void CATexImage2DCGImage(CGImageRef image) {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);

    CGDataProviderRef provider = CGImageGetDataProvider(image);
    CFDataRef data = CGDataProviderCopyData(provider);
    const uint8_t *pixelBytes = CFDataGetBytePtr(data);

    GLenum glFormat = GL_BGRA;
    GLenum glType = GL_UNSIGNED_INT_8_8_8_8_REV;

    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
    CGBitmapInfo byteOrder = bitmapInfo & kCGBitmapByteOrderMask;

    switch (alphaInfo) {

    case kCGImageAlphaNone:
        break;

    case kCGImageAlphaPremultipliedLast:
        if (byteOrder == kO2BitmapByteOrder32Big) {
            glFormat = GL_RGBA;
            glType = GL_UNSIGNED_INT_8_8_8_8_REV;
        }
        break;

    case kCGImageAlphaPremultipliedFirst: // ARGB
        if (byteOrder == kCGBitmapByteOrder32Little) {
            glFormat = GL_BGRA;
            glType = GL_UNSIGNED_INT_8_8_8_8_REV;
        }
        break;

    case kCGImageAlphaLast:
        break;

    case kCGImageAlphaFirst:
        break;

    case kCGImageAlphaNoneSkipLast:
        break;

    case kCGImageAlphaNoneSkipFirst:
        break;

    case kCGImageAlphaOnly:
        break;
    }

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, imageWidth, imageHeight, 0,
                 glFormat, glType, pixelBytes);
}

// Premultiplied colour (the blend function is GL_ONE, GL_ONE_MINUS_SRC_ALPHA).
static BOOL setPremultipliedColor(CGColorRef color, CGFloat opacity) {
    if (color == NULL)
        return NO;

    size_t count = CGColorGetNumberOfComponents(color);
    const CGFloat *c = CGColorGetComponents(color);
    CGColorSpaceModel model =
            CGColorSpaceGetModel(CGColorGetColorSpace(color));
    CGFloat r, g, b, a;

    if (c == NULL)
        return NO;
    // Only RGB and grey components can be used as they are; a CMYK colour also
    // has 4+ components, which must not be read as RGBA.
    if (model == kCGColorSpaceModelRGB && count >= 4) {
        r = c[0]; g = c[1]; b = c[2]; a = c[3];
    } else if (model == kCGColorSpaceModelRGB && count == 3) {
        r = c[0]; g = c[1]; b = c[2]; a = 1;
    } else if (model == kCGColorSpaceModelMonochrome && count >= 2) {
        r = g = b = c[0]; a = c[1];
    } else {
        return NO;
    }

    a *= opacity;
    if (a <= 0)
        return NO;
    glColor4f(r * a, g * a, b * a, a);
    return YES;
}

enum { kCornerSegments = 8, kRoundedRectPoints = 4 * (kCornerSegments + 1) };

// Outline of a rounded rect, counter-clockwise from the bottom-right corner.
// Always kRoundedRectPoints points (a zero radius repeats the corner), so an
// outer and an inner outline can be zipped into a border triangle strip.
static void roundedRectOutline(CGRect r, CGFloat radius, GLfloat *xy) {
    radius = MAX(0, MIN(radius, MIN(r.size.width, r.size.height) / 2));

    const CGFloat cx[4] = {CGRectGetMaxX(r) - radius, CGRectGetMaxX(r) - radius,
                           CGRectGetMinX(r) + radius, CGRectGetMinX(r) + radius};
    const CGFloat cy[4] = {CGRectGetMinY(r) + radius, CGRectGetMaxY(r) - radius,
                           CGRectGetMaxY(r) - radius, CGRectGetMinY(r) + radius};
    int n = 0;

    for (int corner = 0; corner < 4; corner++) {
        CGFloat start = (corner - 1) * M_PI_2;
        for (int i = 0; i <= kCornerSegments; i++) {
            CGFloat angle = start + M_PI_2 * i / kCornerSegments;
            xy[n++] = cx[corner] + radius * cos(angle);
            xy[n++] = cy[corner] + radius * sin(angle);
        }
    }
}

- (void) _drawBackgroundOfLayer: (CALayer *) layer
                         bounds: (CGRect) bounds
                        opacity: (CGFloat) opacity
{
    if (!setPremultipliedColor(layer.backgroundColor, opacity))
        return;

    GLfloat fan[2 * (kRoundedRectPoints + 2)];
    CGRect rect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    fan[0] = CGRectGetMidX(rect);
    fan[1] = CGRectGetMidY(rect);
    roundedRectOutline(rect, layer.cornerRadius, fan + 2);
    fan[2 * (kRoundedRectPoints + 1)] = fan[2];
    fan[2 * (kRoundedRectPoints + 1) + 1] = fan[3];

    glVertexPointer(2, GL_FLOAT, 0, fan);
    glDrawArrays(GL_TRIANGLE_FAN, 0, kRoundedRectPoints + 2);
}

- (void) _drawBorderOfLayer: (CALayer *) layer
                     bounds: (CGRect) bounds
                    opacity: (CGFloat) opacity
{
    CGFloat width = layer.borderWidth;

    if (width <= 0 || !setPremultipliedColor(layer.borderColor, opacity))
        return;

    CGRect outerRect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    CGRect innerRect = CGRectInset(outerRect, width, width);
    if (innerRect.size.width < 0 || innerRect.size.height < 0)
        innerRect = CGRectMake(CGRectGetMidX(outerRect), CGRectGetMidY(outerRect), 0, 0);

    GLfloat outer[2 * kRoundedRectPoints], inner[2 * kRoundedRectPoints];
    GLfloat strip[2 * 2 * (kRoundedRectPoints + 1)];

    roundedRectOutline(outerRect, layer.cornerRadius, outer);
    roundedRectOutline(innerRect, MAX(0, layer.cornerRadius - width), inner);

    for (int i = 0; i <= kRoundedRectPoints; i++) {
        int j = i % kRoundedRectPoints;
        strip[4 * i] = outer[2 * j];
        strip[4 * i + 1] = outer[2 * j + 1];
        strip[4 * i + 2] = inner[2 * j];
        strip[4 * i + 3] = inner[2 * j + 1];
    }

    glVertexPointer(2, GL_FLOAT, 0, strip);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 2 * (kRoundedRectPoints + 1));
}

- (void) _drawContentsOfLayer: (CALayer *) layer
                       bounds: (CGRect) bounds
                      opacity: (CGFloat) opacity
{
    CGImageRef image = (CGImageRef) layer.contents;

    if (image == NULL)
        return;

    NSNumber *textureId = [layer _textureId];
    GLuint texture = [textureId unsignedIntValue];

    // Upload when the texture object doesn't exist yet (check before binding:
    // glBindTexture creates it) or when the layer got new contents since the
    // last upload (a layer-backed NSView sets a new image on every display).
    BOOL upload = texture == 0 || glIsTexture(texture) == GL_FALSE ||
                  [layer _textureContents] != layer.contents;

    glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);

    if (texture != 0)
        glBindTexture(GL_TEXTURE_2D, texture);

    if (upload) {
        CATexImage2DCGImage(image);
        [layer _setTextureContents: layer.contents];

        GLint minFilter = interpolationFromName(layer.minificationFilter);
        GLint magFilter = interpolationFromName(layer.magnificationFilter);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    }

    const GLfloat textureVertices[4 * 2] = {0, 1, 1, 1, 0, 0, 1, 0};
    const GLfloat vertices[4 * 2] = {0, 0, bounds.size.width, 0,
                                     0, bounds.size.height,
                                     bounds.size.width, bounds.size.height};

    glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(opacity, opacity, opacity, opacity);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);
}

// Layers are composited in painter's order: a layer's background, contents and
// border, then its sublayers in array order. Opacity multiplies down the tree.
- (void) _renderLayer: (CALayer *) layer
          currentTime: (CFTimeInterval) currentTime
        parentOpacity: (CGFloat) parentOpacity
{
    if (layer.hidden)
        return;

    CGPoint anchorPoint =
            interpolatePointInLayerKey(layer, @"anchorPoint", currentTime);
    CGPoint position =
            interpolatePointInLayerKey(layer, @"position", currentTime);
    CGRect bounds = interpolateRectInLayerKey(layer, @"bounds", currentTime);
    CGFloat opacity =
            interpolateFloatInLayerKey(layer, @"opacity", currentTime) *
            parentOpacity;

    if (opacity <= 0)
        return;

    glPushMatrix();
    glTranslatef(position.x - (bounds.size.width * anchorPoint.x),
                 position.y - (bounds.size.height * anchorPoint.y), 0);

    [self _drawBackgroundOfLayer: layer bounds: bounds opacity: opacity];
    [self _drawContentsOfLayer: layer bounds: bounds opacity: opacity];
    [self _drawBorderOfLayer: layer bounds: bounds opacity: opacity];

    for (CALayer *child in layer.sublayers)
        [self _renderLayer: child
                currentTime: currentTime
              parentOpacity: opacity];

    glPopMatrix();
}

// Layers that draw their content (-drawInContext:, CATextLayer, CAShapeLayer,
// a drawing delegate) produce it when marked as needing display. This runs
// before any GL drawing: a delegate's -displayLayer: can run arbitrary code (an
// NSView delegate redisplays the view, which renders this layer tree again), and
// doing that in the middle of the traversal would clear the frame and reset the
// matrix stack under it.
static void displayLayerTreeIfNeeded(CALayer *layer) {
    if (layer.hidden)
        return;

    [layer displayIfNeeded];

    // Copied: drawing code may add or remove sublayers.
    NSArray *sublayers = [layer.sublayers copy];
    for (CALayer *child in sublayers)
        displayLayerTreeIfNeeded(child);
    [sublayers release];
}

- (void) render {
    displayLayerTreeIfNeeded(_rootLayer);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // Painter's order instead of depth testing: every layer used to get z+1,
    // which put layers nested two or more deep outside the [-1, 1] depth range
    // of CALayerContext's glOrtho projection, so they were clipped away.
    glDisable(GL_DEPTH_TEST);

    glEnableClientState(GL_VERTEX_ARRAY);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    glAlphaFunc(GL_GREATER, 0);
    glEnable(GL_ALPHA_TEST);

    [self _renderLayer: _rootLayer
            currentTime: CACurrentMediaTime()
          parentOpacity: 1.0];

    glFlush();
}

- (void) endFrame {
}

@end
