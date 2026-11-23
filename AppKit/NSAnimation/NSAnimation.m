/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/NSAnimation.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSValue.h>

NSString *const NSAnimationProgressMarkNotification =
        @"NSAnimationProgressMarkNotification";

// GUESS: the public header declares the key but gives no value; the
// documentation names it NSAnimationProgressMark, so the string is that name
NSString *NSAnimationProgressMark = @"NSAnimationProgressMark";

NSString *NSAnimationTriggerOrderIn = @"NSAnimationTriggerOrderIn";
NSString *NSAnimationTriggerOrderOut = @"NSAnimationTriggerOrderOut";

NSString *NSAnimationRunLoopMode = @"NSAnimationRunLoopMode";

@implementation NSAnimation

- initWithDuration: (NSTimeInterval) duration
        animationCurve: (NSAnimationCurve) curve
{
    _duration = duration;
    _curve = curve;
    _frameRate = 10;
    _blockingMode = NSAnimationBlocking;
    _delegate = nil;
    _progressMarks = [NSMutableArray new];
    _currentValue = 0;
    _runLoopModes = nil; // nil== default, modal and event tracking
    return self;
}

- (void) dealloc {
    [_progressMarks release];
    [_runLoopModes release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSAnimation *result = NSCopyObject(self, 0, zone);

    result->_currentValue = 0;
    result->_currentProgress = 0;
    result->_progressMarks = [_progressMarks mutableCopy];
    result->_runLoopModes = [_runLoopModes copy];
    result->_isAnimating = NO;
    result->_timer = nil;

    return result;
}

- (NSTimeInterval) duration {
    return _duration;
}

- (NSAnimationCurve) animationCurve {
    return _curve;
}

- (float) frameRate {
    return _frameRate;
}

- (NSAnimationBlockingMode) animationBlockingMode {
    return _blockingMode;
}

- delegate {
    return _delegate;
}

- (NSArray *) progressMarks {
    return _progressMarks;
}

- (void) setDuration: (NSTimeInterval) interval {
    _duration = interval;
}

- (void) setAnimationCurve: (NSAnimationCurve) curve {
    _curve = curve;
}

- (void) setFrameRate: (float) fps {
    _frameRate = fps;
}

- (void) setAnimationBlockingMode: (NSAnimationBlockingMode) mode {
    _blockingMode = mode;
}

- (void) setDelegate: delegate {
    _delegate = delegate;
}

- (void) setProgressMarks: (NSArray *) marks {
    // nil clears every mark; the array must stay non-nil for -addProgressMark:
    NSMutableArray *mcopy =
            marks != nil ? [marks mutableCopy] : [NSMutableArray new];
    [_progressMarks release];
    _progressMarks = mcopy;
}

- (void) addProgressMark: (NSAnimationProgress) mark {
    if (mark < 0)
        mark = 0;
    else if (mark > 1)
        mark = 1;

    [_progressMarks addObject: [NSNumber numberWithFloat: mark]];
}

- (void) removeProgressMark: (NSAnimationProgress) mark {
    // GUESS: the argument is pinned like -addProgressMark: pins it, so
    // removing -3 removes the mark that adding -3 stored (at 0.0)
    mark = MAX(0.0f, MIN(1.0f, mark));
    // GUESS: the documentation does not say what happens when the same value
    // was added twice; every entry with that value is removed (rejected
    // alternative: remove only the first one added)
    for (NSInteger i = [_progressMarks count] - 1; i >= 0; i--)
        if ([[_progressMarks objectAtIndex: i] floatValue] == mark)
            [_progressMarks removeObjectAtIndex: i];
}

- (NSAnimationProgress) currentProgress {
    return _currentProgress;
}

- (float) currentValue {
    // documented: the delegate's value for the current progress wins, and it
    // may lie outside 0.0 ... 1.0
    if ([_delegate respondsToSelector: @selector(animation:valueForProgress:)])
        return [_delegate animation: self valueForProgress: _currentProgress];

    // The direction of the curves is documented (NSAnimationEaseIn "slows
    // down as it reaches the end", so its value runs ahead of the progress;
    // NSAnimationEaseOut "slowly speeds up from the start", so it lags), the
    // formula is not. GUESS: the usual polynomial curves (rejected
    // alternatives: a cubic Bezier as Core Animation's timing functions use,
    // a sine ease). All of them map 0.0 to 0.0 and 1.0 to 1.0.
    float progress = _currentProgress;

    switch (_curve) {
    case NSAnimationEaseIn:
        return 1 - (1 - progress) * (1 - progress);
    case NSAnimationEaseOut:
        return progress * progress;
    case NSAnimationEaseInOut:
        return progress * progress * (3 - 2 * progress);
    case NSAnimationLinear:
        break;
    }
    return progress;
}

- (BOOL) isAnimating {
    return _isAnimating;
}

- (NSArray *) runLoopModesForAnimating {
    return _runLoopModes;
}

- (void) setCurrentProgress: (NSAnimationProgress) progress {
    NSAnimationProgress previous = _currentProgress;

    // documented: values outside 0.0 ... 1.0 are pinned
    _currentProgress = MAX(0.0f, MIN(1.0f, progress));

    // GUESS: the documentation does not say when a mark counts as reached. A
    // running animation reaches a mark when its progress moves forward from
    // below the mark to the mark or beyond. A mark is not reached when
    // progress moves backwards or when the animation is not running, and a
    // mark at 0.0 is never reached (progress starts there; rejected
    // alternative: fire marks at 0.0 when the animation starts).
    if (!_isAnimating || _currentProgress <= previous)
        return;
    NSAnimationProgress reached = _currentProgress;

    // GUESS: marks reached in one step are reported in ascending order, and a
    // value that was added more than once is reported once
    NSArray *ordered = [_progressMarks sortedArrayUsingSelector: @selector(compare:)];
    float lastReported = -1;
    for (NSNumber *entry in ordered) {
        // a delegate callback may have stopped the animation
        if (!_isAnimating)
            break;

        float mark = [entry floatValue];
        if (mark == lastReported || mark <= previous || mark > reached)
            continue;
        lastReported = mark;

        if ([_delegate respondsToSelector: @selector(animation:didReachProgressMark:)])
            [_delegate animation: self didReachProgressMark: mark];

        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSAnimationProgressMarkNotification
                              object: self
                            userInfo: [NSDictionary dictionaryWithObject: entry
                                                                  forKey: NSAnimationProgressMark]];
    }
}

