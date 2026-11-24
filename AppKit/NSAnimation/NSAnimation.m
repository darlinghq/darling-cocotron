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
#include <math.h>
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

// The public header declares the key without a value; the string is the key's own name (observed
// on macOS 10.14.4 and 26.7.3).
NSString *NSAnimationProgressMark = @"NSAnimationProgressMark";

NSString *NSAnimationTriggerOrderIn = @"NSAnimationTriggerOrderIn";
NSString *NSAnimationTriggerOrderOut = @"NSAnimationTriggerOrderOut";

NSString *NSAnimationRunLoopMode = @"NSAnimationRunLoopMode";

@implementation NSAnimation

// The animation that triggers keeps one entry per animation linked to it:
// the linked animation (not retained), the progress and whether it stops
// (YES) or starts (NO) at that progress.
static void addLink(NSAnimation *trigger, NSAnimation *dependent,
        NSAnimationProgress progress, BOOL stop)
{
    NSMutableArray *links = NS_EXTRA(NSAnimation, trigger)->_linkedAnimations;

    if (links == nil)
        links = NS_EXTRA(NSAnimation, trigger)->_linkedAnimations =
                [NSMutableArray new];

    [links addObject:
                   [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSValue valueWithNonretainedObject: dependent], @"animation",
                                         [NSNumber numberWithFloat: progress], @"progress",
                                         [NSNumber numberWithBool: stop], @"stop",
                                         nil]];
}

static void removeLink(NSAnimation *trigger, NSAnimation *dependent, BOOL stop) {
    if (trigger == nil)
        return;

    NSMutableArray *links = NS_EXTRA(NSAnimation, trigger)->_linkedAnimations;

    for (NSInteger i = [links count] - 1; i >= 0; i--) {
        NSDictionary *link = [links objectAtIndex: i];

        if ([[link objectForKey: @"animation"] nonretainedObjectValue] == dependent &&
                [[link objectForKey: @"stop"] boolValue] == stop)
            [links removeObjectAtIndex: i];
    }
}

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
    if (NS_EXTRA_ALLOCATED(NSAnimation, self)) {
        [self clearStartAnimation];
        [self clearStopAnimation];

        // animations linked to this one must not keep pointing at it
        for (NSDictionary *link in NS_EXTRA(NSAnimation, self)->_linkedAnimations) {
            NSAnimation *dependent = [[link objectForKey: @"animation"] nonretainedObjectValue];
            if ([[link objectForKey: @"stop"] boolValue])
                NS_EXTRA(NSAnimation, dependent)->_stopAnimation = nil;
            else
                NS_EXTRA(NSAnimation, dependent)->_startAnimation = nil;
        }
        [NS_EXTRA(NSAnimation, self)->_linkedAnimations release];
    }
    NS_EXTRA_FREE(NSAnimation, self);
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

    // Observed on macOS 10.14.4 and 26.7.3: a copy starts and stops with the same animations at the
    // same progress as the original (the animations that depend on the original are not copied).
    // Test: appkit-nsanimation-linked-animations.
    NS_EXTRA_COPY(NSAnimation, result, self);
    NS_EXTRA(NSAnimation, result)->_linkedAnimations = nil;
    NS_EXTRA(NSAnimation, result)->_markLowInclusive = NO;
    NS_EXTRA(NSAnimation, result)->_markLow = 0;
    for (int stop = 0; stop <= 1; stop++) {
        NSAnimation *trigger = stop ? NS_EXTRA(NSAnimation, self)->_stopAnimation
                                    : NS_EXTRA(NSAnimation, self)->_startAnimation;
        if (trigger == nil)
            continue;
        for (NSDictionary *link in NS_EXTRA(NSAnimation, trigger)->_linkedAnimations) {
            if ([[link objectForKey: @"animation"] nonretainedObjectValue] == self &&
                    [[link objectForKey: @"stop"] boolValue] == (BOOL) stop)
                addLink(trigger, result, [[link objectForKey: @"progress"] floatValue], stop);
        }
    }

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

// Observed on macOS 10.14.4 and 26.7.3 (black-box, tier 2; probe 7 of the cristim batch10b
// evidence): a mark outside 0.0 ... 1.0 is ignored, not pinned; the marks are kept in ascending
// order, equal values included; removing a value removes every entry with it.
// Test: appkit-nsanimation-progress-marks.
- (void) addProgressMark: (NSAnimationProgress) mark {
    if (!(mark >= 0 && mark <= 1))
        return;

    NSUInteger index = 0;
    while (index < [_progressMarks count] && [[_progressMarks objectAtIndex: index] floatValue] <= mark)
        index++;
    [_progressMarks insertObject: [NSNumber numberWithFloat: mark] atIndex: index];
}

