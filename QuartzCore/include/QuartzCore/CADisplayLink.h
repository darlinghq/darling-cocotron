#import <Foundation/NSObject.h>
#import <Foundation/NSRunLoop.h>
#import <QuartzCore/CABase.h>

@class NSMutableArray;

@interface CADisplayLink : NSObject {
@private
    id _target;
    SEL _selector;
    id _display;
    NSMutableArray *_schedules;
    CFTimeInterval _timestamp;
    CFTimeInterval _targetTimestamp;
    CFTimeInterval _duration;
    NSInteger _preferredFramesPerSecond;
    BOOL _paused;
    BOOL _invalidated;
}

+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector;

@property (nonatomic, readonly) CFTimeInterval timestamp;
@property (nonatomic, readonly) CFTimeInterval targetTimestamp;
@property (nonatomic, readonly) CFTimeInterval duration;
@property (nonatomic) NSInteger preferredFramesPerSecond;
@property (nonatomic) NSInteger frameInterval;
@property (nonatomic, getter=isPaused) BOOL paused;

- (void)addToRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode;
- (void)removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode;
- (void)invalidate;

@end
