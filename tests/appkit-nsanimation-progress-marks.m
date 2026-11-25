// Copyright (C) 2026 Lubos Dolezel
//
// NSAnimation progress marks, from the public contract
// (https://developer.apple.com/documentation/appkit/nsanimation/addprogressmark(_:)):
//  - a mark is a progress value between 0.0 and 1.0;
//  - when a running animation reaches a mark, the delegate receives
//    -animation:didReachProgressMark: and NSAnimationProgressMarkNotification
//    is posted with the animation as the object and the mark under the key
//    NSAnimationProgressMark (the public header gives no string value; macOS
//    uses the key's own name);
//  - several marks may be reached by one advance;
//  - -removeProgressMark: removes a mark added earlier, -setProgressMarks:nil
//    clears all marks;
//  - -setCurrentProgress: pins values outside 0.0 ... 1.0.
// The lines marked OBSERVED pin what the documentation leaves open, as observed on macOS 10.14.4
// and 26.7.3: marks outside 0.0 ... 1.0 are ignored, the marks are kept in ascending order (a
// value added twice twice), a running animation reports marks in ascending order including one at
// 0.0 with its first update and a value added twice twice, a mark is reported once per run (no
// report after moving backwards and forwards again), marks below the progress the run started at
// are not reported, and a delegate that stops the animation does not end the reports of that
// update. Nothing is reported while the animation is not running.
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

@interface MarkRecorder : NSObject {
@public
    NSMutableArray *delegateMarks;
    NSMutableArray *notificationMarks;
    id notificationObject;
    BOOL stopFirst; // stop the animation from the callback for the first mark of an update
}
@end

@implementation MarkRecorder
- (id) init {
    delegateMarks = [NSMutableArray new];
    notificationMarks = [NSMutableArray new];
    return self;
}
- (void) animation: (NSAnimation *) animation didReachProgressMark: (NSAnimationProgress) progress {
    [delegateMarks addObject: [NSNumber numberWithFloat: progress]];
    if (stopFirst)
        [animation stopAnimation];
}
- (void) marked: (NSNotification *) note {
    notificationObject = [note object];
    [notificationMarks addObject: [[note userInfo] objectForKey: NSAnimationProgressMark]];
}
@end

// runs the animation to its end in blocking mode
static void runBlocking(NSAnimation *animation) {
    [animation setAnimationBlockingMode: NSAnimationBlocking];
    [animation setFrameRate: 50];
    [animation startAnimation];
}

static BOOL marksEqual(NSArray *got, const float *want, NSUInteger count) {
    if ([got count] != count)
        return NO;
    for (NSUInteger i = 0; i < count; i++)
        if ([[got objectAtIndex: i] floatValue] != want[i])
            return NO;
    return YES;
}

