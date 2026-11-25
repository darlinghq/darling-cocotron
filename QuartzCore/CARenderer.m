#define GL_GLEXT_PROTOTYPES 1
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2Surface.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
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
    // The layer property is retain, so the renderer owns one reference.
    [NS_EXTRA(CARenderer, self)->_rootLayer release];
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

// Copies the first `knots` key times into times when they are usable: every one a
// number in [0,1] and none smaller than the one before (a NaN is not a number in
// range). Anything else is ignored, as documented for CAKeyframeAnimation.keyTimes.
static BOOL copyUsableKeyTimes(NSArray *keyTimes, NSUInteger knots,
                               double *times)
{
    if ([keyTimes count] < knots || knots < 2)
        return NO;

    double previous = 0;
    for (NSUInteger i = 0; i < knots; i++) {
        double time = [[keyTimes objectAtIndex: i] doubleValue];
        if (!(time >= previous && time <= 1))
            return NO;
        times[i] = previous = time;
    }
    return YES;
}

// The index of the span of knot times that progress falls in: the last knot at or
// before progress starts the span, the first span when there is none, and there
// are `spans` spans.
static NSUInteger spanAtProgress(const double *times, NSUInteger spans,
                                 double progress)
{
    NSUInteger index = 0;

    while (index + 1 < spans && times[index + 1] <= progress)
        index++;
    return index;
}

enum { StackKnots = 32 };

// The two values a keyframe animation is between at the given time and how far
// through that span it is. Linear, discrete and (for values with a distance)
// paced modes are covered. NO, so that the caller leaves the layer at its model
// value, for what is not: a path (the docs say values are then ignored), cubic
// modes, fewer than two values (an animation of one value shows nothing), and a
// paced animation of values without a distance.
//
// QUIRK: the documentation says little about key times that do not fit the values.
// Black-box observation of macOS 26.7.3 (tier 2): the key times are used as long as
// there are at least two numbers in [0,1] that never decrease, whatever the first and
// last are: before the first key time the first value is shown and after the last
// one the last value; with more key times than values, or fewer, only as many of the
// leading ones as there are knots are used (fewer than values: only the leading values
// take part); with no usable key times the knots are evenly spaced. A discrete
// animation takes one more key time than values, or just as many, in which case the
// last value is not reached before the end of the animation: the value of a span holds
// from its key time until the next.
// Test: the key time checks of tests/quartzcore-keyframe-animation-render.m
//
// GUESS: a paced animation ignores timingFunctions (the header says it ignores
// keyTimes and timingFunctions) but still gets the animation's own timingFunction.
static BOOL keyframeSpan(CAKeyframeAnimation *animation,
                         CFTimeInterval currentTime,
                         double (*distance)(id, id), id *from, id *to,
                         double *fraction)
{
    if ([animation path] != NULL)
        return NO;

    NSArray *values = [animation values];
    NSUInteger count = [values count];
    NSString *mode = [animation calculationMode];
    BOOL discrete = [mode isEqualToString: kCAAnimationDiscrete];
    BOOL paced = [mode isEqualToString: kCAAnimationPaced];

    if (count < 2 || (!discrete && !paced &&
                      ![mode isEqualToString: kCAAnimationLinear]))
        return NO;
    if (paced && distance == NULL)
        return NO;

    CFTimeInterval begin = [animation beginTime];
    CFTimeInterval duration = [animation duration];
    double progress = 0;
    // As for the basic animations, nothing has started before beginTime is set.
    if (begin > 0)
        progress = duration > 0
                ? MIN(MAX((currentTime - begin) / duration, 0.0), 1.0)
                : 1;
    // The animation's own timing function comes first, then the one of the span.
    if ([animation timingFunction] != nil)
        progress = applyMediaTimingFunction([animation timingFunction],
                                            progress);

    // Linear and paced animations have a knot per value, a discrete one a knot at the
    // start of every value and one at the end of the last.
    NSUInteger knots = discrete ? count + 1 : count;
    double stackTimes[StackKnots];
    double *times = knots <= StackKnots ? stackTimes
                                        : malloc(knots * sizeof(double));

    if (times == NULL)
        return NO;

    if (paced) {
        double total = 0;
        times[0] = 0;
        for (NSUInteger i = 1; i < count; i++) {
            total += distance([values objectAtIndex: i - 1],
                              [values objectAtIndex: i]);
            times[i] = total;
        }
        for (NSUInteger i = 1; i < count; i++)
            times[i] = total > 0 ? times[i] / total : (double) i / (count - 1);
    } else {
        NSArray *keyTimes = [animation keyTimes];
        NSUInteger given = [keyTimes count];
        NSUInteger used = MIN(given, knots);

        if (copyUsableKeyTimes(keyTimes, used, times)) {
            knots = used;
        } else {
            for (NSUInteger i = 0; i < knots; i++)
                times[i] = (double) i / (knots - 1);
        }
    }

    if (discrete) {
        // the value of a span holds from its key time until the next
        *from = *to = [values objectAtIndex: spanAtProgress(times, knots - 1, progress)];
        *fraction = 0;
    } else if (progress <= times[0]) {
        *from = *to = [values objectAtIndex: 0];
        *fraction = 0;
    } else if (progress >= times[knots - 1]) {
        *from = *to = [values objectAtIndex: knots - 1];
        *fraction = 0;
    } else {
        NSUInteger index = spanAtProgress(times, knots - 1, progress);
        double start = times[index], end = times[index + 1];
        double local = end > start ? (progress - start) / (end - start) : 1;
        NSArray *functions = paced ? nil : [animation timingFunctions];

        if (index < [functions count])
            local = applyMediaTimingFunction([functions objectAtIndex: index],
                                             local);
        *from = [values objectAtIndex: index];
        *to = [values objectAtIndex: index + 1];
        *fraction = local;
    }
    if (times != stackTimes)
        free(times);
    return YES;
}

