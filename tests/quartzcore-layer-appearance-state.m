#import <QuartzCore/QuartzCore.h>

int main(void) {
    @autoreleasepool {
        CALayer *layer = [CALayer layer];
        if (layer.mask != nil || layer.filters != nil ||
            layer.compositingFilter != nil || layer.shadowOpacity != 0 ||
            layer.shadowRadius != 3 ||
            !CGSizeEqualToSize(layer.shadowOffset, CGSizeMake(0, -3)))
            return 1;
        if (layer.shadowColor == NULL || CGColorGetAlpha(layer.shadowColor) != 1)
            return 2;

        CALayer *mask = [CALayer layer];
        layer.mask = mask;
        if (layer.mask != mask || mask.superlayer != nil)
            return 3;

        NSMutableArray *inputFilters = [NSMutableArray arrayWithObject:@"filter"];
        layer.filters = inputFilters;
        [inputFilters removeAllObjects];
        if (layer.filters.count != 1)
            return 4;

        NSObject *filter = [[NSObject alloc] init];
        layer.compositingFilter = filter;
        [filter release];
        if (layer.compositingFilter == nil)
            return 5;

        CGColorRef red = CGColorCreateGenericRGB(1, 0, 0, 1);
        layer.shadowColor = red;
        CGColorRelease(red);
        layer.shadowOpacity = 0.5f;
        layer.shadowRadius = 8;
        layer.shadowOffset = CGSizeMake(2, -4);
        if (layer.shadowColor == NULL || layer.shadowOpacity != 0.5f ||
            layer.shadowRadius != 8 ||
            !CGSizeEqualToSize(layer.shadowOffset, CGSizeMake(2, -4)))
            return 6;

        BOOL rejectedSelfMask = NO;
        @try {
            layer.mask = layer;
        } @catch (NSException *exception) {
            rejectedSelfMask = [exception.name isEqualToString:NSInvalidArgumentException];
        }
        return rejectedSelfMask ? 0 : 7;
    }
}
