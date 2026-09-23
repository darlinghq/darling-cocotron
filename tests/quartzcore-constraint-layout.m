#import <QuartzCore/QuartzCore.h>

@interface CountingLayoutManager : NSObject <CALayoutManager> {
    int _calls;
}
- (int)calls;
@end

@implementation CountingLayoutManager
- (void)layoutSublayersOfLayer:(CALayer *)layer {
    _calls++;
}
- (int)calls { return _calls; }
@end

@interface LayoutDelegate : NSObject <CALayerDelegate>
@end

@implementation LayoutDelegate
- (void)layoutSublayersOfLayer:(CALayer *)layer {
}
@end

static BOOL frameIs(CALayer *layer, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return CGRectEqualToRect([layer frame], CGRectMake(x, y, w, h));
}

int main(void) {
    @autoreleasepool {
        CALayer *root = [CALayer layer];
        root.bounds = CGRectMake(0, 0, 200, 100);
        if (root.layoutManager != nil || root.name != nil) return 1;

        // The two-halves example from the CAConstraintLayoutManager documentation.
        CAConstraint *height = [CAConstraint constraintWithAttribute:kCAConstraintHeight
                                                          relativeTo:@"superlayer"
                                                           attribute:kCAConstraintHeight];
        CAConstraint *halfWidth = [CAConstraint constraintWithAttribute:kCAConstraintWidth
                                                             relativeTo:@"superlayer"
                                                              attribute:kCAConstraintWidth
                                                                  scale:0.5
                                                                 offset:0];
        CAConstraint *left = [CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                        relativeTo:@"superlayer"
                                                         attribute:kCAConstraintMinX];
        CAConstraint *right = [CAConstraint constraintWithAttribute:kCAConstraintMaxX
                                                         relativeTo:@"superlayer"
                                                          attribute:kCAConstraintMaxX];
        CAConstraint *bottom = [CAConstraint constraintWithAttribute:kCAConstraintMinY
                                                          relativeTo:@"superlayer"
                                                           attribute:kCAConstraintMinY];
        if (halfWidth.attribute != kCAConstraintWidth || ![halfWidth.sourceName isEqualToString:@"superlayer"] ||
            halfWidth.sourceAttribute != kCAConstraintWidth || halfWidth.scale != 0.5 || halfWidth.offset != 0 ||
            left.scale != 1)
            return 2;

        // A sibling-relative layer placed before the layer it depends on.
        CALayer *caption = [CALayer layer];
        caption.frame = CGRectMake(0, 0, 30, 10);
        [caption addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                          relativeTo:@"leftHalf"
                                                           attribute:kCAConstraintMaxX
                                                              offset:5]];
        [caption addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMidY
                                                          relativeTo:@"leftHalf"
                                                           attribute:kCAConstraintMidY]];
        [root addSublayer:caption];

        CALayer *leftLayer = [CALayer layer];
        leftLayer.name = @"leftHalf";
        leftLayer.frame = CGRectMake(0, 0, 20, 20);
        leftLayer.constraints = @[height, halfWidth, left, bottom];
        [root addSublayer:leftLayer];

        CALayer *rightLayer = [CALayer layer];
        rightLayer.constraints = @[height, halfWidth, right, bottom];
        [root addSublayer:rightLayer];

        // Only one X edge and one Y edge: the layer keeps its size.
        CALayer *badge = [CALayer layer];
        badge.frame = CGRectMake(1, 2, 16, 8);
        [badge addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMaxX
                                                        relativeTo:@"superlayer"
                                                         attribute:kCAConstraintMaxX
                                                            offset:-4]];
        [badge addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMaxY
                                                        relativeTo:@"superlayer"
                                                         attribute:kCAConstraintMaxY
                                                            offset:-4]];
        // Both edges: the size follows them.
        [badge addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMinY
                                                        relativeTo:@"superlayer"
                                                         attribute:kCAConstraintMidY]];
        [root addSublayer:badge];

        // Unknown source names are ignored.
        CALayer *orphan = [CALayer layer];
        orphan.frame = CGRectMake(3, 4, 5, 6);
        [orphan addConstraint:[CAConstraint constraintWithAttribute:kCAConstraintMinX
                                                         relativeTo:@"missing"
                                                          attribute:kCAConstraintMinX]];
        [root addSublayer:orphan];

        root.layoutManager = [CAConstraintLayoutManager layoutManager];
        if (![root.layoutManager isKindOfClass:[CAConstraintLayoutManager class]] || !root.needsLayout)
            return 3;
        [root layoutIfNeeded];

        if (!frameIs(leftLayer, 0, 0, 100, 100)) return 4;
        if (!frameIs(rightLayer, 100, 0, 100, 100)) return 5;
        if (!frameIs(caption, 105, 45, 30, 10)) return 6;
        if (!frameIs(badge, 180, 50, 16, 46)) return 7;
        if (!frameIs(orphan, 3, 4, 5, 6)) return 8;

        // Resizing the superlayer lays the sublayers out again.
        root.bounds = CGRectMake(0, 0, 300, 60);
        if (!root.needsLayout) return 9;
        [root layoutIfNeeded];
        if (!frameIs(leftLayer, 0, 0, 150, 60)) return 10;
        if (!frameIs(rightLayer, 150, 0, 150, 60)) return 11;
        if (!frameIs(caption, 155, 25, 30, 10)) return 12;

        // Changing a sublayer's constraints marks the superlayer for layout.
        caption.constraints = @[[CAConstraint constraintWithAttribute:kCAConstraintMidX
                                                           relativeTo:@"superlayer"
                                                            attribute:kCAConstraintMidX]];
        if (!root.needsLayout) return 13;
        [root layoutIfNeeded];
        if (!frameIs(caption, 135, 25, 30, 10)) return 14;

        // A delegate that lays out takes precedence over the layout manager.
        CountingLayoutManager *counting = [[CountingLayoutManager alloc] init];
        LayoutDelegate *delegate = [[LayoutDelegate alloc] init];
        CALayer *other = [CALayer layer];
        other.layoutManager = counting;
        [other layoutIfNeeded];
        if ([counting calls] != 1) return 15;
        other.delegate = delegate;
        [other setNeedsLayout];
        [other layoutIfNeeded];
        if ([counting calls] != 1) return 16;
        other.delegate = nil;
        [counting release];
        [delegate release];

        @try {
            [CAConstraint constraintWithAttribute:(CAConstraintAttribute)8
                                       relativeTo:@"superlayer"
                                        attribute:kCAConstraintMinX];
            return 17;
        } @catch (NSException *e) {
            if (![[e name] isEqualToString:NSInvalidArgumentException]) return 18;
        }

        printf("PASS quartzcore-constraint-layout\n");
        return 0;
    }
}
