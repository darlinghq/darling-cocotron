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

    // GUESS: the documentation does not say whether a copy keeps the links
    // of the original; it starts without any (rejected alternative: link the
    // copy to the same animations)
    NS_EXTRA_COPY(NSAnimation, result, self);
    NS_EXTRA(NSAnimation, result)->_startAnimation = nil;
    NS_EXTRA(NSAnimation, result)->_stopAnimation = nil;
    NS_EXTRA(NSAnimation, result)->_linkedAnimations = nil;

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
    return _currentValue;
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

    // animations linked to this one start or stop when it reaches the progress
    // they asked for.
    // GUESS: a link stays in place after it triggered, until it is cleared or
    // replaced (rejected alternative: a link triggers once).
    // GUESS: a link is not a progress mark of this animation, so it does not
    // show in -progressMarks and does not reach the delegate (the page says
    // the progress "specifies a progress mark of the other animation"; the
    // rejected alternative adds a real mark to the other animation).
    // GUESS: the crossing rule of the marks applies, so a link at 0.0 never
    // triggers (rejected alternative: it triggers when this animation starts).
    // A dependent in NSAnimationBlocking mode runs its own run loop inside
    // this call, as -startAnimation does for any caller; a dependent that is
    // not meant to hold up this animation needs a non-blocking mode.
    // A delegate that stopped this animation from a mark callback ends the
    // step here, as it does for the marks: a stopped animation does not
    // reach the linked progress.
    if (!_isAnimating || !NS_EXTRA_ALLOCATED(NSAnimation, self))
        return;
    for (NSDictionary *link in [[NS_EXTRA(NSAnimation, self)->_linkedAnimations copy] autorelease]) {
        if (!_isAnimating)
            break;

        float trigger = [[link objectForKey: @"progress"] floatValue];
        if (trigger <= previous || trigger > reached)
            continue;
        // an earlier dependent's delegate may have cleared this link or freed
        // its animation, which removes the link
        if (![NS_EXTRA(NSAnimation, self)->_linkedAnimations containsObject: link])
            continue;

        NSAnimation *dependent = [[[link objectForKey: @"animation"] nonretainedObjectValue] retain];
        if ([[link objectForKey: @"stop"] boolValue])
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
    // GUESS: nil only clears the link (rejected alternative: raise)
    if (animation == nil)
        return;

    // GUESS: the progress is pinned to 0.0 ... 1.0 like a progress mark is
    // (the page does not say; rejected alternative: raise for a value outside)
    progress = MAX(0.0f, MIN(1.0f, progress));
    NS_EXTRA(NSAnimation, self)->_startAnimation = animation;
    addLink(animation, self, progress, NO);
}

- (void) stopWhenAnimation: (NSAnimation *) animation
           reachesProgress: (NSAnimationProgress) progress
{
    // documented: a new stop animation replaces the previous one
    [self clearStopAnimation];
    // GUESS: nil only clears the link (rejected alternative: raise)
    if (animation == nil)
        return;

    // GUESS: the progress is pinned to 0.0 ... 1.0 like a progress mark is
    // (the page does not say; rejected alternative: raise for a value outside)
    progress = MAX(0.0f, MIN(1.0f, progress));
    NS_EXTRA(NSAnimation, self)->_stopAnimation = animation;
    addLink(animation, self, progress, YES);
}

@end
