#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>

typedef NS_ENUM(NSInteger, NSHapticFeedbackPattern) {
    NSHapticFeedbackPatternGeneric = 0,
    NSHapticFeedbackPatternAlignment,
    NSHapticFeedbackPatternLevelChange,
};

typedef NS_ENUM(NSInteger, NSHapticFeedbackPerformanceTime) {
    NSHapticFeedbackPerformanceTimeDefault = 0,
    NSHapticFeedbackPerformanceTimeNow,
    NSHapticFeedbackPerformanceTimeDrawCompleted,
};

@protocol NSHapticFeedbackPerformer <NSObject>
- (void) performFeedbackPattern: (NSHapticFeedbackPattern) pattern
                performanceTime: (NSHapticFeedbackPerformanceTime) performanceTime;
@end

@interface NSHapticFeedbackManager : NSObject

// The performer does nothing: there is no haptic hardware behind Darling. macOS
// behaves the same way on a Mac without a Force Touch trackpad.
+ (id<NSHapticFeedbackPerformer>) defaultPerformer;

@end

// Still unimplemented.
@interface NSAlignmentFeedbackFilter : NSObject

@end
