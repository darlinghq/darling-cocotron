#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/OpenGL.h>
#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/CAMediaTimingFunction.h>
#import <QuartzCore/CARenderer.h>
#import <QuartzCore/CATransformLayer.h>
#import <QuartzCore/CASpringAnimation.h>
#import "CALayerInternal.h"

#include <math.h>
#include <string.h>

@interface CASpringAnimation (Private)
- (CGFloat) _springProgressAtTime: (CFTimeInterval) t;
@end

@interface CAMediaTimingFunction (Private)
- (float) _solveForInput: (float) input;
@end

NSString *const kCARendererColorSpace = @"kCARendererColorSpace";

@implementation CARenderer

- (CGRect) bounds {
    return NS_EXTRA(CARenderer, self)->_bounds;
}

- (void) setBounds: (CGRect) value {
    NS_EXTRA(CARenderer, self)->_bounds = value;
}

NS_EXTRA_SYNTHESIZE_RETAIN(CARenderer, layer, _rootLayer, CALayer *, layer, setLayer:)

- (void) _setClearsToTransparent: (BOOL) value {
    NS_EXTRA(CARenderer, self)->_clearsToTransparent = value;
}

- (void) _setBackdropImage: (CGImageRef) image {
    if (image != NULL)
        CGImageRetain(image);
    CGImageRelease(NS_EXTRA(CARenderer, self)->_backdropImage);
    NS_EXTRA(CARenderer, self)->_backdropImage = image;
}

- (void) dealloc {
    // The texture goes with the GL context, which may not be current here.
    CGImageRelease(NS_EXTRA(CARenderer, self)->_backdropImage);
    NS_EXTRA_FREE(CARenderer, self);
    [super dealloc];
}

// Draws the backdrop over the whole drawable, in clip coordinates.
- (void) _drawBackdrop {
    if (NS_EXTRA(CARenderer, self)->_backdropImage == NULL)
        return;
    if (NS_EXTRA(CARenderer, self)->_backdropTexture == 0)
        glGenTextures(1, &NS_EXTRA(CARenderer, self)->_backdropTexture);

    glEnable(GL_TEXTURE_2D);
    glBindTexture(GL_TEXTURE_2D, NS_EXTRA(CARenderer, self)->_backdropTexture);
    CATexImage2DCGImage(NS_EXTRA(CARenderer, self)->_backdropImage);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);

    // Texture row 0 is the top of the image, which is the top of the drawable.
    static const GLfloat texture[4 * 2] = {0, 1, 1, 1, 0, 0, 1, 0};
    static const GLfloat vertices[4 * 2] = {-1, -1, 1, -1, -1, 1, 1, 1};

    glMatrixMode(GL_PROJECTION);
    glPushMatrix();
    glLoadIdentity();
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glTexCoordPointer(2, GL_FLOAT, 0, texture);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(1, 1, 1, 1);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);
    glPopMatrix();
}

- initWithCGLContext: (void *) cglContext options: (NSDictionary *) options {
    NS_EXTRA(CARenderer, self)->_cglContext = cglContext;
    NS_EXTRA(CARenderer, self)->_bounds = CGRectZero;
    NS_EXTRA(CARenderer, self)->_rootLayer = nil;
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
    startAnimationsInLayer(NS_EXTRA(CARenderer, self)->_rootLayer, currentTime);
}

