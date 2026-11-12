#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSObject.h>

@class NSHapticFeedbackManager;

typedef NS_ENUM(NSInteger, NSHapticFeedbackPattern) {
    NSHapticFeedbackPatternGeneric = 0,
    NSHapticFeedbackPatternAlignment,
    NSHapticFeedbackPatternLevelChange,
} NS_SWIFT_NAME(NSHapticFeedbackManager.FeedbackPattern);

typedef NS_ENUM(NSInteger, NSHapticFeedbackPerformanceTime) {
    NSHapticFeedbackPerformanceTimeDefault = 0,
    NSHapticFeedbackPerformanceTimeNow,
    NSHapticFeedbackPerformanceTimeDrawCompleted,
} NS_SWIFT_NAME(NSHapticFeedbackManager.PerformanceTime);

@protocol NSHapticFeedbackPerformer <NSObject>
- (void) performFeedbackPattern: (NSHapticFeedbackPattern) pattern
                performanceTime: (NSHapticFeedbackPerformanceTime) performanceTime;
@end

@interface NSHapticFeedbackManager : NSObject

// The performer does nothing: there is no haptic hardware behind Darling. macOS
// behaves the same way on a Mac without a Force Touch trackpad.
@property (class, readonly, strong) id<NSHapticFeedbackPerformer> defaultPerformer;

@end

// Still unimplemented.
@interface NSAlignmentFeedbackFilter : NSObject

@end
