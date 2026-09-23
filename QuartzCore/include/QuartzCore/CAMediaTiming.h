#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/CABase.h>

typedef NSString *CAMediaTimingFillMode NS_TYPED_ENUM;

CA_EXPORT CAMediaTimingFillMode const kCAFillModeForwards NS_SWIFT_NAME(CAMediaTimingFillMode.forwards);
CA_EXPORT CAMediaTimingFillMode const kCAFillModeBackwards NS_SWIFT_NAME(CAMediaTimingFillMode.backwards);
CA_EXPORT CAMediaTimingFillMode const kCAFillModeBoth NS_SWIFT_NAME(CAMediaTimingFillMode.both);
CA_EXPORT CAMediaTimingFillMode const kCAFillModeRemoved NS_SWIFT_NAME(CAMediaTimingFillMode.removed);

@protocol CAMediaTiming

@property BOOL autoreverses;

@property CFTimeInterval beginTime;

@property CFTimeInterval duration;

@property(copy) CAMediaTimingFillMode fillMode;

@property CGFloat repeatCount;

@property CFTimeInterval repeatDuration;

@property CGFloat speed;

@property CFTimeInterval timeOffset;

@end
