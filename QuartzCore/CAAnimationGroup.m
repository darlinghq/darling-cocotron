#import <QuartzCore/CAAnimationGroup.h>

@implementation CAAnimationGroup

- (NSArray *) animations {
    return NS_EXTRA(CAAnimationGroup, self)->_animations;
}

- (void) setAnimations: (NSArray *) value {
    value = [value copy];
    [NS_EXTRA(CAAnimationGroup, self)->_animations release];
    NS_EXTRA(CAAnimationGroup, self)->_animations = value;
}

@end
