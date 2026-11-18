#import <QuartzCore/CADisplayLink.h>
#import <QuartzCore/CAFrameRateRange.h>
#include <Block.h>
#include <math.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <CoreGraphics/CGDirectDisplay.h>

@interface _CADisplayLinkSchedule : NSObject {
@public
    NSRunLoop *runLoop;
    NSRunLoopMode mode;
    NSTimer *timer;
}
- (instancetype)initWithRunLoop:(NSRunLoop *)aRunLoop mode:(NSRunLoopMode)aMode;
@end

@implementation _CADisplayLinkSchedule
- (instancetype)initWithRunLoop:(NSRunLoop *)aRunLoop mode:(NSRunLoopMode)aMode {
    if ((self = [super init])) {
        runLoop = [aRunLoop retain];
        mode = [aMode copy];
    }
    return self;
}

- (void)dealloc {
    [timer invalidate];
    [timer release];
    [mode release];
    [runLoop release];
    [super dealloc];
}
@end

@interface CADisplayLink ()
- (instancetype)_initWithDisplay:(id)display target:(id)target selector:(SEL)selector;
- (NSInteger)_effectiveFramesPerSecond;
- (void)_rescheduleTimers;
- (void)_tick:(NSTimer *)timer;
- (void)_scheduleTimer:(_CADisplayLinkSchedule *)schedule;
- (double)_queryRefreshRate;
- (void)_refreshRateMayHaveChanged;
- (void)_setRefreshRateProvider:(double (^)(void))provider;
@end

@implementation CADisplayLink

+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector {
    return [[[self alloc] _initWithDisplay:nil target:target selector:selector] autorelease];
}

// The macOS SwiftUI SPI requests a link for a particular display.
+ (instancetype)displayLinkWithDisplay:(id)display target:(id)target selector:(SEL)selector {
    return [[[self alloc] _initWithDisplay:display target:target selector:selector] autorelease];
}

- (instancetype)_initWithDisplay:(id)display target:(id)target selector:(SEL)selector {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        [self release];
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink requires a target and one-argument selector"];
        return nil;
    }
    if ((self = [super init])) {
        NS_EXTRA(CADisplayLink, self)->_target = [target retain];
        NS_EXTRA(CADisplayLink, self)->_selector = selector;
        NS_EXTRA(CADisplayLink, self)->_display = [display retain];
        NS_EXTRA(CADisplayLink, self)->_schedules = [[NSMutableArray alloc] init];
        NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond = 0;
        NS_EXTRA(CADisplayLink, self)->_refreshRate = [self _queryRefreshRate];
        NS_EXTRA(CADisplayLink, self)->_duration = 1.0 / NS_EXTRA(CADisplayLink, self)->_refreshRate;
    }
    return self;
}

- (id)display { return NS_EXTRA(CADisplayLink, self)->_display; }
- (CFTimeInterval)timestamp { return NS_EXTRA(CADisplayLink, self)->_timestamp; }
- (CFTimeInterval)targetTimestamp { return NS_EXTRA(CADisplayLink, self)->_targetTimestamp; }
- (CFTimeInterval)duration { return NS_EXTRA(CADisplayLink, self)->_duration; }
- (NSInteger)preferredFramesPerSecond { return NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond; }
- (BOOL)isPaused { return NS_EXTRA(CADisplayLink, self)->_paused; }
- (void)setPaused:(BOOL)paused { NS_EXTRA(CADisplayLink, self)->_paused = paused; }

// The refresh rate of the display the link is bound to, in Hz: asked of the
// provider set by the layer above (the screen of a view or window), else the
// current mode of the main display. 60 Hz when nothing reports a rate.
- (double)_queryRefreshRate {
    double rate = 0;

    if (NS_EXTRA(CADisplayLink, self)->_refreshRateProvider != NULL) {
        rate = NS_EXTRA(CADisplayLink, self)->_refreshRateProvider();
    } else {
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(CGMainDisplayID());
        if (mode != NULL) {
            rate = CGDisplayModeGetRefreshRate(mode);
            CGDisplayModeRelease(mode);
        }
    }
    return rate > 0 && isfinite(rate) ? rate : 60.0;
}

- (void)_setRefreshRateProvider:(double (^)(void))provider {
    Block_release(NS_EXTRA(CADisplayLink, self)->_refreshRateProvider);
    NS_EXTRA(CADisplayLink, self)->_refreshRateProvider = provider != NULL ? Block_copy(provider) : NULL;
    [self _refreshRateMayHaveChanged];
}

// Called when the link is scheduled and, at most once a second, from the
// timer: the display (or its mode) may have changed under the link.
- (void)_refreshRateMayHaveChanged {
    double rate = [self _queryRefreshRate];

    NS_EXTRA(CADisplayLink, self)->_refreshRateCheckedAt = CACurrentMediaTime();
    if (rate == NS_EXTRA(CADisplayLink, self)->_refreshRate)
        return;
    NS_EXTRA(CADisplayLink, self)->_refreshRate = rate;
    NS_EXTRA(CADisplayLink, self)->_duration = 1.0 / rate;
    [self _rescheduleTimers];
}

- (NSInteger)frameInterval {
    return MAX(1, (NSInteger) lround(NS_EXTRA(CADisplayLink, self)->_refreshRate / [self _effectiveFramesPerSecond]));
}