static CGFloat applyMediaTimingFunction(CAMediaTimingFunction *function,
                                        CGFloat t)
{
    return [function _solveForInput: t];
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
    if ([animation isKindOfClass: [CASpringAnimation class]])
        return [(CASpringAnimation *) animation
                _springProgressAtTime: MIN(MAX(delta, 0.0), duration)];

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

static void applyLayerTransform(CATransform3D t) {
    // CATransform3D uses row vectors. OpenGL consumes column-major storage,
    // so this field order represents the same point transformation there.
    const GLfloat matrix[16] = {
        t.m11, t.m12, t.m13, t.m14,
        t.m21, t.m22, t.m23, t.m24,
        t.m31, t.m32, t.m33, t.m34,
        t.m41, t.m42, t.m43, t.m44,
    };
    glMultMatrixf(matrix);
}

// Applies a layer's sublayer transform about its anchor point. The matrix has
// the layer's bounds corner at the origin, so the anchor point is at
// anchorPoint * size.
static void applySublayerTransform(CATransform3D t, CGPoint anchorPoint,
                                   CGRect bounds)
{
    if (CATransform3DIsIdentity(t))
        return;
    CGFloat ax = bounds.size.width * anchorPoint.x;
    CGFloat ay = bounds.size.height * anchorPoint.y;
    glTranslatef(ax, ay, 0);
    applyLayerTransform(t);
    glTranslatef(-ax, -ay, 0);
}

// Specifies the bound texture as a single transparent pixel, for contents
// that have no pixels to upload, so that nothing stale is drawn.
static void texImage2DTransparent(void) {
    static const uint8_t transparent[4] = {0, 0, 0, 0};

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, transparent);
}

