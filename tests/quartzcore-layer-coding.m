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

// Plain keyed archiving, so the exception itself is observable.
static NSString *archiveException(id root) {
    @try {
        [NSKeyedArchiver archivedDataWithRootObject: root];
    } @catch (NSException *e) {
        return [e name];
    }
    return nil;
}

static BOOL sameColor(CGColorRef a, CGColorRef b) {
    return (a == NULL && b == NULL) || (a != NULL && b != NULL && CGColorEqualToColor(a, b));
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
        CHECK([CALayer supportsSecureCoding], 1);

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
        root.borderColor = NULL;
        root.shadowOffset = CGSizeMake(2, -2);
        CGPathRef shadow = CGPathCreateWithRect(CGRectMake(0, 0, 10, 20), NULL);
        root.shadowPath = shadow;
        CGImageRef image = makeImage();
        root.contents = (id) image;

        CAShapeLayer *shape = [CAShapeLayer layer];
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddQuadCurveToPoint(path, NULL, 5, 10, 10, 0);
        CGPathAddCurveToPoint(path, NULL, 12, 2, 14, 4, 16, 0);
        CGPathCloseSubpath(path);
        shape.path = path;
        shape.fillColor = NULL;
        shape.strokeColor = CGColorCreateGenericGray(0.5, 1);
        shape.lineWidth = 3;
        shape.lineCap = kCALineCapRound;
        shape.lineDashPattern = @[@2, @3];
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
        CHECK(copy != nil && [copy class] == [CALayer class], 2);
        CHECK(CGRectEqualToRect(copy.bounds, root.bounds) && CGPointEqualToPoint(copy.position, root.position), 3);
        CHECK(CGPointEqualToPoint(copy.anchorPoint, root.anchorPoint) && copy.opacity == 0.5f, 4);
        CHECK(CATransform3DEqualToTransform(copy.transform, root.transform), 5);
        CHECK(CATransform3DEqualToTransform(copy.sublayerTransform, root.sublayerTransform), 6);
        CHECK(copy.cornerRadius == 4 && copy.borderWidth == 1.5 && copy.masksToBounds && copy.hidden, 7);
        CHECK([copy.contentsGravity isEqualToString: kCAGravityTopLeft], 8);
        CHECK([copy.minificationFilter isEqualToString: kCAFilterNearest], 9);
        CHECK(copy.edgeAntialiasingMask == (kCALayerTopEdge | kCALayerLeftEdge), 10);
        CHECK([copy.compositingFilter isEqual: @"multiplyBlendMode"], 11);
        CHECK(sameColor(copy.backgroundColor, background), 12);
        CHECK(CFEqual(CGColorSpaceGetName(CGColorGetColorSpace(copy.backgroundColor)), kCGColorSpaceDisplayP3), 13);
        CHECK(copy.borderColor == NULL && sameColor(copy.shadowColor, root.shadowColor), 14);
        CHECK(CGSizeEqualToSize(copy.shadowOffset, root.shadowOffset), 15);
        CHECK(copy.shadowPath != NULL && CGPathEqualToPath(copy.shadowPath, shadow), 16);

        CGImageRef decoded = (CGImageRef) copy.contents;
        CHECK(decoded != NULL && CGImageGetWidth(decoded) == 3 && CGImageGetHeight(decoded) == 2, 17);
        CFDataRef before = CGDataProviderCopyData(CGImageGetDataProvider(image));
        CFDataRef after = CGDataProviderCopyData(CGImageGetDataProvider(decoded));
        CHECK(before && after && CFEqual(before, after), 18);

        CHECK([copy.sublayers count] == 2, 19);
        CAShapeLayer *shapeCopy = (CAShapeLayer *) copy.sublayers[0];
        CATextLayer *textCopy = (CATextLayer *) copy.sublayers[1];
        CHECK([shapeCopy isKindOfClass: [CAShapeLayer class]] && shapeCopy.superlayer == copy, 20);
        CHECK(CGPathEqualToPath(shapeCopy.path, path), 21);
        CHECK(shapeCopy.fillColor == NULL && sameColor(shapeCopy.strokeColor, shape.strokeColor), 22);
        CHECK(shapeCopy.lineWidth == 3 && [shapeCopy.lineCap isEqualToString: kCALineCapRound], 23);
        CHECK([shapeCopy.lineDashPattern isEqual: (@[@2, @3])] && shapeCopy.strokeEnd == 1, 24);
        CHECK([textCopy isKindOfClass: [CATextLayer class]] && [textCopy.string isEqual: @"hello"], 25);
        CHECK([(id) textCopy.font isEqual: @"Courier"] && textCopy.fontSize == 11, 26);
        CHECK([textCopy.alignmentMode isEqualToString: kCAAlignmentCenter], 27);
        CHECK(sameColor(textCopy.foregroundColor, text.foregroundColor), 28);
        CHECK(copy.mask != nil && CGRectEqualToRect(copy.mask.bounds, mask.bounds) && copy.mask.superlayer == nil, 29);

        // State with no archived form fails loudly rather than being dropped.
        // (Animations are also refused, but a layer only holds them once it has a render context.)
        CALayer *withObject = [CALayer layer];
        withObject.contents = [NSDate date];
        CHECK([archiveException(withObject) isEqualToString: NSInvalidArchiveOperationException], 31);
        CALayer *withFilter = [CALayer layer];
        withFilter.filters = @[[NSDate date]];
        CHECK([archiveException(withFilter) isEqualToString: NSInvalidArchiveOperationException], 32);
        CATextLayer *withFont = [CATextLayer layer];
        CGFontRef font = CGFontCreateWithFontName(CFSTR("Helvetica"));
        withFont.font = font;
        CHECK(font == NULL || [archiveException(withFont) isEqualToString: NSInvalidArchiveOperationException], 33);
        // The secure-coding entry point reports the same failure as an error.
        error = nil;
        CHECK(roundTrip(withFilter, &error) == nil && error != nil, 34);
        // A failure in a sublayer fails the whole tree.
        CALayer *parent = [CALayer layer];
        [parent addSublayer: withObject];
        CHECK([archiveException(parent) isEqualToString: NSInvalidArchiveOperationException], 35);
    }
    printf("ALL PASSED\n");
    return 0;
}