static double floatDistance(id a, id b) {
    return fabs([b floatValue] - [a floatValue]);
}

static double pointDistance(id a, id b) {
    CGPoint pa = [a pointValue], pb = [b pointValue];
    return hypot(pb.x - pa.x, pb.y - pa.y);
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

    if ([animation isKindOfClass: [CAKeyframeAnimation class]]) {
        id from, to;
        double fraction;

        if (keyframeSpan((CAKeyframeAnimation *) animation, currentTime,
                         floatDistance, &from, &to, &fraction))
            return [from floatValue] +
                   ([to floatValue] - [from floatValue]) * fraction;
        // a keyframe animation this renderer does not interpolate
        return [[layer valueForKey: key] floatValue];
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

    if ([animation isKindOfClass: [CAKeyframeAnimation class]]) {
        id from, to;
        double fraction;

        if (keyframeSpan((CAKeyframeAnimation *) animation, currentTime,
                         pointDistance, &from, &to, &fraction)) {
            CGPoint a = [from pointValue], b = [to pointValue];
            return CGPointMake(a.x + (b.x - a.x) * fraction,
                               a.y + (b.y - a.y) * fraction);
        }
        // a keyframe animation this renderer does not interpolate
        return [[layer valueForKey: key] pointValue];
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

    if ([animation isKindOfClass: [CAKeyframeAnimation class]]) {
        id from, to;
        double fraction;

        if (keyframeSpan((CAKeyframeAnimation *) animation, currentTime, NULL,
                         &from, &to, &fraction)) {
            CGRect a = [from rectValue], b = [to rectValue];
            return CGRectMake(a.origin.x + (b.origin.x - a.origin.x) * fraction,
                              a.origin.y + (b.origin.y - a.origin.y) * fraction,
                              a.size.width + (b.size.width - a.size.width) * fraction,
                              a.size.height + (b.size.height - a.size.height) * fraction);
        }
        // a keyframe animation this renderer does not interpolate
        return [[layer valueForKey: key] rectValue];
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

// A circular corner is a quarter circle of the corner radius. A continuous
// corner is a smoother curve that departs from the straight edges further away
// (about 1.53 times the radius) and cuts a little more off the corner. It is
// drawn as the superellipse |x|^n + |y|^n = 1 over that extent.
static const CGFloat kContinuousCornerExtent = 1.5286;
static const CGFloat kContinuousCornerExponent = 3.5;

static BOOL hasContinuousCorners(CALayer *layer) {
    return [layer.cornerCurve isEqualToString: kCACornerCurveContinuous];
}

// The distance from a corner at which its curve meets the straight edges. The
// radius is limited so that the corners fit in the smaller side. The curves of
// continuous corners may overlap along a short side.
static CGFloat cornerExtent(CGFloat radius, CGSize size, BOOL continuous) {
    CGFloat half = MIN(size.width, size.height) / 2;
    radius = MAX(0, MIN(radius, half));
    return continuous ? radius * kContinuousCornerExtent : radius;
}

// Outline of a rounded rect, counter-clockwise from the bottom-right corner.
// Always kRoundedRectPoints points (a zero radius repeats the corner), so an
// outer and an inner outline can be zipped into a border triangle strip.
// Only the corners in `corners` are rounded.
static void roundedRectOutline(CGRect r, CGFloat radius, BOOL continuous,
                               CACornerMask corners, GLfloat *xy)
{
    // The outline cannot overlap itself, so its corners stop at the middle of the sides.
    const CGFloat extent = MIN(cornerExtent(radius, r.size, continuous),
                               MIN(r.size.width, r.size.height) / 2);
    const CGFloat power = continuous ? 2 / kContinuousCornerExponent : 1;
    const CACornerMask cornerBits[4] = {kCALayerMaxXMinYCorner, kCALayerMaxXMaxYCorner,
                                        kCALayerMinXMaxYCorner, kCALayerMinXMinYCorner};
    int n = 0;

    for (int corner = 0; corner < 4; corner++) {
        CGFloat e = (corners & cornerBits[corner]) ? extent : 0;
        CGFloat cx = (corner < 2 ? CGRectGetMaxX(r) : CGRectGetMinX(r)) + (corner < 2 ? -e : e);
        CGFloat cy = (corner == 0 || corner == 3 ? CGRectGetMinY(r) : CGRectGetMaxY(r)) +
                     (corner == 0 || corner == 3 ? e : -e);
        CGFloat start = (corner - 1) * M_PI_2;
        for (int i = 0; i <= kCornerSegments; i++) {
            CGFloat angle = start + M_PI_2 * i / kCornerSegments;
            CGFloat c = cos(angle), s = sin(angle);
            xy[n++] = cx + e * copysign(pow(fabs(c), power), c);
            xy[n++] = cy + e * copysign(pow(fabs(s), power), s);
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
    roundedRectOutline(rect, layer.cornerRadius, hasContinuousCorners(layer),
                       layer.maskedCorners, fan + 2);
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

    roundedRectOutline(outerRect, layer.cornerRadius, hasContinuousCorners(layer),
                       layer.maskedCorners, outer);
    roundedRectOutline(innerRect, MAX(0, layer.cornerRadius - width),
                       hasContinuousCorners(layer), layer.maskedCorners, inner);

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

    // Layout and display code runs inside -render, after the layer's context named the tree, so a
    // sublayer it added has no texture yet. Drawing it without one would upload into whatever texture
    // is bound and replace that picture. A layer with no context is left as it was: its context is
    // what deletes the name when the layer goes.
    NSNumber *textureId = [layer _textureId];
    if (textureId == nil && [layer _context] != nil) {
        GLuint name = 0;
        glGenTextures(1, &name);
        if (name != 0) {
            textureId = [NSNumber numberWithUnsignedInt: name];
            [layer _setTextureId: textureId];
        }
    }
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

    // contentsCenter, in the unit coordinates of the part, splits the contents
    // into nine parts. The corners keep their size (in points, so pixels divided
    // by contentsScale), the edges stretch along their length and the centre in
    // both directions to fill what is left of rect. Corners that don't fit shrink
    // in proportion. The default, the unit rectangle, stretches everything.
    CGRect center = interpolateRectInLayerKey(layer, @"contentsCenter", currentTime);
    center = CGRectIntersection(CGRectStandardize(center), CGRectMake(0, 0, 1, 1));
    if (CGRectIsNull(center))
        center = CGRectMake(0, 0, 1, 1);

    // Where the nine parts begin and end across (x) and up (y) the rectangle,
    // and the contents coordinates (s, v) that go with them.
    part = CGRectStandardize(part);
    CGFloat x[4], y[4], s[4], v[4];
    CGFloat leftFixed = center.origin.x * partSize.width;
    CGFloat rightFixed = (1 - CGRectGetMaxX(center)) * partSize.width;
    CGFloat bottomFixed = center.origin.y * partSize.height;
    CGFloat topFixed = (1 - CGRectGetMaxY(center)) * partSize.height;
    if (leftFixed + rightFixed > rect.size.width) {
        CGFloat shrink = rect.size.width / (leftFixed + rightFixed);
        leftFixed *= shrink;
        rightFixed *= shrink;
    }
    if (bottomFixed + topFixed > rect.size.height) {
        CGFloat shrink = rect.size.height / (bottomFixed + topFixed);
        bottomFixed *= shrink;
        topFixed *= shrink;
    }
    x[0] = CGRectGetMinX(rect);
    x[1] = x[0] + leftFixed;
    x[3] = CGRectGetMaxX(rect);
    x[2] = x[3] - rightFixed;
    y[0] = CGRectGetMinY(rect);
    y[1] = y[0] + bottomFixed;
    y[3] = CGRectGetMaxY(rect);
    y[2] = y[3] - topFixed;
    s[0] = CGRectGetMinX(part);
    s[1] = s[0] + center.origin.x * part.size.width;
    s[2] = s[0] + CGRectGetMaxX(center) * part.size.width;
    s[3] = CGRectGetMaxX(part);
    v[0] = CGRectGetMinY(part);
    v[1] = v[0] + center.origin.y * part.size.height;
    v[2] = v[0] + CGRectGetMaxY(center) * part.size.height;
    v[3] = CGRectGetMaxY(part);

    // Texture row 0 (t = 0) is the top of the image.
    GLfloat vertices[9 * 6 * 2], textureVertices[9 * 6 * 2];
    int count = 0;
    for (int row = 0; row < 3; row++) {
        for (int column = 0; column < 3; column++) {
            if (!(x[column + 1] > x[column] && y[row + 1] > y[row]))
                continue;
            const CGFloat xs[6] = {x[column], x[column + 1], x[column], x[column + 1], x[column], x[column + 1]};
            const CGFloat ys[6] = {y[row], y[row], y[row + 1], y[row], y[row + 1], y[row + 1]};
            const CGFloat ss[6] = {s[column], s[column + 1], s[column], s[column + 1], s[column], s[column + 1]};
            const CGFloat vs[6] = {v[row], v[row], v[row + 1], v[row], v[row + 1], v[row + 1]};
            for (int i = 0; i < 6; i++) {
                vertices[2 * count] = xs[i];
                vertices[2 * count + 1] = ys[i];
                textureVertices[2 * count] = ss[i];
                textureVertices[2 * count + 1] = flipped ? vs[i] : 1 - vs[i];
                count++;
            }
        }
    }

    glTexCoordPointer(2, GL_FLOAT, 0, textureVertices);
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glColor4f(opacity, opacity, opacity, opacity);
    glDrawArrays(GL_TRIANGLES, 0, count);

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

// Rounded clips. The drawables have no stencil buffer, so a masking layer
// with rounded corners draws its contents and sublayers into a temporary
// texture first. The texture is then drawn over the bounds of the layer with
// the coverage of the rounded rectangle applied by a fragment shader, which
// also anti-aliases the curve. Nested rounded clips intersect because the
// inner layer is composited into the outer layer's texture.
static const char kRoundedClipVertexShader[] =
        "#version 120\n"
        "varying vec2 layerPosition;\n"
        "void main() {\n"
        "    layerPosition = gl_Vertex.xy;\n"
        "    gl_ClipVertex = gl_ModelViewMatrix * gl_Vertex;\n"
        "    gl_Position = ftransform();\n"
        "}\n";

static const char kRoundedClipFragmentShader[] =
        "#version 120\n"
        "uniform sampler2D content;\n"
        "uniform vec2 inverseTextureSize;\n"
        "uniform vec2 layerSize;\n"
        "uniform float extent;\n"
        "uniform float exponent;\n"
        "uniform float pixelsPerUnit;\n"
        "uniform vec4 rounded;\n" // bottom left, bottom right, top left, top right
        "varying vec2 layerPosition;\n"
        "void main() {\n"
        "    vec2 edge = min(layerPosition, layerSize - layerPosition);\n"
        "    bool right = layerPosition.x > layerSize.x * 0.5;\n"
        "    bool top = layerPosition.y > layerSize.y * 0.5;\n"
        "    float corner = top ? (right ? rounded.w : rounded.z)\n"
        "                       : (right ? rounded.y : rounded.x);\n"
        "    float coverage = 1.0;\n"
        "    if (corner > 0.5 && edge.x < extent && edge.y < extent) {\n"
        "        vec2 u = max((vec2(extent) - edge) / extent, vec2(0.0));\n"
        "        float f = pow(pow(u.x, exponent) + pow(u.y, exponent), 1.0 / exponent);\n"
        "        coverage = clamp(0.5 - (f - 1.0) * extent * pixelsPerUnit, 0.0, 1.0);\n"
        "    }\n"
        "    gl_FragColor = texture2D(content, gl_FragCoord.xy * inverseTextureSize) * coverage;\n"
        "}\n";

static GLuint compileShader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint ok = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

typedef struct {
    GLuint texture, framebuffer;
    GLint drawFramebuffer, readFramebuffer;
    GLint width, height;
} CARendererOffscreen;

// Window pixels per unit of the current modelview coordinates.
static CGFloat pixelsPerUnit(void) {
    GLdouble m[16], p[16], a[2], b[2], c[2];
    GLint viewport[4];
    glGetDoublev(GL_MODELVIEW_MATRIX, m);
    glGetDoublev(GL_PROJECTION_MATRIX, p);
    glGetIntegerv(GL_VIEWPORT, viewport);
    if (!windowPoint(m, p, viewport, 0, 0, a) || !windowPoint(m, p, viewport, 1, 0, b) ||
        !windowPoint(m, p, viewport, 0, 1, c))
        return 1;
    return (hypot(b[0] - a[0], b[1] - a[1]) + hypot(c[0] - a[0], c[1] - a[1])) / 2;
}

- (GLuint) _roundedClipProgram {
    if (NS_EXTRA(CARenderer, self)->_roundedClipProgram != 0 ||
        NS_EXTRA(CARenderer, self)->_roundedClipUnavailable)
        return NS_EXTRA(CARenderer, self)->_roundedClipProgram;

    GLuint vertex = compileShader(GL_VERTEX_SHADER, kRoundedClipVertexShader);
    GLuint fragment = compileShader(GL_FRAGMENT_SHADER, kRoundedClipFragmentShader);
    GLuint program = 0;
    if (vertex != 0 && fragment != 0) {
        program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glLinkProgram(program);
        GLint ok = 0;
        glGetProgramiv(program, GL_LINK_STATUS, &ok);
        if (!ok) {
            glDeleteProgram(program);
            program = 0;
        }
    }
    if (vertex != 0)
        glDeleteShader(vertex);
    if (fragment != 0)
        glDeleteShader(fragment);
    // The program goes with the GL context, which may not be current when the
    // renderer is released.
    NS_EXTRA(CARenderer, self)->_roundedClipProgram = program;
    NS_EXTRA(CARenderer, self)->_roundedClipUnavailable = program == 0;
    return program;
}

// Redirects drawing to a transparent texture that covers the drawable's
// window coordinates. Returns NO, drawing unchanged, when that isn't possible.
- (BOOL) _beginOffscreen: (CARendererOffscreen *) pass {
    GLint viewport[4], previousTexture;
    glGetIntegerv(GL_VIEWPORT, viewport);
    pass->width = viewport[0] + viewport[2];
    pass->height = viewport[1] + viewport[3];
    if (pass->width <= 0 || pass->height <= 0 || [self _roundedClipProgram] == 0)
        return NO;

    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &pass->drawFramebuffer);
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &pass->readFramebuffer);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);

    glGenTextures(1, &pass->texture);
    glBindTexture(GL_TEXTURE_2D, pass->texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, pass->width, pass->height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, previousTexture);

    glGenFramebuffers(1, &pass->framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, pass->framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           pass->texture, 0);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, pass->drawFramebuffer);
        glBindFramebuffer(GL_READ_FRAMEBUFFER, pass->readFramebuffer);
        glDeleteFramebuffers(1, &pass->framebuffer);
        glDeleteTextures(1, &pass->texture);
        return NO;
    }

    GLfloat clearColor[4];
    glGetFloatv(GL_COLOR_CLEAR_VALUE, clearColor);
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
    glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
    return YES;
}

// Returns to the previous drawing destination and draws the texture over
// (0, 0, width, height) of the current modelview coordinates, keeping the
// part inside the rounded rectangle.
- (void) _endOffscreen: (CARendererOffscreen *) pass
                 layer: (CALayer *) layer
                  size: (CGSize) size
{
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, pass->drawFramebuffer);
    glBindFramebuffer(GL_READ_FRAMEBUFFER, pass->readFramebuffer);

    BOOL continuous = hasContinuousCorners(layer);
    CACornerMask corners = layer.maskedCorners;
    GLuint program = [self _roundedClipProgram];
    GLint previousProgram, previousTexture, previousUnit;
    glGetIntegerv(GL_CURRENT_PROGRAM, &previousProgram);
    glGetIntegerv(GL_ACTIVE_TEXTURE, &previousUnit);
    glActiveTexture(GL_TEXTURE0);
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &previousTexture);

    glUseProgram(program);
    glBindTexture(GL_TEXTURE_2D, pass->texture);
    glUniform1i(glGetUniformLocation(program, "content"), 0);
    glUniform2f(glGetUniformLocation(program, "inverseTextureSize"), 1.0f / pass->width,
                1.0f / pass->height);
    glUniform2f(glGetUniformLocation(program, "layerSize"), size.width, size.height);
    glUniform1f(glGetUniformLocation(program, "extent"),
                cornerExtent(layer.cornerRadius, size, continuous));
    glUniform1f(glGetUniformLocation(program, "exponent"),
                continuous ? kContinuousCornerExponent : 2);
    glUniform1f(glGetUniformLocation(program, "pixelsPerUnit"), pixelsPerUnit());
    glUniform4f(glGetUniformLocation(program, "rounded"),
                (corners & kCALayerMinXMinYCorner) != 0, (corners & kCALayerMaxXMinYCorner) != 0,
                (corners & kCALayerMinXMaxYCorner) != 0, (corners & kCALayerMaxXMaxYCorner) != 0);

    const GLfloat vertices[4 * 2] = {0, 0, size.width, 0, 0, size.height, size.width, size.height};
    glVertexPointer(2, GL_FLOAT, 0, vertices);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glUseProgram(previousProgram);
    glBindTexture(GL_TEXTURE_2D, previousTexture);
    glActiveTexture(previousUnit);
    glDeleteFramebuffers(1, &pass->framebuffer);
    glDeleteTextures(1, &pass->texture);
}

