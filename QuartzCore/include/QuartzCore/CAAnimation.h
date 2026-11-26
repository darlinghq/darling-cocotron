#import <Foundation/NSObject.h>
#import <QuartzCore/LegacyIvarLayout.h>
#import <QuartzCore/CAAction.h>
#import <QuartzCore/CABase.h>
#import <QuartzCore/CAMediaTiming.h>
#import <CoreGraphics/CGPath.h>

@class CAMediaTimingFunction, CAPropertyAnimation, CAValueFunction;
@protocol CAAnimationDelegate;

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
    NS_LEGACY_IVAR_PAD(_legacyPadCAAnimation, 4)
    NS_EXTRA_IVARS_BEGIN(CAAnimation)
        id _delegate;
        BOOL _removedOnCompletion;
        CAMediaTimingFunction *_timingFunction;
        BOOL _autoreverses;
        CFTimeInterval _beginTime;
        CFTimeInterval _duration;
        NSString *_fillMode;
        float _repeatCount;
        CFTimeInterval _repeatDuration;
        float _speed;
        CFTimeInterval _timeOffset;
        NSMutableDictionary *_undefinedKeyValues;
    NS_EXTRA_IVARS_END(CAAnimation)
}

+ (instancetype) animation;
+ (id) defaultValueForKey: (NSString *) key;

// Retained, unlike most delegates.
@property(retain) id <CAAnimationDelegate> delegate;

@property(getter=isRemovedOnCompletion) BOOL removedOnCompletion;

@property(retain) CAMediaTimingFunction *timingFunction;

@end

@protocol CAAnimationDelegate <NSObject>
@optional
- (void) animationDidStart: (CAAnimation *) animation;
- (void) animationDidStop: (CAAnimation *) animation finished: (BOOL) finished;
@end

#define _NS_SIDE_CAPropertyAnimation 0, 1,
@interface CAPropertyAnimation : CAAnimation {
    NS_EXTRA_IVARS_BEGIN(CAPropertyAnimation)
        NSString *_keyPath;
        BOOL _additive;
        BOOL _cumulative;
        CAValueFunction *_valueFunction;
    NS_SIDE_IVARS_END(CAPropertyAnimation)
}

+ (instancetype) animationWithKeyPath: (NSString *) keyPath __attribute__((returns_nonnull));
@property(copy) NSString *keyPath;
@property(getter=isAdditive) BOOL additive;
@property(getter=isCumulative) BOOL cumulative;
@property(retain) CAValueFunction *valueFunction;

@end

#define _NS_SIDE_CAKeyframeAnimation 0, 1,
@interface CAKeyframeAnimation : CAPropertyAnimation {
    NS_EXTRA_IVARS_BEGIN(CAKeyframeAnimation)
        NSArray *_values;
        CGPathRef _path;
        NSArray *_keyTimes;
        NSArray *_timingFunctions;
        NSString *_calculationMode;
        NSArray *_tensionValues;
        NSArray *_continuityValues;
        NSArray *_biasValues;
        NSString *_rotationMode;
    NS_SIDE_IVARS_END(CAKeyframeAnimation)
}

@property(copy) NSArray *values;
@property CGPathRef path;
@property(copy) NSArray<NSNumber *> *keyTimes;
@property(copy) NSArray<CAMediaTimingFunction *> *timingFunctions;
@property(copy) NSString *calculationMode;
@property(copy) NSArray<NSNumber *> *tensionValues;
@property(copy) NSArray<NSNumber *> *continuityValues;
@property(copy) NSArray<NSNumber *> *biasValues;
@property(copy) NSString *rotationMode;

@end

#define _NS_SIDE_CABasicAnimation 0, 1,
@interface CABasicAnimation : CAPropertyAnimation {
    NS_EXTRA_IVARS_BEGIN(CABasicAnimation)
        id _fromValue;
        id _toValue;
        id _byValue;
    NS_SIDE_IVARS_END(CABasicAnimation)
}

@property(retain) id fromValue;
@property(retain) id toValue;
@property(retain) id byValue;

@end

#import <QuartzCore/CAAnimationGroup.h>
#import <QuartzCore/CATransition.h>
