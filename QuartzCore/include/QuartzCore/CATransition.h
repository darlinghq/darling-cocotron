#import <QuartzCore/CAAnimation.h>
#import <QuartzCore/LegacyIvarLayout.h>

#define _NS_SIDE_CATransition 0, 1,
@interface CATransition : CAAnimation {
    NS_EXTRA_IVARS_BEGIN(CATransition)
        NSString *_type;
        NSString *_subtype;
        CGFloat _startProgress;
        CGFloat _endProgress;
    NS_SIDE_IVARS_END(CATransition)
}

@property(copy) NSString *type;
@property(copy) NSString *subtype;
@property CGFloat startProgress;
@property CGFloat endProgress;

@end
