#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>

CA_EXPORT NSString *const kCAFillModeForwards;
CA_EXPORT NSString *const kCAFillModeBackwards;
CA_EXPORT NSString *const kCAFillModeBoth;
CA_EXPORT NSString *const kCAFillModeRemoved;

@protocol CAMediaTiming

@property BOOL autoreverses;

@property CFTimeInterval beginTime;

@property CFTimeInterval duration;

@property(copy) NSString *fillMode;

@property CGFloat repeatCount;

@property CFTimeInterval repeatDuration;

@property CGFloat speed;

@property CFTimeInterval timeOffset;

@end