void CATexImage2DCGImage(CGImageRef image) {
    CGDataProviderRef provider = image ? CGImageGetDataProvider(image) : NULL;
    CFDataRef data = provider ? CGDataProviderCopyData(provider) : NULL;
    const uint8_t *pixelBytes = data ? CFDataGetBytePtr(data) : NULL;
    size_t imageWidth = image ? CGImageGetWidth(image) : 0;
    size_t imageHeight = image ? CGImageGetHeight(image) : 0;

    if (pixelBytes == NULL || imageWidth == 0 || imageHeight == 0) {
        if (data != NULL)
            CFRelease(data);
        texImage2DTransparent();
        return;
    }

    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(image);

    GLenum glFormat = GL_BGRA;
    GLenum glType = GL_UNSIGNED_INT_8_8_8_8_REV;

    CGImageAlphaInfo alphaInfo = bitmapInfo & kCGBitmapAlphaInfoMask;
    CGBitmapInfo byteOrder = bitmapInfo & kCGBitmapByteOrderMask;

    switch (alphaInfo) {

    case kCGImageAlphaNone:
        break;

    case kCGImageAlphaPremultipliedLast:
        // Without an explicit byte order the samples are R, G, B, A in memory
        if (byteOrder == kCGBitmapByteOrderDefault ||
            byteOrder == kO2BitmapByteOrder32Big) {
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
    CFRelease(data);
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
    } else if (model == kCGColorSpaceModelCMYK && count >= 5) {
        // Match Onyx2D's device-CMYK approximation; this is not ICC matching.
        O2Float rgb[4];
        if (!O2ColorConvertComponentsToDeviceRGB(
                (O2ColorSpaceRef)CGColorGetColorSpace(color), c, rgb))
            return NO;
        r = rgb[0]; g = rgb[1]; b = rgb[2]; a = rgb[3];
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

// Specifies the bound texture from the surface's pixels. Only the 32-bit
// formats that map directly onto a GL format are drawn; other surfaces are
// drawn transparent. Returns the seed the uploaded pixels have.
static uint32_t texImage2DIOSurface(CGLContextObj context,
                                    IOSurfaceRef surface)
{
    GLenum format, type;

    switch (IOSurfaceGetPixelFormat(surface)) {
    case 'BGRA':
        format = GL_BGRA;
        type = GL_UNSIGNED_INT_8_8_8_8_REV;
        break;
    case 'RGBA':
        format = GL_RGBA;
        type = GL_UNSIGNED_BYTE;
        break;
    default:
        texImage2DTransparent();
        return IOSurfaceGetSeed(surface);
    }

    // Keep writers out while the pixels are copied into the texture.
    uint32_t seed = 0;
    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, &seed);
    CGLError error = CGLTexImageIOSurface2D(
            context, GL_TEXTURE_2D, GL_RGBA8,
            (GLsizei) IOSurfaceGetWidth(surface),
            (GLsizei) IOSurfaceGetHeight(surface), format, type, surface, 0);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);

    if (error != kCGLNoError)
        texImage2DTransparent();
    return seed;
}

// Where the selected part of the contents goes in rect (the layer's bounds,
// relative to their corner, in the layer's own orientation: y = 0 is the
// bounds origin, which is the bottom on screen unless the layer is flipped).
// size is the part's size in points. The gravity names refer to the layer's
// coordinates, so "top" is the maxY edge, which a flipped layer shows at the
// bottom of the screen.
static CGRect contentsRectForGravity(NSString *gravity, CGRect rect, CGSize size) {
    if (gravity == nil || [gravity isEqualToString: kCAGravityResize] ||
        size.width <= 0 || size.height <= 0)
        return rect;

    if ([gravity isEqualToString: kCAGravityResizeAspect] ||
        [gravity isEqualToString: kCAGravityResizeAspectFill]) {
        CGFloat sx = rect.size.width / size.width;
        CGFloat sy = rect.size.height / size.height;
        CGFloat scale = [gravity isEqualToString: kCAGravityResizeAspect] ? MIN(sx, sy) : MAX(sx, sy);
        size = CGSizeMake(size.width * scale, size.height * scale);
        return CGRectMake(CGRectGetMidX(rect) - size.width / 2,
                          CGRectGetMidY(rect) - size.height / 2, size.width,
                          size.height);
    }

    BOOL left = [gravity isEqualToString: kCAGravityLeft] ||
                [gravity isEqualToString: kCAGravityTopLeft] ||
                [gravity isEqualToString: kCAGravityBottomLeft];
    BOOL right = [gravity isEqualToString: kCAGravityRight] ||
                 [gravity isEqualToString: kCAGravityTopRight] ||
                 [gravity isEqualToString: kCAGravityBottomRight];
    BOOL top = [gravity isEqualToString: kCAGravityTop] ||
               [gravity isEqualToString: kCAGravityTopLeft] ||
               [gravity isEqualToString: kCAGravityTopRight];
    BOOL bottom = [gravity isEqualToString: kCAGravityBottom] ||
                  [gravity isEqualToString: kCAGravityBottomLeft] ||
                  [gravity isEqualToString: kCAGravityBottomRight];

    // An unknown name is treated as the default, resize.
    if (!left && !right && !top && !bottom &&
        ![gravity isEqualToString: kCAGravityCenter])
        return rect;

    CGFloat x = left ? CGRectGetMinX(rect)
                     : right ? CGRectGetMaxX(rect) - size.width
                             : CGRectGetMidX(rect) - size.width / 2;
    CGFloat y = bottom ? CGRectGetMinY(rect)
                       : top ? CGRectGetMaxY(rect) - size.height
                             : CGRectGetMidY(rect) - size.height / 2;
    return CGRectMake(x, y, size.width, size.height);
}

- (void) _drawContentsOfLayer: (CALayer *) layer
                       bounds: (CGRect) bounds
                      opacity: (CGFloat) opacity
                      flipped: (BOOL) flipped
                       atTime: (CFTimeInterval) currentTime
{
    CGRect rect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    id contents = [layer _contentsForRendering: &rect];

    if (contents == nil)
        return;

    // Contents can be a CGImage or an IOSurface.
    IOSurfaceRef surface = NULL;
    if (CFGetTypeID((CFTypeRef) contents) == IOSurfaceGetTypeID())
        surface = (IOSurfaceRef) contents;

    NSNumber *textureId = [layer _textureId];
    GLuint texture = [textureId unsignedIntValue];

    // Upload when the texture object doesn't exist yet (check before binding:
    // glBindTexture creates it) or when the layer got new contents since the
    // last upload (a layer-backed NSView sets a new image on every display).
    // A surface is drawn by CPU or GPU code that keeps the same object, so
    // its pixels are uploaded again once its seed has moved on.
    BOOL upload = texture == 0 || glIsTexture(texture) == GL_FALSE ||
                  [layer _textureContents] != contents ||
                  (surface != NULL &&
                   IOSurfaceGetSeed(surface) != [layer _textureSeed]);

    glEnable(GL_TEXTURE_2D);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);

    if (texture != 0)
        glBindTexture(GL_TEXTURE_2D, texture);

    if (upload) {
        if (surface != NULL) {
            [layer _setTextureSeed: texImage2DIOSurface(NS_EXTRA(CARenderer, self)->_cglContext, surface)];
        } else {
            CATexImage2DCGImage((CGImageRef) contents);
        }
        [layer _setTextureContents: contents];

        GLint minFilter = interpolationFromName(layer.minificationFilter);
        GLint magFilter = interpolationFromName(layer.magnificationFilter);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, minFilter);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, magFilter);

        // Parts of contentsRect outside the unit square show the edge
        // pixels, extended outwards (as the contentsRect documentation says).
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }

    // The part of the contents to show, in the unit coordinates of the
    // contents. Its y = 0 is the image edge at the layer's bounds origin:
    // the bottom of the image, or its top when the layer's coordinate space
    // is flipped on screen. The image itself stays upright.
    CGRect part = interpolateRectInLayerKey(layer, @"contentsRect", currentTime);

    size_t pixelsWide = surface != NULL ? IOSurfaceGetWidth(surface)
                                        : CGImageGetWidth((CGImageRef) contents);
    size_t pixelsHigh = surface != NULL ? IOSurfaceGetHeight(surface)
                                        : CGImageGetHeight((CGImageRef) contents);
    CGFloat scale = layer.contentsScale > 0 ? layer.contentsScale : 1;
    CGSize partSize = CGSizeMake(fabs(part.size.width) * pixelsWide / scale,
                                 fabs(part.size.height) * pixelsHigh / scale);
    rect = contentsRectForGravity(layer.contentsGravity, rect, partSize);

    // Texture row 0 (t = 0) is the top of the image.
    const GLfloat s0 = CGRectGetMinX(part), s1 = CGRectGetMaxX(part);
    GLfloat tBottom, tTop;
    if (flipped) {
        tBottom = CGRectGetMinY(part);
        tTop = CGRectGetMaxY(part);
    } else {
        tBottom = 1 - CGRectGetMinY(part);
        tTop = 1 - CGRectGetMaxY(part);
    }
    const GLfloat textureVertices[4 * 2] = {s0, tBottom, s1, tBottom,
                                            s0, tTop, s1, tTop};
    const GLfloat left = CGRectGetMinX(rect), right = CGRectGetMaxX(rect);
    const GLfloat bottom = CGRectGetMinY(rect), top = CGRectGetMaxY(rect);
    const GLfloat vertices[4 * 2] = {left, bottom, right, bottom,
                                     left, top, right, top};

    glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(opacity, opacity, opacity, opacity);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    glDisable(GL_TEXTURE_2D);
}