// The rate the timers run at, never above the display's refresh rate. A frame
// rate range with a maximum takes precedence: its preferred rate if that lies
// in the range, else its maximum. Otherwise preferredFramesPerSecond applies,
// 0 meaning the display's maximum refresh rate.
- (NSInteger)_effectiveFramesPerSecond {
    NSInteger display = MAX(1, (NSInteger) lround(NS_EXTRA(CADisplayLink, self)->_refreshRate));
    NSInteger rate = display;

    if (NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange.maximum > 0) {
        float preferred = NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange.preferred;
        if (preferred >= NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange.minimum && preferred <= NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange.maximum &&
            preferred > 0)
            rate = (NSInteger) lroundf(preferred);
        else
            rate = (NSInteger) lroundf(NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange.maximum);
    } else if (NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond > 0) {
        rate = NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond;
    }
    return MIN(MAX(1, rate), display);
}

- (CAFrameRateRange)preferredFrameRateRange {
    return NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (CAFrameRateRangeIsEqualToRange(NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange, range)) return;
    NS_EXTRA(CADisplayLink, self)->_preferredFrameRateRange = range;
    [self _rescheduleTimers];
}

- (void)setFrameInterval:(NSInteger)frameInterval {
    if (frameInterval < 1) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink frameInterval must be positive"];
        return;
    }
    [self setPreferredFramesPerSecond:MAX(1, (NSInteger) lround(NS_EXTRA(CADisplayLink, self)->_refreshRate / frameInterval))];
}

- (void)setPreferredFramesPerSecond:(NSInteger)rate {
    if (rate < 0) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink preferredFramesPerSecond must not be negative"];
        return;
    }
    if (NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond == rate) return;
    NS_EXTRA(CADisplayLink, self)->_preferredFramesPerSecond = rate;
    [self _rescheduleTimers];
}

- (void)_rescheduleTimers {
    NSArray *schedules = [[NS_EXTRA(CADisplayLink, self)->_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) {
        [schedule->timer invalidate];
        [schedule->timer release];
        schedule->timer = nil;
        [self _scheduleTimer:schedule];
    }
}

- (void)_scheduleTimer:(_CADisplayLinkSchedule *)schedule {
    NSInteger rate = [self _effectiveFramesPerSecond];
    schedule->timer = [[NSTimer timerWithTimeInterval:1.0 / rate
                                             target:self
                                           selector:@selector(_tick:)
                                           userInfo:nil
                                            repeats:YES] retain];
    [schedule->runLoop addTimer:schedule->timer forMode:schedule->mode];
}

- (void)addToRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode {
    if (NS_EXTRA(CADisplayLink, self)->_invalidated || !runLoop || !mode) return;
    for (_CADisplayLinkSchedule *schedule in NS_EXTRA(CADisplayLink, self)->_schedules) {
        if (schedule->runLoop == runLoop && [schedule->mode isEqualToString:mode]) return;
    }
    _CADisplayLinkSchedule *schedule = [[_CADisplayLinkSchedule alloc] initWithRunLoop:runLoop mode:mode];
    // Before the new schedule exists: a changed rate reschedules the others.
    [self _refreshRateMayHaveChanged];
    [NS_EXTRA(CADisplayLink, self)->_schedules addObject:schedule];
    [self _scheduleTimer:schedule];
    [schedule release];
}

- (void)removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode {
    NSArray *schedules = [[NS_EXTRA(CADisplayLink, self)->_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) {
        if (schedule->runLoop == runLoop && [schedule->mode isEqualToString:mode]) {
            [schedule->timer invalidate];
            [NS_EXTRA(CADisplayLink, self)->_schedules removeObject:schedule];
        }
    }
}

- (void)_tick:(NSTimer *)timer {
    (void)timer;
    if (NS_EXTRA(CADisplayLink, self)->_paused || NS_EXTRA(CADisplayLink, self)->_invalidated) return;
    NS_EXTRA(CADisplayLink, self)->_timestamp = CACurrentMediaTime();
    if (NS_EXTRA(CADisplayLink, self)->_timestamp - NS_EXTRA(CADisplayLink, self)->_refreshRateCheckedAt >= 1.0)
        [self _refreshRateMayHaveChanged];
    NSInteger rate = [self _effectiveFramesPerSecond];
    NS_EXTRA(CADisplayLink, self)->_targetTimestamp = NS_EXTRA(CADisplayLink, self)->_timestamp + 1.0 / rate;
    ((void (*)(id, SEL, id))objc_msgSend)(NS_EXTRA(CADisplayLink, self)->_target, NS_EXTRA(CADisplayLink, self)->_selector, self);
}

- (void)setHighFrameRateReasons:(const uint32_t *)reasons count:(NSInteger)count {
    (void)reasons;
    (void)count;
}

- (void)invalidate {
    if (NS_EXTRA(CADisplayLink, self)->_invalidated) return;
    NS_EXTRA(CADisplayLink, self)->_invalidated = YES;
    NSArray *schedules = [[NS_EXTRA(CADisplayLink, self)->_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) [schedule->timer invalidate];
    [NS_EXTRA(CADisplayLink, self)->_schedules removeAllObjects];
    [NS_EXTRA(CADisplayLink, self)->_target release];
    NS_EXTRA(CADisplayLink, self)->_target = nil;
    // The provider may own what the target owns; release it with the target.
    Block_release(NS_EXTRA(CADisplayLink, self)->_refreshRateProvider);
    NS_EXTRA(CADisplayLink, self)->_refreshRateProvider = NULL;
}

- (void)dealloc {
    [self invalidate];
    [NS_EXTRA(CADisplayLink, self)->_display release];
    Block_release(NS_EXTRA(CADisplayLink, self)->_refreshRateProvider);
    [NS_EXTRA(CADisplayLink, self)->_schedules release];
    NS_EXTRA_FREE(CADisplayLink, self);
    [super dealloc];
}

@end