- (void) clearStartAnimation {
    NSUnimplementedMethod();
}

- (void) clearStopAnimation {
    NSUnimplementedMethod();
}

- (void) _setCurrentProgressAndEndIfNeeded: (NSAnimationProgress) progress {
    if (_isAnimating) {
        progress = MAX(0.0, MIN(1.0, progress));
        [self setCurrentProgress: progress];

        if (progress >= 1.0) {
            if ([_delegate respondsToSelector: @selector(animationDidEnd:)])
                [_delegate performSelector: @selector(animationDidEnd:)
                                withObject: self];

            [self stopAnimation];
        }
    }
}

- (void) timer: (NSTimer *) timer {
    NSTimeInterval currentTime = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsedTime = currentTime - _startTime;
    CGFloat progress = elapsedTime / _duration;

    [self _setCurrentProgressAndEndIfNeeded: progress];
}

- (void) startAnimation {
    if (!_isAnimating) {

        if ([_delegate respondsToSelector: @selector(animationShouldStart:)])
            if (![_delegate animationShouldStart: self])
                return;

        // documented: an animation that finished starts again at 0.0
        if (_currentProgress >= 1.0)
            _currentProgress = 0;

        [self retain];
        _isAnimating = YES;
        _startTime = [NSDate timeIntervalSinceReferenceDate];

        switch (_blockingMode) {

        case NSAnimationBlocking:
            _timer = [NSTimer timerWithTimeInterval: 1.0 / _frameRate
                                             target: self
                                           selector: @selector(timer:)
                                           userInfo: nil
                                            repeats: YES];

            [[NSRunLoop currentRunLoop] addTimer: _timer
                                         forMode: NSAnimationRunLoopMode];

            while (_isAnimating)
                [[NSRunLoop currentRunLoop]
                           runMode: NSAnimationRunLoopMode
                        beforeDate: [NSDate dateWithTimeIntervalSinceNow:
                                                    _duration]];

            [self _setCurrentProgressAndEndIfNeeded: 1.0];
            break;

        case NSAnimationNonblocking:
            _timer = [NSTimer scheduledTimerWithTimeInterval: 1.0 / _frameRate
                                                      target: self
                                                    selector: @selector(timer:)
                                                    userInfo: nil
                                                     repeats: YES];
            break;

        case NSAnimationNonblockingThreaded:
            NSUnimplementedMethod();
            break;
        }
    }
}

- (void) stopAnimation {
    if (_isAnimating) {
        _isAnimating = NO;
        [_timer invalidate];
        _timer = nil;
        [self autorelease];
    }
}

- (void) startWhenAnimation: (NSAnimation *) animation
            reachesProgress: (NSAnimationProgress) progress
{
    NSUnimplementedMethod();
}

- (void) stopWhenAnimation: (NSAnimation *) animation
           reachesProgress: (NSAnimationProgress) progress
{
    NSUnimplementedMethod();
}

@end