// The clip that masking layers (masksToBounds) set up for their contents and
// sublayers. A layer whose bounds are an axis-aligned rectangle on the
// drawable narrows the scissor box. Otherwise its bounds are clipped with
// four user clip planes, which work whatever buffers the drawable has; when
// the planes run out, the scissor box around its bounds is used instead.
// Nested clips intersect.
typedef struct {
    BOOL scissor;
    GLint box[4];
    GLint planes;
    GLint maxPlanes;
} CARendererClip;

static BOOL windowPoint(const GLdouble *m, const GLdouble *p, const GLint *viewport,
                        GLdouble x, GLdouble y, GLdouble out[2])
{
    GLdouble eye[4], clip[4];
    for (int i = 0; i < 4; i++)
        eye[i] = m[i] * x + m[4 + i] * y + m[12 + i];
    for (int i = 0; i < 4; i++)
        clip[i] = p[i] * eye[0] + p[4 + i] * eye[1] + p[8 + i] * eye[2] + p[12 + i] * eye[3];
    if (!(clip[3] > 0))
        return NO;
    out[0] = viewport[0] + (clip[0] / clip[3] + 1) * viewport[2] / 2;
    out[1] = viewport[1] + (clip[1] / clip[3] + 1) * viewport[3] / 2;
    return YES;
}

