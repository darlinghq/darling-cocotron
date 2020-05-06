#import <Foundation/NSObject.h>
#import <QuartzCore/CAAction.h>
#import <QuartzCore/CABase.h>
#import <QuartzCore/CAMediaTiming.h>

@class CAMediaTimingFunction, CAPropertyAnimation;

CA_EXPORT NSString *const kCATransitionFade;
CA_EXPORT NSString *const kCATransitionMoveIn;
CA_EXPORT NSString *const kCATransitionPush;
CA_EXPORT NSString *const kCATransitionReveal;

CA_EXPORT NSString *const kCATransitionFromLeft;
CA_EXPORT NSString *const kCATransitionFromRight;
CA_EXPORT NSString *const kCATransitionFromTop;
CA_EXPORT NSString *const kCATransitionFromBottom;

CA_EXPORT NSString *const kCAAnimationLinear;
CA_EXPORT NSString *const kCAAnimationDiscrete;
CA_EXPORT NSString *const kCAAnimationPaced;
CA_EXPORT NSString *const kCAAnimationCubic;
CA_EXPORT NSString *const kCAAnimationCubicPaced;

CA_EXPORT NSString *const kCAAnimationRotateAuto;
CA_EXPORT NSString *const kCAAnimationRotateAutoReverse;

@interface CAAnimation : NSObject <NSCopying, CAMediaTiming, CAAction> {
    id _delegate;
    BOOL _removedOnCompletion;
    CAMediaTimingFunction *_timingFunction;
    BOOL _autoreverses;
    CFTimeInterval _beginTime;
    CFTimeInterval _duration;
    NSString *_fillMode;
    CGFloat _repeatCount;
    CFTimeInterval _repeatDuration;
    CGFloat _speed;
    CFTimeInterval _timeOffset;
}

+ animation;

@property(retain) id delegate;

@property(getter=isRemovedOnCompletion) BOOL removedOnCompletion;

@property(retain) CAMediaTimingFunction *timingFunction;

@end

@interface NSObject (CAAnimationDelegate)
- (void) animationDidStart: (CAAnimation *) animation;
- (void) animationDidStop: (CAAnimation *) animation finished: (BOOL) finished;
@end

@interface CAPropertyAnimation : CAAnimation {
    NSString *_keyPath;
    BOOL _additive;
    BOOL _cumulative;
}

+ animationWithKeyPath: (NSString *) keyPath;
@property(copy) NSString *keyPath;
@property(getter=isAdditive) BOOL additive;
@property(getter=isCumulative) BOOL cumulative;

@end

@interface CAKeyframeAnimation : CAPropertyAnimation

@end

@interface CABasicAnimation : CAPropertyAnimation {
    id _fromValue;
    id _toValue;
    id _byValue;
}

@property(retain) id fromValue;
@property(retain) id toValue;
@property(retain) id byValue;

@end

#import <QuartzCore/CAAnimationGroup.h>
#import <QuartzCore/CATransition.h>