int main(void) {
    @autoreleasepool {
        MarkRecorder *recorder = [MarkRecorder new];
        [[NSNotificationCenter defaultCenter] addObserver: recorder
                                                 selector: @selector(marked:)
                                                     name: NSAnimationProgressMarkNotification
                                                   object: nil];

        NSAnimation *animation = [[NSAnimation alloc] initWithDuration: 0.4
                                                        animationCurve: NSAnimationLinear];
        [animation setDelegate: recorder];

        // OBSERVED: marks outside 0.0 ... 1.0 are ignored
        [animation addProgressMark: -3];
        [animation addProgressMark: 7];
        CHECK([[animation progressMarks] count] == 0, "marks outside the range are ignored");
        [animation removeProgressMark: -3]; // no effect, no exception
        [animation addProgressMark: 0.5];
        [animation setProgressMarks: nil];
        CHECK([animation progressMarks] != nil && [[animation progressMarks] count] == 0, "nil clears the marks");
        [animation addProgressMark: 0.5];
        CHECK([[animation progressMarks] count] == 1, "a mark can be added after clearing");

        [animation setProgressMarks: [NSArray array]];
        [animation addProgressMark: 0.75];
        [animation addProgressMark: 0.25];
        [animation addProgressMark: 0.25];
        [animation addProgressMark: 0.5];
        const float sorted[] = {0.25f, 0.25f, 0.5f, 0.75f};
        CHECK(marksEqual([animation progressMarks], sorted, 4), "marks kept ascending: %s", [[[animation progressMarks] description] UTF8String]);
        [animation removeProgressMark: 0.25]; // added twice: both go
        [animation removeProgressMark: 0.6]; // absent: no effect, no exception
        const float afterRemove[] = {0.5f, 0.75f};
        CHECK(marksEqual([animation progressMarks], afterRemove, 2), "0.25 removed, 0.5 and 0.75 left");

        [animation setProgressMarks: [NSArray arrayWithObjects:
            [NSNumber numberWithFloat: 0.25f], [NSNumber numberWithFloat: 0.75f], [NSNumber numberWithFloat: 0.75f],
            [NSNumber numberWithFloat: 1.0f], [NSNumber numberWithFloat: 0.0f], nil]];

        // not running: progress changes report nothing, and out-of-range values are pinned
        [animation setCurrentProgress: 0.9];
        CHECK([recorder->delegateMarks count] == 0, "no mark reported while not running");
        [animation setCurrentProgress: -1];
        CHECK([animation currentProgress] == 0, "negative progress pinned to 0");
        [animation setCurrentProgress: 5];
        CHECK([animation currentProgress] == 1, "large progress pinned to 1");
        [animation setCurrentProgress: 0];

        runBlocking(animation);
        const float all[] = {0.0f, 0.25f, 0.75f, 0.75f, 1.0f};
        CHECK(marksEqual(recorder->delegateMarks, all, 5), "delegate marks %s", [[recorder->delegateMarks description] UTF8String]);
        CHECK(marksEqual(recorder->notificationMarks, all, 5), "notification marks %s", [[recorder->notificationMarks description] UTF8String]);
        CHECK(recorder->notificationObject == animation, "notification object is the animation");
        CHECK([animation currentProgress] == 1, "ended at 1.0");

        // a finished animation starts again at 0.0 and reports its marks again
        [recorder->delegateMarks removeAllObjects];
        [recorder->notificationMarks removeAllObjects];
        runBlocking(animation);
        CHECK(marksEqual(recorder->delegateMarks, all, 5), "second run delegate marks %s", [[recorder->delegateMarks description] UTF8String]);

        // one advance past several marks reports each, in ascending order, the first mark (0.0) too
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0];
        [animation setAnimationBlockingMode: NSAnimationNonblocking];
        [animation setFrameRate: 1]; // the timer never fires during the test
        [animation startAnimation];
        CHECK([recorder->delegateMarks count] == 0, "starting reports nothing by itself");
        [animation setCurrentProgress: 0.8];
        const float four[] = {0.0f, 0.25f, 0.75f, 0.75f};
        CHECK(marksEqual(recorder->delegateMarks, four, 4), "marks of one advance %s", [[recorder->delegateMarks description] UTF8String]);

        // moving backwards and forwards again reports nothing: a mark is reported once per run
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0.1];
        CHECK([recorder->delegateMarks count] == 0, "backwards reports nothing");
        [animation setCurrentProgress: 0.3];
        CHECK([recorder->delegateMarks count] == 0, "crossing 0.25 again reports nothing");
        [animation stopAnimation];

        // stopping the animation from the callback does not end the reports of that update
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0];
        [animation startAnimation];
        recorder->stopFirst = YES;
        [animation setCurrentProgress: 0.8];
        recorder->stopFirst = NO;
        CHECK(marksEqual(recorder->delegateMarks, four, 4), "stopped from the callback %s",
              [[recorder->delegateMarks description] UTF8String]);
        CHECK(![animation isAnimating], "animation stopped from the callback");

        // a run that starts at 0.25 reports from 0.25 on, not the mark at 0.0
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0.25];
        [animation startAnimation];
        [animation setCurrentProgress: 0.25];
        [animation setCurrentProgress: 0.3];
        const float one[] = {0.25f};
        CHECK(marksEqual(recorder->delegateMarks, one, 1), "run started at 0.25 %s", [[recorder->delegateMarks description] UTF8String]);
        [animation stopAnimation];

        // a removed mark is not reported
        [recorder->delegateMarks removeAllObjects];
        [animation removeProgressMark: 0.25];
        [animation setCurrentProgress: 0];
        runBlocking(animation);
        const float rest[] = {0.0f, 0.75f, 0.75f, 1.0f};
        CHECK(marksEqual(recorder->delegateMarks, rest, 4), "after removal %s", [[recorder->delegateMarks description] UTF8String]);

        [[NSNotificationCenter defaultCenter] removeObserver: recorder];
        [animation release];
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSAnimation progress marks");
    return 0;
}