// The depth of a sublayer as used for ordering siblings. A NaN counts as 0, the default
// zPosition, so every layer has a comparable depth.
static CGFloat siblingDepth(CALayer *child, CFTimeInterval currentTime) {
    CGFloat depth = interpolateFloatInLayerKey(child, @"zPosition", currentTime);

    return isnan(depth) ? 0 : depth;
}

// Returns the sublayers of `layer` back to front: ascending zPosition, so that a layer
// closer to the viewer is drawn after, and so over, the ones behind it. Layers at the same
// depth stay in their array order. The depth test is off, so this order alone decides which
// of two overlapping siblings is visible.
static NSArray *sublayersBackToFront(CALayer *layer, CFTimeInterval currentTime) {
    NSArray *sublayers = layer.sublayers;
    NSUInteger count = [sublayers count];
    BOOL inOrder = YES;
    CGFloat previous = 0;

    for (NSUInteger i = 0; i < count && inOrder; i++) {
        CGFloat depth = siblingDepth([sublayers objectAtIndex: i], currentTime);

        if (i > 0 && depth < previous)
            inOrder = NO;
        previous = depth;
    }
    if (inOrder)
        return sublayers;

    NSMutableData *depthStorage = [NSMutableData dataWithLength: count * sizeof(CGFloat)];
    CGFloat *depths = [depthStorage mutableBytes];
    NSMutableArray *indexes = [NSMutableArray arrayWithCapacity: count];

    for (NSUInteger i = 0; i < count; i++) {
        depths[i] = siblingDepth([sublayers objectAtIndex: i], currentTime);
        [indexes addObject: [NSNumber numberWithUnsignedInteger: i]];
    }
    // The array position is the tie-break, which makes the result independent of
    // whether the sort itself is stable.
    [indexes sortUsingComparator: ^NSComparisonResult(NSNumber *a, NSNumber *b) {
        NSUInteger ia = [a unsignedIntegerValue], ib = [b unsignedIntegerValue];

        if (depths[ia] != depths[ib])
            return depths[ia] < depths[ib] ? NSOrderedAscending : NSOrderedDescending;
        return ia < ib ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity: count];

    for (NSNumber *index in indexes)
        [result addObject: [sublayers objectAtIndex: [index unsignedIntegerValue]]];
    return result;
}

// Layers are composited in painter's order: a layer's background and contents, its
// sublayers in ascending zPosition order (array order among equals), then its
// border. Opacity multiplies down the tree.
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
    CARendererOffscreen offscreen;
    BOOL rounded = NO;
    if (masks) {
        if (!(bounds.size.width > 0 && bounds.size.height > 0)) {
            glPopMatrix();
            return;
        }
        // A rounded clip is drawn through a texture (see -_endOffscreen:...).
        if (layer.cornerRadius > 0 && layer.maskedCorners != 0)
            rounded = [self _beginOffscreen: &offscreen];
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
    for (CALayer *child in sublayersBackToFront(layer, currentTime))
        [self _renderLayer: child
                currentTime: currentTime
              parentOpacity: opacity
              parentFlipped: flipped
                       clip: clip];
    glPopMatrix();

    if (masks)
        popClip(clip, &saved);
    if (rounded)
        [self _endOffscreen: &offscreen layer: layer size: bounds.size];

    // The border covers the sublayers.
    if (!isTransformLayer)
        [self _drawBorderOfLayer: layer bounds: bounds opacity: opacity];

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
