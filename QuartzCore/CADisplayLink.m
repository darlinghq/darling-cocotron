#import <QuartzCore/CADisplayLink.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

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
- (void)_tick:(NSTimer *)timer;
- (void)_scheduleTimer:(_CADisplayLinkSchedule *)schedule;
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
        _duration = 1.0 / 60.0;
        _preferredFramesPerSecond = 60;
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

- (NSInteger)frameInterval {
    NSInteger rate = _preferredFramesPerSecond > 0 ? _preferredFramesPerSecond : 60;
    return MAX(1, 60 / rate);
}

- (void)setFrameInterval:(NSInteger)frameInterval {
    if (frameInterval < 1) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink frameInterval must be positive"];
        return;
    }
    [self setPreferredFramesPerSecond:MAX(1, 60 / frameInterval)];
}

- (void)setPreferredFramesPerSecond:(NSInteger)rate {
    if (rate < 0) {
        [NSException raise:NSInvalidArgumentException format:@"CADisplayLink preferredFramesPerSecond must not be negative"];
        return;
    }
    if (_preferredFramesPerSecond == rate) return;
    _preferredFramesPerSecond = rate;
    NSArray *schedules = [[_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) {
        [schedule->timer invalidate];
        [schedule->timer release];
        schedule->timer = nil;
        [self _scheduleTimer:schedule];
    }
}

- (void)_scheduleTimer:(_CADisplayLinkSchedule *)schedule {
    NSInteger rate = _preferredFramesPerSecond > 0 ? _preferredFramesPerSecond : 60;
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
    NSInteger rate = _preferredFramesPerSecond > 0 ? _preferredFramesPerSecond : 60;
    _targetTimestamp = _timestamp + 1.0 / rate;
    ((void (*)(id, SEL, id))objc_msgSend)(_target, _selector, self);
}

- (void)setHighFrameRateReasons:(const uint32_t *)reasons count:(NSInteger)count {
    (void)reasons;
    (void)count;
    // The current Darling display backend runs at a fixed 60 Hz.
}

- (void)invalidate {
    if (_invalidated) return;
    _invalidated = YES;
    NSArray *schedules = [[_schedules copy] autorelease];
    for (_CADisplayLinkSchedule *schedule in schedules) [schedule->timer invalidate];
    [_schedules removeAllObjects];
    [_target release];
    _target = nil;
}

- (void)dealloc {
    [self invalidate];
    [_display release];
    [_schedules release];
    [super dealloc];
}

@end