static void intersectScissor(CARendererClip *clip, GLdouble minX, GLdouble minY,
                             GLdouble maxX, GLdouble maxY)
{
    GLint x0 = (GLint) floor(minX + 0.5), y0 = (GLint) floor(minY + 0.5);
    GLint x1 = (GLint) floor(maxX + 0.5), y1 = (GLint) floor(maxY + 0.5);
    if (clip->scissor) {
        x0 = MAX(x0, clip->box[0]);
        y0 = MAX(y0, clip->box[1]);
        x1 = MIN(x1, clip->box[0] + clip->box[2]);
        y1 = MIN(y1, clip->box[1] + clip->box[3]);
    }
    clip->scissor = YES;
    clip->box[0] = x0;
    clip->box[1] = y0;
    clip->box[2] = MAX(x1 - x0, 0);
    clip->box[3] = MAX(y1 - y0, 0);
    glEnable(GL_SCISSOR_TEST);
    glScissor(clip->box[0], clip->box[1], clip->box[2], clip->box[3]);
}

// Clips to (0, 0, width, height) of the current modelview coordinates.
static void pushBoundsClip(CARendererClip *clip, CGFloat width, CGFloat height)
{
    GLdouble m[16], p[16];
    GLint viewport[4];
    glGetDoublev(GL_MODELVIEW_MATRIX, m);
    glGetDoublev(GL_PROJECTION_MATRIX, p);
    glGetIntegerv(GL_VIEWPORT, viewport);

    GLdouble corners[4][2];
    BOOL inFront = windowPoint(m, p, viewport, 0, 0, corners[0]) &&
                   windowPoint(m, p, viewport, width, 0, corners[1]) &&
                   windowPoint(m, p, viewport, 0, height, corners[2]) &&
                   windowPoint(m, p, viewport, width, height, corners[3]);

    if (inFront) {
        GLdouble minX = INFINITY, minY = INFINITY, maxX = -INFINITY, maxY = -INFINITY;
        for (int i = 0; i < 4; i++) {
            minX = MIN(minX, corners[i][0]);
            maxX = MAX(maxX, corners[i][0]);
            minY = MIN(minY, corners[i][1]);
            maxY = MAX(maxY, corners[i][1]);
        }
        // The edges from corner 0 run along the window's axes (in either
        // order) and the far corner closes the rectangle.
        const GLdouble e = 1.0 / 64;
        GLdouble ux = corners[1][0] - corners[0][0], uy = corners[1][1] - corners[0][1];
        GLdouble vx = corners[2][0] - corners[0][0], vy = corners[2][1] - corners[0][1];
        BOOL aligned = ((fabs(uy) < e && fabs(vx) < e) || (fabs(ux) < e && fabs(vy) < e)) &&
                       fabs(corners[3][0] - (corners[0][0] + ux + vx)) < e &&
                       fabs(corners[3][1] - (corners[0][1] + uy + vy)) < e;
        intersectScissor(clip, minX, minY, maxX, maxY);
        if (aligned)
            return;
    }

    if (clip->planes + 4 > clip->maxPlanes)
        return;
    // ax + by + d >= 0 is kept; the planes are given in the current
    // modelview coordinates.
    const GLdouble equations[4][4] = {
        {1, 0, 0, 0},
        {-1, 0, 0, width},
        {0, 1, 0, 0},
        {0, -1, 0, height},
    };
    for (int i = 0; i < 4; i++) {
        glClipPlane(GL_CLIP_PLANE0 + clip->planes + i, equations[i]);
        glEnable(GL_CLIP_PLANE0 + clip->planes + i);
    }
    clip->planes += 4;
}

