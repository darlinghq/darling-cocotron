// Keyed archiving of CALayer, CAShapeLayer and CATextLayer: state survives a
// round trip, the archive has the layout macOS writes (default layer with four
// keys, proxy classes for geometry, colors, arrays, paths and images, a
// __CACodingContents list), and state without an archived form is left out
// rather than raising. The same program passes on macOS.
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>

#define CHECK(cond, code)                                   \
    do {                                                    \
        if (!(cond)) {                                      \
            fprintf(stderr, "FAIL %d: %s\n", code, #cond);  \
            return code;                                    \
        }                                                   \
    } while (0)

static id roundTrip(id root, NSError **error) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: root requiringSecureCoding: YES error: error];
    if (data == nil)
        return nil;
    return [NSKeyedUnarchiver unarchivedObjectOfClass: [CALayer class] fromData: data error: error];
}

// Records the keys a layer was archived with and the classes decoded below it.
static NSMutableArray *recordedKeys;
static NSMutableSet *decodedClasses;

#define PROBE_CLASS(NAME, SUPER)                                                                \
    @interface NAME : SUPER                                                                      \
    @end                                                                                         \
    @implementation NAME                                                                         \
    + (BOOL) supportsSecureCoding { return YES; }                                                \
    - (instancetype) initWithCoder: (NSCoder *) coder {                                          \
        NSArray *keys = [coder decodeObjectOfClass: [NSArray class] forKey: @"__CACodingContents"]; \
        if ([recordedKeys count] == 0)                                                           \
            [recordedKeys addObjectsFromArray: keys]; /* the outermost layer is decoded first */ \
        return [super initWithCoder: coder];                                                     \
    }                                                                                            \
    @end

PROBE_CLASS(ProbeLayer, CALayer)
PROBE_CLASS(ProbeShapeLayer, CAShapeLayer)
PROBE_CLASS(ProbeTextLayer, CATextLayer)

@interface RecordingUnarchiver : NSKeyedUnarchiver
@end
@implementation RecordingUnarchiver
- (id) decodeObjectOfClasses: (NSSet *) classes forKey: (NSString *) key {
    id object = [super decodeObjectOfClasses: classes forKey: key];
    if (object != nil)
        [decodedClasses addObject: NSStringFromClass([object class])];
    return object;
}
- (id) decodeObjectOfClass: (Class) cls forKey: (NSString *) key {
    id object = [super decodeObjectOfClass: cls forKey: key];
    if (object != nil)
        [decodedClasses addObject: NSStringFromClass([object class])];
    return object;
}
@end

// Decodes the archive with ProbeLayer standing in for CALayer; fills the two records.
static BOOL inspect(id layer) {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: layer requiringSecureCoding: YES error: NULL];
    recordedKeys = [NSMutableArray array];
    decodedClasses = [NSMutableSet set];
    NSError *error = nil;
    RecordingUnarchiver *unarchiver = [[[RecordingUnarchiver alloc] initForReadingFromData: data error: &error] autorelease];
    [unarchiver setClass: [ProbeLayer class] forClassName: @"CALayer"];
    [unarchiver setClass: [ProbeShapeLayer class] forClassName: @"CAShapeLayer"];
    [unarchiver setClass: [ProbeTextLayer class] forClassName: @"CATextLayer"];
    Class probe = [layer isKindOfClass: [CAShapeLayer class]] ? [ProbeShapeLayer class]
                  : [layer isKindOfClass: [CATextLayer class]] ? [ProbeTextLayer class] : [ProbeLayer class];
    id decoded = [unarchiver decodeObjectOfClass: probe forKey: NSKeyedArchiveRootObjectKey];
    [unarchiver finishDecoding];
    return decoded != nil;
}

static BOOL sameColorInSRGB(CGColorRef a, CGColorRef b) {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef ma = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, a, NULL);
    CGColorRef mb = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, b, NULL);
    BOOL same = ma != NULL && mb != NULL && CGColorGetNumberOfComponents(ma) == 4 && CGColorGetNumberOfComponents(mb) == 4;
    for (int i = 0; same && i < 4; i++) {
        CGFloat d = CGColorGetComponents(ma)[i] - CGColorGetComponents(mb)[i];
        same = d < 1e-4 && d > -1e-4;
    }
    CGColorRelease(ma);
    CGColorRelease(mb);
    CGColorSpaceRelease(srgb);
    return same;
}

static CGImageRef makeImage(void) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 3, 2, 8, 12, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 3, 2));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    return image;
}

