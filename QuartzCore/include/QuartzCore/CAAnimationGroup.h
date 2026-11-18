#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/LegacyIvarLayout.h>

@class NSArray;

#define _NS_SIDE_CAAnimationGroup 0, 1,
@interface CAAnimationGroup : CAAnimation {
    NS_EXTRA_IVARS_BEGIN(CAAnimationGroup)
        NSArray *_animations;
    NS_SIDE_IVARS_END(CAAnimationGroup)
}

@property(copy) NSArray *animations;

@end