static void popClip(CARendererClip *clip, const CARendererClip *saved)
{
    for (GLint i = saved->planes; i < clip->planes; i++)
        glDisable(GL_CLIP_PLANE0 + i);
    if (saved->scissor) {
        glEnable(GL_SCISSOR_TEST);
        glScissor(saved->box[0], saved->box[1], saved->box[2], saved->box[3]);
    } else {
        glDisable(GL_SCISSOR_TEST);
    }
    *clip = *saved;
}

// Layers are composited in painter's order: a layer's background, contents and
// border, then its sublayers in array order. Opacity multiplies down the tree.
// parentFlipped says whether the parent's coordinate space is y-flipped on screen.
- (void) _renderLayer: (CALayer *) layer
          currentTime: (CFTimeInterval) currentTime
        parentOpacity: (CGFloat) parentOpacity
        parentFlipped: (BOOL) parentFlipped
                 clip: (CARendererClip *) clip
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
    // Position is the anchor in parent coordinates. Apply the layer transform
    // around it, then move local geometry so its anchor is at the origin.
    glTranslatef(position.x, position.y, 0);
    applyLayerTransform(layer.transform);
    glTranslatef(-bounds.size.width * anchorPoint.x,
                 -bounds.size.height * anchorPoint.y, 0);

    BOOL flipped = parentFlipped;
    if (layer.geometryFlipped) {
        glTranslatef(0, bounds.size.height, 0);
        glScalef(1, -1, 1);
        flipped = !flipped;
    }

    // A masking layer clips its contents and its sublayers to its bounds. A
    // transform layer renders only its sublayers and does not mask.
    BOOL isTransformLayer = [layer isKindOfClass: [CATransformLayer class]];
    BOOL masks = layer.masksToBounds && !isTransformLayer;
    CARendererClip saved = *clip;
    if (masks) {
        if (!(bounds.size.width > 0 && bounds.size.height > 0)) {
            glPopMatrix();
            return;
        }
        pushBoundsClip(clip, bounds.size.width, bounds.size.height);
    }

    if (!isTransformLayer) {
        [self _drawBackgroundOfLayer: layer bounds: bounds opacity: opacity];

        // A layer that draws its own content (CAMetalLayer draws the texture the GPU
        // filled in) opts out of the contents path, which would otherwise upload
        // into the same texture it just drew from.
        if (![layer _drawLayerContents: bounds opacity: opacity])
            [self _drawContentsOfLayer: layer
                                bounds: bounds
                               opacity: opacity
                               flipped: flipped
                                atTime: currentTime];

        [self _drawBorderOfLayer: layer bounds: bounds opacity: opacity];
    }

    // A child is positioned in this layer's coordinate system, whose origin is
    // bounds.origin, so it belongs that much further left and down than the matrix above
    // puts it. Only the recursion is offset: this layer's own contents already have the
    // origin removed from their image, so translating them too would double-count it.
    // The sublayer transform applies about the anchor point, in the layer's own
    // (possibly flipped) coordinates.
    glPushMatrix();
    applySublayerTransform(layer.sublayerTransform, anchorPoint, bounds);
    glTranslatef(-bounds.origin.x, -bounds.origin.y, 0);
    for (CALayer *child in layer.sublayers)
        [self _renderLayer: child
                currentTime: currentTime
              parentOpacity: opacity
              parentFlipped: flipped
                       clip: clip];
    glPopMatrix();

    if (masks)
        popClip(clip, &saved);

    glPopMatrix();
}

