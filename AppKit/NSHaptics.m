#import <AppKit/NSHaptics.h>

@interface NSNullHapticFeedbackPerformer : NSObject <NSHapticFeedbackPerformer>
@end

@implementation NSNullHapticFeedbackPerformer

- (void) performFeedbackPattern: (NSHapticFeedbackPattern) pattern
                performanceTime: (NSHapticFeedbackPerformanceTime) performanceTime
{
}

@end

@implementation NSHapticFeedbackManager

+ (id<NSHapticFeedbackPerformer>) defaultPerformer {
    static NSNullHapticFeedbackPerformer *performer = nil;
    if (performer == nil)
        performer = [[NSNullHapticFeedbackPerformer alloc] init];
    return performer;
}

@end

@implementation NSAlignmentFeedbackFilter

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