int main(void) {
    @autoreleasepool {
        CHECK([CALayer supportsSecureCoding] && [CAShapeLayer supportsSecureCoding] && [CATextLayer supportsSecureCoding], 1);

        // A default layer carries exactly the four default keys, listed in __CACodingContents.
        CHECK(inspect([CALayer layer]), 2);
        NSArray *expectedKeys = @[ @"allowsEdgeAntialiasing", @"allowsGroupOpacity", @"contentsFormat", @"cornerCurve" ];
        CHECK([recordedKeys isEqualToArray: expectedKeys], 3);
        BOOL anyProxy = NO;
        for (NSString *name in decodedClasses)
            anyProxy |= [name hasSuffix: @"Proxy"];
        CHECK(!anyProxy, 4);

        // Properties set to non-default values add their keys (sorted), wrapped in proxies.
        CALayer *keyed = [CALayer layer];
        keyed.position = CGPointMake(5, 6);
        keyed.bounds = CGRectMake(0, 0, 10, 20);
        keyed.shadowOffset = CGSizeMake(1, 2);
        keyed.transform = CATransform3DMakeScale(2, 2, 1);
        keyed.backgroundColor = CGColorCreateGenericRGB(1, 0, 0, 1);
        keyed.sublayers = @[ [CALayer layer] ];
        keyed.name = @"k";
        CHECK(inspect(keyed), 5);
        NSArray *sorted = [recordedKeys sortedArrayUsingSelector: @selector(compare:)];
        CHECK([recordedKeys containsObject: @"position"] && [recordedKeys containsObject: @"bounds"] &&
                  [recordedKeys containsObject: @"shadowOffset"] && [recordedKeys containsObject: @"transform"] &&
                  [recordedKeys containsObject: @"backgroundColor"] && [recordedKeys containsObject: @"sublayers"] &&
                  [recordedKeys containsObject: @"name"] && [recordedKeys isEqualToArray: sorted], 6);
        CHECK([decodedClasses containsObject: @"LKNSValueCodingProxy"] && [decodedClasses containsObject: @"LKCGColorCodingProxy"] &&
                  [decodedClasses containsObject: @"LKNSArrayCodingProxy"], 7);

        CALayer *root = [CALayer layer];
        root.bounds = CGRectMake(0, 0, 40, 30);
        root.position = CGPointMake(5, 6);
        root.anchorPoint = CGPointMake(0.25, 0.75);
        root.opacity = 0.5;
        root.transform = CATransform3DMakeScale(2, 3, 1);
        root.sublayerTransform = CATransform3DMakeTranslation(1, 2, 3);
        root.cornerRadius = 4;
        root.borderWidth = 1.5;
        root.masksToBounds = YES;
        root.hidden = YES;
        root.contentsGravity = kCAGravityTopLeft;
        root.minificationFilter = kCAFilterNearest;
        root.edgeAntialiasingMask = kCALayerTopEdge | kCALayerLeftEdge;
        root.compositingFilter = @"multiplyBlendMode";
        CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
        CGFloat p3Components[4] = {0.1, 0.2, 0.3, 0.4};
        CGColorRef background = CGColorCreate(p3, p3Components);
        root.backgroundColor = background;
        root.shadowOffset = CGSizeMake(2, -2);
        root.shadowOpacity = 0.25;
        CGPathRef shadow = CGPathCreateWithRect(CGRectMake(0, 0, 10, 20), NULL);
        root.shadowPath = shadow;
        CGImageRef image = makeImage();
        root.contents = (id) image;

        CAShapeLayer *shape = [CAShapeLayer layer];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 1, 1);
        CGPathAddQuadCurveToPoint(path, NULL, 5, 10, 10, 0);
        CGPathAddCurveToPoint(path, NULL, 12, 2, 14, 4, 16, 0);
        CGPathCloseSubpath(path);
        shape.path = path;
        shape.strokeColor = CGColorCreateGenericGray(0.5, 1);
        shape.lineWidth = 3;
        shape.strokeStart = 0.1;
        shape.strokeEnd = 0.9;
        shape.lineCap = kCALineCapRound;
        shape.lineDashPattern = @[ @2, @3 ];
        CATextLayer *text = [CATextLayer layer];
        text.string = @"hello";
        text.font = (CFTypeRef) @"Courier";
        text.fontSize = 11;
        text.alignmentMode = kCAAlignmentCenter;
        CALayer *mask = [CALayer layer];
        mask.bounds = CGRectMake(0, 0, 7, 7);
        [root addSublayer: shape];
        [root addSublayer: text];
        root.mask = mask;

        NSError *error = nil;
        CALayer *copy = roundTrip(root, &error);
        CHECK(copy != nil && [copy class] == [CALayer class], 10);
        CHECK(CGRectEqualToRect(copy.bounds, root.bounds) && CGPointEqualToPoint(copy.position, root.position), 11);
        CHECK(CGPointEqualToPoint(copy.anchorPoint, root.anchorPoint) && copy.opacity == 0.5f, 12);
        CHECK(CATransform3DEqualToTransform(copy.transform, root.transform), 13);
        CHECK(CATransform3DEqualToTransform(copy.sublayerTransform, root.sublayerTransform), 14);
        CHECK(copy.cornerRadius == 4 && copy.borderWidth == 1.5 && copy.masksToBounds && copy.hidden, 15);
        CHECK([copy.contentsGravity isEqualToString: kCAGravityTopLeft], 16);
        CHECK([copy.minificationFilter isEqualToString: kCAFilterNearest], 17);
        CHECK(copy.edgeAntialiasingMask == (kCALayerTopEdge | kCALayerLeftEdge), 18);
        CHECK([copy.compositingFilter isEqual: @"multiplyBlendMode"], 19);
        // Colors come back in sRGB, matched from the original color space.
        CHECK(sameColorInSRGB(copy.backgroundColor, background), 20);
        CHECK(CGSizeEqualToSize(copy.shadowOffset, root.shadowOffset) && copy.shadowOpacity == 0.25f, 21);
        CHECK(copy.shadowPath != NULL && CGRectEqualToRect(CGPathGetBoundingBox(copy.shadowPath), CGPathGetBoundingBox(shadow)), 22);

        CGImageRef decoded = (CGImageRef) copy.contents;
        CHECK(decoded != NULL && CGImageGetWidth(decoded) == 3 && CGImageGetHeight(decoded) == 2, 23);

        CHECK([copy.sublayers count] == 2, 24);
        CAShapeLayer *shapeCopy = (CAShapeLayer *) copy.sublayers[0];
        CATextLayer *textCopy = (CATextLayer *) copy.sublayers[1];
        CHECK([shapeCopy isKindOfClass: [CAShapeLayer class]] && shapeCopy.superlayer == copy, 25);
        CHECK(CGPathEqualToPath(shapeCopy.path, path), 26);
        CHECK(sameColorInSRGB(shapeCopy.strokeColor, shape.strokeColor), 27);
        CHECK(shapeCopy.lineWidth == 3 && [shapeCopy.lineCap isEqualToString: kCALineCapRound], 28);
        CHECK(shapeCopy.strokeStart == 0.1 && shapeCopy.strokeEnd == 0.9, 29);
        CHECK([shapeCopy.lineDashPattern isEqual: (@[ @2, @3 ])], 30);
        CHECK([textCopy isKindOfClass: [CATextLayer class]] && [textCopy.string isEqual: @"hello"], 31);
        CHECK([(id) textCopy.font isEqual: @"Courier"] && textCopy.fontSize == 11, 32);
        CHECK([textCopy.alignmentMode isEqualToString: kCAAlignmentCenter], 33);
        CHECK(copy.mask != nil && CGRectEqualToRect(copy.mask.bounds, mask.bounds), 34);

        // Defaults of the subclasses stay out of the archive and come back as defaults.
        CHECK(inspect([CAShapeLayer layer]) && [recordedKeys isEqualToArray: expectedKeys], 35);
        CHECK(inspect([CATextLayer layer]) && [recordedKeys isEqualToArray: expectedKeys], 36);
        CAShapeLayer *plainShape = roundTrip([CAShapeLayer layer], &error);
        CHECK(plainShape.lineWidth == 1 && plainShape.miterLimit == 10 && plainShape.strokeEnd == 1 && plainShape.fillColor != NULL &&
                  plainShape.strokeColor == NULL && plainShape.path == NULL, 37);
        CATextLayer *plainText = roundTrip([CATextLayer layer], &error);
        CHECK(plainText.fontSize == 36 && plainText.string == nil && !plainText.wrapped, 38);

        // A font that is not a name is archived as NSNull: the layer comes back with its default font, not the CGFont.
        CATextLayer *withFont = [CATextLayer layer];
        CGFontRef font = CGFontCreateWithFontName(CFSTR("Helvetica"));
        withFont.font = font;
        CATextLayer *fontCopy = roundTrip(withFont, &error);
        CHECK(fontCopy != nil && (fontCopy.font == NULL || ![(id) fontCopy.font isKindOfClass: [NSString class]]), 39);

        // Animations are not archived; the layer itself is.
        CALayer *animated = [CALayer layer];
        animated.name = @"animated";
        [animated addAnimation: [CABasicAnimation animationWithKeyPath: @"opacity"] forKey: @"a"];
        CALayer *animatedCopy = roundTrip(animated, &error);
        CHECK(animatedCopy != nil && [animatedCopy.name isEqualToString: @"animated"], 40);
    }
    puts("ALL PASSED");
    return 0;
}