// Maps a point of the layer's own coordinates (bounds origin removed, as its
// background and contents are drawn) into its superlayer's coordinates, the way
// the matrix in -_renderLayer: does.
static CATransform3D layerToSuperlayer(CGPoint position, CGPoint anchorPoint,
                                       CGRect bounds, CATransform3D transform,
                                       BOOL geometryFlipped)
{
    CATransform3D m = CATransform3DIdentity;
    if (geometryFlipped)
        m = CATransform3DConcat(
                CATransform3DMakeScale(1, -1, 1),
                CATransform3DMakeTranslation(0, bounds.size.height, 0));
    m = CATransform3DConcat(
            m, CATransform3DMakeTranslation(-bounds.size.width * anchorPoint.x,
                                            -bounds.size.height * anchorPoint.y,
                                            0));
    m = CATransform3DConcat(m, transform);
    return CATransform3DConcat(
            m, CATransform3DMakeTranslation(position.x, position.y, 0));
}

// The bounding box of rect under m (CATransform3D maps row vectors), or
// CGRectNull when no corner lies in front of the viewer.
static CGRect boundingBoxOfTransformedRect(CGRect rect, CATransform3D m) {
    const CGFloat xs[2] = {CGRectGetMinX(rect), CGRectGetMaxX(rect)};
    const CGFloat ys[2] = {CGRectGetMinY(rect), CGRectGetMaxY(rect)};
    CGFloat minX = INFINITY, minY = INFINITY, maxX = -INFINITY, maxY = -INFINITY;

    for (int i = 0; i < 4; i++) {
        CGFloat x = xs[i & 1], y = ys[i >> 1];
        CGFloat w = x * m.m14 + y * m.m24 + m.m44;
        if (!(w > 0))
            continue;
        CGFloat tx = (x * m.m11 + y * m.m21 + m.m41) / w;
        CGFloat ty = (x * m.m12 + y * m.m22 + m.m42) / w;
        minX = MIN(minX, tx);
        maxX = MAX(maxX, tx);
        minY = MIN(minY, ty);
        maxY = MAX(maxY, ty);
    }
    if (minX > maxX)
        return CGRectNull;
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

static CGRect unionOfRects(CGRect a, CGRect b) {
    if (CGRectIsNull(a))
        return b;
    if (CGRectIsNull(b))
        return a;
    CGFloat minX = MIN(CGRectGetMinX(a), CGRectGetMinX(b));
    CGFloat minY = MIN(CGRectGetMinY(a), CGRectGetMinY(b));
    CGFloat maxX = MAX(CGRectGetMaxX(a), CGRectGetMaxX(b));
    CGFloat maxY = MAX(CGRectGetMaxY(a), CGRectGetMaxY(b));
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

// What -_renderLayer: draws for the layer and its sublayers, in the
// coordinates superlayerToRoot maps from. *frame, when not NULL, gets the
// layer's own frame there.
static CGRect drawnExtentOfLayer(CALayer *layer, CATransform3D superlayerToRoot,
                                 CFTimeInterval currentTime, CGRect *frame)
{
    CGPoint anchorPoint =
            interpolatePointInLayerKey(layer, @"anchorPoint", currentTime);
    CGPoint position =
            interpolatePointInLayerKey(layer, @"position", currentTime);
    CGRect bounds = interpolateRectInLayerKey(layer, @"bounds", currentTime);
    CATransform3D toRoot = CATransform3DConcat(
            layerToSuperlayer(position, anchorPoint, bounds, layer.transform,
                              layer.geometryFlipped),
            superlayerToRoot);
    CGRect ownRect = CGRectMake(0, 0, bounds.size.width, bounds.size.height);
    CGRect ownFrame = boundingBoxOfTransformedRect(ownRect, toRoot);

    if (frame != NULL)
        *frame = ownFrame;

    if (layer.hidden ||
        interpolateFloatInLayerKey(layer, @"opacity", currentTime) <= 0)
        return CGRectNull;

    // A layer of zero area draws nothing itself, and a transform layer draws
    // only its sublayers.
    BOOL drawsItself = bounds.size.width > 0 && bounds.size.height > 0 &&
                       ![layer isKindOfClass: [CATransformLayer class]];
    CGRect extent = drawsItself ? ownFrame : CGRectNull;

    // The sublayers of a masking layer show only inside its bounds.
    if (layer.masksToBounds)
        return extent;

    // Sublayers are positioned relative to the bounds origin, and the
    // sublayer transform applies about the anchor point, as in -_renderLayer:.
    CATransform3D sublayers = CATransform3DMakeTranslation(-bounds.origin.x, -bounds.origin.y, 0);
    CATransform3D sublayerTransform = layer.sublayerTransform;
    if (!CATransform3DIsIdentity(sublayerTransform)) {
        CGFloat ax = bounds.size.width * anchorPoint.x;
        CGFloat ay = bounds.size.height * anchorPoint.y;
        sublayers = CATransform3DConcat(sublayers, CATransform3DMakeTranslation(-ax, -ay, 0));
        sublayers = CATransform3DConcat(sublayers, sublayerTransform);
        sublayers = CATransform3DConcat(sublayers, CATransform3DMakeTranslation(ax, ay, 0));
    }
    CATransform3D sublayersToRoot = CATransform3DConcat(sublayers, toRoot);
    for (CALayer *child in layer.sublayers)
        extent = unionOfRects(extent, drawnExtentOfLayer(child, sublayersToRoot,
                                                         currentTime, NULL));
    return extent;
}

- (CGRect) _drawnExtentOfLayerTree: (CALayer *) layer
                         rootFrame: (CGRect *) rootFrame
                            atTime: (CFTimeInterval) time
{
    if (rootFrame != NULL)
        *rootFrame = CGRectNull;
    if (layer == nil)
        return CGRectNull;
    return drawnExtentOfLayer(layer, CATransform3DIdentity, time, rootFrame);
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
    [NS_EXTRA(CARenderer, self)->_rootLayer layoutIfNeeded];
    displayLayerTreeIfNeeded(NS_EXTRA(CARenderer, self)->_rootLayer);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glClearColor(0, 0, 0, NS_EXTRA(CARenderer, self)->_clearsToTransparent ? 0 : 1);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    [self _drawBackdrop];

    // Painter's order instead of depth testing: every layer used to get z+1,
    // which put layers nested two or more deep outside the [-1, 1] depth range
    // of CALayerContext's glOrtho projection, so they were clipped away.
    glDisable(GL_DEPTH_TEST);

    glEnableClientState(GL_VERTEX_ARRAY);

    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

    glAlphaFunc(GL_GREATER, 0);
    glEnable(GL_ALPHA_TEST);

    // Masking layers narrow a scissor box the caller may already have set.
    CARendererClip clip = {NO, {0, 0, 0, 0}, 0, 0};
    GLboolean callerScissor = glIsEnabled(GL_SCISSOR_TEST);
    GLint callerBox[4];
    glGetIntegerv(GL_SCISSOR_BOX, callerBox);
    clip.scissor = callerScissor;
    memcpy(clip.box, callerBox, sizeof(callerBox));
    glGetIntegerv(GL_MAX_CLIP_PLANES, &clip.maxPlanes);

    [self _renderLayer: NS_EXTRA(CARenderer, self)->_rootLayer
            currentTime: CACurrentMediaTime()
          parentOpacity: 1.0
          parentFlipped: [NS_EXTRA(CARenderer, self)->_rootLayer.superlayer contentsAreFlipped]
                   clip: &clip];

    if (callerScissor)
        glScissor(callerBox[0], callerBox[1], callerBox[2], callerBox[3]);
    else
        glDisable(GL_SCISSOR_TEST);

    glFlush();
}

- (void) endFrame {
}

@end
