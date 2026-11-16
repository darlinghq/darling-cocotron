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
        _target = [target retain];
        _selector = selector;
        _display = [display retain];
        _schedules = [[NSMutableArray alloc] init];
        _preferredFramesPerSecond = 0;
        _refreshRate = [self _queryRefreshRate];
        _duration = 1.0 / _refreshRate;
    }
    return self;
}

- (id)display { return _display; }
- (CFTimeInterval)timestamp { return _timestamp; }
- (CFTimeInterval)targetTimestamp { return _targetTimestamp; }
- (CFTimeInterval)duration { return _duration; }
- (NSInteger)preferredFramesPerSecond { return _preferredFramesPerSecond; }
- (BOOL)isPaused { return _paused; }
- (void)setPaused:(BOOL)paused { _paused = paused; }

// The refresh rate of the display the link is bound to, in Hz: asked of the
// provider set by the layer above (the screen of a view or window), else the
// current mode of the main display. 60 Hz when nothing reports a rate.
- (double)_queryRefreshRate {
    double rate = 0;

    if (_refreshRateProvider != NULL) {
        rate = _refreshRateProvider();
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
    Block_release(_refreshRateProvider);
    _refreshRateProvider = provider != NULL ? Block_copy(provider) : NULL;
    [self _refreshRateMayHaveChanged];
}

// Called when the link is scheduled and, at most once a second, from the
// timer: the display (or its mode) may have changed under the link.
- (void)_refreshRateMayHaveChanged {
    double rate = [self _queryRefreshRate];

    _refreshRateCheckedAt = CACurrentMediaTime();
    if (rate == _refreshRate)
        return;
    _refreshRate = rate;
    _duration = 1.0 / rate;
    [self _rescheduleTimers];
}

- (NSInteger)frameInterval {
    return MAX(1, (NSInteger) lround(_refreshRate / [self _effectiveFramesPerSecond]));
}

// The rate the timers run at, never above the display's refresh rate. A frame
// rate range with a maximum takes precedence: its preferred rate if that lies
// in the range, else its maximum. Otherwise preferredFramesPerSecond applies,
// 0 meaning the display's maximum refresh rate.
- (NSInteger)_effectiveFramesPerSecond {
    NSInteger display = MAX(1, (NSInteger) lround(_refreshRate));
    NSInteger rate = display;

    if (_preferredFrameRateRange.maximum > 0) {
        float preferred = _preferredFrameRateRange.preferred;
        if (preferred >= _preferredFrameRateRange.minimum && preferred <= _preferredFrameRateRange.maximum &&
            preferred > 0)
            rate = (NSInteger) lroundf(preferred);
        else
            rate = (NSInteger) lroundf(_preferredFrameRateRange.maximum);
    } else if (_preferredFramesPerSecond > 0) {
        rate = _preferredFramesPerSecond;
    }
    return MIN(MAX(1, rate), display);
}

- (CAFrameRateRange)preferredFrameRateRange {
    return _preferredFrameRateRange;
}

- (void)setPreferredFrameRateRange:(CAFrameRateRange)range {
    if (CAFrameRateRangeIsEqualToRange(_preferredFrameRateRange, range)) return;
    _preferredFrameRateRange = range;
    [self _rescheduleTimers];
}

- (void)setFrameInterval:(NSInteger)frameInterval {
    if (frameInterval < 1) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink frameInterval must be positive"];
        return;
    }
    [self setPreferredFramesPerSecond:MAX(1, (NSInteger) lround(_refreshRate / frameInterval))];
}

- (void)setPreferredFramesPerSecond:(NSInteger)rate {
    if (rate < 0) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink preferredFramesPerSecond must not be negative"];
        return;
    }
    if (_preferredFramesPerSecond == rate) return;
    _preferredFramesPerSecond = rate;
    [self _rescheduleTimers];
}

- (void)_rescheduleTimers {
    NSArray *schedules = [[_schedules copy] autorelease];
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
    if (_invalidated || !runLoop || !mode) return;
    for (_CADisplayLinkSchedule *schedule in _schedules) {
        if (schedule->runLoop == runLoop && [schedule->mode isEqualToString:mode]) return;
    }
    _CADisplayLinkSchedule *schedule = [[_CADisplayLinkSchedule alloc] initWithRunLoop:runLoop mode:mode];
    // Before the new schedule exists: a changed rate reschedules the others.
    [self _refreshRateMayHaveChanged];
    [_schedules addObject:schedule];
    [self _scheduleTimer:schedule];
    [schedule release];
}

- (void)removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSRunLoopMode)mode {
    NSArray *schedules = [[_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) {
        if (schedule->runLoop == runLoop && [schedule->mode isEqualToString:mode]) {
            [schedule->timer invalidate];
            [_schedules removeObject:schedule];
        }
    }
}

- (void)_tick:(NSTimer *)timer {
    (void)timer;
    if (_paused || _invalidated) return;
    _timestamp = CACurrentMediaTime();
    if (_timestamp - _refreshRateCheckedAt >= 1.0)
        [self _refreshRateMayHaveChanged];
    NSInteger rate = [self _effectiveFramesPerSecond];
    _targetTimestamp = _timestamp + 1.0 / rate;
    ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, self);
}

- (void)setHighFrameRateReasons:(const uint32_t *)reasons count:(NSInteger)count {
    (void)reasons;
    (void)count;
}

- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    NSArray *schedules = [[_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) [schedule->timer invalidate];
    [_schedules removeAllObjects];
    [_target release];
    _target = nil;
    // The provider may own what the target owns; release it with the target.
    Block_release(_refreshRateProvider);
    _refreshRateProvider = NULL;
}

- (void)dealloc {
    [self invalidate];
    [_display release];
    Block_release(_refreshRateProvider);
    [_schedules release];
    [super dealloc];
}

@end
