// Copyright (C) 2026 Lubos Dolezel
//
// NSAnimation linking, from the public contract
// (https://developer.apple.com/documentation/appkit/nsanimation/start(when:reachesprogress:)
// and the pages for stop(when:reachesprogress:), clearStart() and clearStop()):
//  - -startWhenAnimation:reachesProgress: starts the receiver when the other
//    animation reaches the given progress, -stopWhenAnimation:reachesProgress:
//    stops it;
//  - an animation has at most one start link and one stop link, setting a new
//    one replaces the previous;
//  - -clearStartAnimation and -clearStopAnimation remove the links.
// The lines marked OBSERVED pin what the documentation leaves open, as observed on macOS 10.14.4
// and 26.7.3: nil clears a link, a link takes part in the same pass as the marks of the animation
// it waits for (it triggers once per run, and a link at 0.0 triggers with the first update), a
// progress outside 0.0 ... 1.0 never triggers, and a copy keeps the links of the original. A link
// never keeps an animation alive or points at a deallocated one (also when the animation is freed
// by the delegate of another one that the same step starts).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

// frees another animation when it is asked to start
@interface Releaser : NSObject {
@public
    NSAnimation *victim;
}
@end

@implementation Releaser
- (BOOL) animationShouldStart: (NSAnimation *) animation {
    [victim release];
    victim = nil;
    return YES;
}
@end

// a non-blocking animation whose timer never fires during the test: progress
// is moved by hand with -setCurrentProgress:
static NSAnimation *makeAnimation(void) {
    NSAnimation *animation = [[NSAnimation alloc] initWithDuration: 100
                                                    animationCurve: NSAnimationLinear];
    [animation setAnimationBlockingMode: NSAnimationNonblocking];
    [animation setFrameRate: 0.01];
    return animation;
}

int main(void) {
    @autoreleasepool {
        NSAnimation *trigger = makeAnimation();
        NSAnimation *other = makeAnimation();
        NSAnimation *follower = makeAnimation();

        // start link
        [follower startWhenAnimation: trigger reachesProgress: 0.5];
        [trigger startAnimation];
        [trigger setCurrentProgress: 0.4];
        CHECK(![follower isAnimating], "not started before the progress");
        [trigger setCurrentProgress: 0.6];
        CHECK([follower isAnimating], "started at the progress");

        // OBSERVED: a link triggers once per run, like a mark: crossing it again does not start the follower again
        [follower stopAnimation];
        [trigger setCurrentProgress: 0.1];
        [trigger setCurrentProgress: 0.7];
        CHECK(![follower isAnimating], "link does not trigger again within the run");
        [trigger stopAnimation];
        [trigger setCurrentProgress: 0];
        [trigger startAnimation];
        [trigger setCurrentProgress: 0.7];
        CHECK([follower isAnimating], "link triggers again in the next run");
        [follower stopAnimation];

        // one start link: a new one replaces the previous
        [follower startWhenAnimation: other reachesProgress: 0.5];
        [trigger setCurrentProgress: 0.9];
        CHECK(![follower isAnimating], "replaced start link no longer triggers");
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.6];
        CHECK([follower isAnimating], "new start link triggers");
        [follower stopAnimation];
        [other stopAnimation];

        // clearStartAnimation, and nil clears too
        [follower clearStartAnimation];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.9];
        CHECK(![follower isAnimating], "cleared start link does not trigger");
        [other stopAnimation];
        [follower startWhenAnimation: other reachesProgress: 0.5];
        [follower startWhenAnimation: nil reachesProgress: 0.5];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.9];
        CHECK(![follower isAnimating], "nil animation clears the start link");
        [follower clearStartAnimation]; // nothing linked: no effect
        [other stopAnimation];

        // OBSERVED: a progress above 1.0 never triggers
        [follower startWhenAnimation: other reachesProgress: 4];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 1];
        CHECK(![follower isAnimating], "progress 4 never triggers");
        [other stopAnimation];
        [follower clearStartAnimation];

        // stop link
        [other setCurrentProgress: 0];
        [other startAnimation];
        [follower stopWhenAnimation: other reachesProgress: 0.8];
        [follower startAnimation];
        [other setCurrentProgress: 0.7];
        CHECK([follower isAnimating], "still running before the stop progress");
        [other setCurrentProgress: 0.85];
        CHECK(![follower isAnimating], "stopped at the stop progress");
        [other stopAnimation];

        // start and stop links are independent
        [follower startWhenAnimation: other reachesProgress: 0.9];
        [follower clearStopAnimation];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.95];
        CHECK([follower isAnimating], "clearing the stop link keeps the start link");
        [follower stopAnimation];
        [follower clearStartAnimation];
        [other stopAnimation];

        // OBSERVED: a copy keeps the links of the original
        [follower startWhenAnimation: other reachesProgress: 0.5];
        NSAnimation *copy = [follower copy];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.6];
        CHECK([follower isAnimating], "the original is still linked");
        CHECK([copy isAnimating], "the copy is linked too");
        [follower stopAnimation];
        [copy stopAnimation];
        [copy release];
        [other stopAnimation];

        // OBSERVED: a link at 0.0 triggers with the first update of the run
        [follower startWhenAnimation: other reachesProgress: 0];
        [other setCurrentProgress: 0];
        [other startAnimation];
        CHECK(![follower isAnimating], "a link at 0.0 does not trigger by the start alone");
        [other setCurrentProgress: 0.1];
        CHECK([follower isAnimating], "a link at 0.0 triggers with the first update");
        [follower stopAnimation];
        [other stopAnimation];
        [follower clearStartAnimation];

#ifndef SKIP_FREED_IN_STEP /* macOS 26.7.3 raises NSRangeException here (build with -DSKIP_FREED_IN_STEP to compare) */
        // an animation freed while the same step starts another one is skipped
        {
            Releaser *releaser = [Releaser new];
            NSAnimation *first = makeAnimation();
            NSAnimation *second = makeAnimation();
            releaser->victim = second;
            [first setDelegate: releaser];
            NSAnimation *source = makeAnimation();
            [first startWhenAnimation: source reachesProgress: 0.5];
            [second startWhenAnimation: source reachesProgress: 0.5];
            [source setCurrentProgress: 0];
            [source startAnimation];
            [source setCurrentProgress: 0.6]; // starts first, whose delegate frees second
            CHECK([first isAnimating], "first was started");
            CHECK(releaser->victim == nil, "second was freed by the delegate");
            [first stopAnimation];
            [source stopAnimation];
            [first release];
            [source release];
            [releaser release];
        }
#endif

        // deallocated animations leave no link behind
        NSAnimation *shortLived = makeAnimation();
        [shortLived startWhenAnimation: other reachesProgress: 0.5];
        [shortLived stopWhenAnimation: other reachesProgress: 0.7];
        [shortLived release];
        [other setCurrentProgress: 0];
        [other startAnimation];
        [other setCurrentProgress: 0.9]; // must not touch the deallocated animation

        NSAnimation *shortLivedTrigger = makeAnimation();
        [follower startWhenAnimation: shortLivedTrigger reachesProgress: 0.5];
        [follower stopWhenAnimation: shortLivedTrigger reachesProgress: 0.7];
        [shortLivedTrigger release];
        [follower clearStartAnimation]; // must not touch the deallocated trigger
        [follower clearStopAnimation];

        [other stopAnimation];
        [trigger stopAnimation];
        [follower stopAnimation];
        [trigger release];
        [other release];
        [follower release];
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSAnimation linked animations");
    return 0;
}