- (void) removeProgressMark: (NSAnimationProgress) mark {
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

    // The value of the curve at the current progress. Observed on macOS 10.14.4 and 26.7.3
    // (black-box, tier 2; probe 7 of the cristim batch10b evidence): sine curves, EaseIn
    // 1 - cos(progress * pi / 2) (starts slowly), EaseOut sin(progress * pi / 2) and EaseInOut
    // (1 - cos(progress * pi)) / 2. Test: appkit-nsanimation-current-value.
    double progress = _currentProgress;

    switch (_curve) {
    case NSAnimationEaseIn:
        return 1 - cos(progress * M_PI_2);
    case NSAnimationEaseOut:
        return sin(progress * M_PI_2);
    case NSAnimationEaseInOut:
        return (1 - cos(progress * M_PI)) / 2;
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

// Progress marks and links. Observed on macOS 10.14.4 and 26.7.3 (black-box, tier 2; probe 7 of
// the cristim batch10b evidence):
// - values outside 0.0 ... 1.0 are pinned;
// - nothing is reported while the animation is not running;
// - starting the animation starts a pass over the marks at the current progress (0.0 for one that
//   finished); a running animation reports every mark whose value was reached since the last
//   report, in ascending order, a value added twice twice, and a mark at 0.0 with the first
//   update. A mark is reported once per pass: moving the progress backwards and forwards again
//   reports nothing more, and marks below the progress the animation started at are never
//   reported;
// - a delegate that stops the animation from a callback does not end the reports of that update;
// - the delegate is told, then NSAnimationProgressMarkNotification is posted;
// - the animations linked with -startWhenAnimation: / -stopWhenAnimation: take part in the same
//   pass as the marks of the animation they wait for, without showing as marks (not in
//   -progressMarks, no delegate message).
// Tests: appkit-nsanimation-progress-marks, appkit-nsanimation-linked-animations.
- (void) setCurrentProgress: (NSAnimationProgress) progress {
    // documented: values outside 0.0 ... 1.0 are pinned
    _currentProgress = MAX(0.0f, MIN(1.0f, progress));

    if (!_isAnimating)
        return;

    NSAnimationProgress reached = _currentProgress;
    float low = NS_EXTRA(NSAnimation, self)->_markLow;
    BOOL inclusive = NS_EXTRA(NSAnimation, self)->_markLowInclusive;

    if (reached < low || (reached == low && !inclusive))
        return;
    NS_EXTRA(NSAnimation, self)->_markLow = reached;
    NS_EXTRA(NSAnimation, self)->_markLowInclusive = NO;

    // the events of this update: marks and links, ascending by progress, marks first
    NSMutableArray *events = [NSMutableArray array];
    for (NSNumber *entry in _progressMarks) {
        float mark = [entry floatValue];
        if ((inclusive ? mark >= low : mark > low) && mark <= reached)
            [events addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                                     entry, @"progress", nil]];
    }
    for (NSDictionary *link in NS_EXTRA_ALLOCATED(NSAnimation, self) ? NS_EXTRA(NSAnimation, self)->_linkedAnimations : nil) {
        float trigger = [[link objectForKey: @"progress"] floatValue];
        if ((inclusive ? trigger >= low : trigger > low) && trigger <= reached)
            [events addObject: link];
    }
    // insertion sort by progress; equal values keep their order (marks before links)
    for (NSUInteger i = 1; i < [events count]; i++) {
        NSDictionary *event = [[[events objectAtIndex: i] retain] autorelease];
        NSInteger j = i - 1;
        while (j >= 0 && [[[events objectAtIndex: j] objectForKey: @"progress"]
                                 compare: [event objectForKey: @"progress"]] == NSOrderedDescending) {
            [events replaceObjectAtIndex: j + 1 withObject: [events objectAtIndex: j]];
            j--;
        }
        [events replaceObjectAtIndex: j + 1 withObject: event];
    }

    for (NSDictionary *event in events) {
        NSNumber *entry = [event objectForKey: @"progress"];

        if ([event objectForKey: @"animation"] == nil) {
            if ([_delegate respondsToSelector: @selector(animation:didReachProgressMark:)])
                [_delegate animation: self didReachProgressMark: [entry floatValue]];

            [[NSNotificationCenter defaultCenter]
                    postNotificationName: NSAnimationProgressMarkNotification
                                  object: self
                                userInfo: [NSDictionary dictionaryWithObject: entry
                                                                      forKey: NSAnimationProgressMark]];
            continue;
        }

        // an earlier callback may have cleared this link or freed its animation, which removes the link
        if (![NS_EXTRA(NSAnimation, self)->_linkedAnimations containsObject: event])
            continue;

        // A dependent in NSAnimationBlocking mode runs its own run loop inside this call, as
        // -startAnimation does for any caller.
        NSAnimation *dependent = [[[event objectForKey: @"animation"] nonretainedObjectValue] retain];
        if ([[event objectForKey: @"stop"] boolValue])
            [dependent stopAnimation];
        else
            [dependent startAnimation];
        [dependent release];
    }
}

- (void) clearStartAnimation {
    NSAnimation *trigger = NS_EXTRA(NSAnimation, self)->_startAnimation;

    NS_EXTRA(NSAnimation, self)->_startAnimation = nil;
    removeLink(trigger, self, NO);
}

- (void) clearStopAnimation {
    NSAnimation *trigger = NS_EXTRA(NSAnimation, self)->_stopAnimation;

    NS_EXTRA(NSAnimation, self)->_stopAnimation = nil;
    removeLink(trigger, self, YES);
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
        NS_EXTRA(NSAnimation, self)->_markLow = _currentProgress;
        NS_EXTRA(NSAnimation, self)->_markLowInclusive = YES;
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
    // documented: a new start animation replaces the previous one
    [self clearStartAnimation];
    // Observed on macOS 10.14.4 and 26.7.3: nil only clears the link, and a progress outside
    // 0.0 ... 1.0 never triggers (like a mark outside the range, it is not kept).
    if (animation == nil || !(progress >= 0 && progress <= 1))
        return;

    NS_EXTRA(NSAnimation, self)->_startAnimation = animation;
    addLink(animation, self, progress, NO);
}

- (void) stopWhenAnimation: (NSAnimation *) animation
           reachesProgress: (NSAnimationProgress) progress
{
    // documented: a new stop animation replaces the previous one
    [self clearStopAnimation];
    // Observed on macOS 10.14.4 and 26.7.3: nil only clears the link, and a progress outside
    // 0.0 ... 1.0 never triggers (like a mark outside the range, it is not kept).
    if (animation == nil || !(progress >= 0 && progress <= 1))
        return;

    NS_EXTRA(NSAnimation, self)->_stopAnimation = animation;
    addLink(animation, self, progress, YES);
}

@end
