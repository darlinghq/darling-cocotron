#import <QuartzCore/QuartzCore.h>

@interface LayerLayoutDelegate : NSObject <CALayerDelegate> {
    int _calls;
}
- (int)calls;
@end

@implementation LayerLayoutDelegate
- (void)layoutSublayersOfLayer:(CALayer *)layer {
    _calls++;
}
- (int)calls { return _calls; }
@end

int main(void) {
    @autoreleasepool {
        CALayer *layer = [CALayer layer];
        if (![layer.contentsGravity isEqualToString:kCAGravityResize] ||
            ![layer.cornerCurve isEqualToString:kCACornerCurveCircular] ||
            !layer.allowsGroupOpacity || layer.shadowPath != NULL)
            return 1;

        layer.contentsGravity = kCAGravityCenter;
        layer.cornerCurve = kCACornerCurveContinuous;
        layer.allowsGroupOpacity = NO;
        CGPathRef input = CGPathCreateWithRect(CGRectMake(0, 0, 10, 12), NULL);
        layer.shadowPath = input;
        CGPathRelease(input);
        if (![layer.contentsGravity isEqualToString:kCAGravityCenter] ||
            ![layer.cornerCurve isEqualToString:kCACornerCurveContinuous] ||
            layer.allowsGroupOpacity ||
            !CGRectEqualToRect(CGPathGetBoundingBox(layer.shadowPath), CGRectMake(0, 0, 10, 12)))
            return 2;

        LayerLayoutDelegate *delegate = [[LayerLayoutDelegate alloc] init];
        layer.delegate = delegate;
        [layer setNeedsLayout];
        if (![layer needsLayout]) return 3;
        [layer layoutIfNeeded];
        if ([layer needsLayout] || [delegate calls] != 1) return 4;
        [layer layoutIfNeeded];
        if ([delegate calls] != 1) return 5;

        layer.bounds = CGRectMake(0, 0, 20, 30);
        [layer layoutIfNeeded];
        if ([delegate calls] != 2) return 6;

        CALayer *child = [CALayer layer];
        LayerLayoutDelegate *childDelegate = [[LayerLayoutDelegate alloc] init];
        child.delegate = childDelegate;
        [layer addSublayer:child];
        [child setNeedsLayout];
        [layer layoutIfNeeded];
        if ([childDelegate calls] != 1) return 7;

        [childDelegate release];
        [delegate release];
        return 0;
    }
}
