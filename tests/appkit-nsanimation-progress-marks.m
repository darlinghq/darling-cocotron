// Copyright (C) 2026 Lubos Dolezel
//
// NSAnimation progress marks, from the public contract
// (https://developer.apple.com/documentation/appkit/nsanimation/addprogressmark(_:)):
//  - a mark is a progress value between 0.0 and 1.0, values outside are pinned
//    to the nearest end;
//  - when a running animation reaches a mark, the delegate receives
//    -animation:didReachProgressMark: and NSAnimationProgressMarkNotification
//    is posted with the animation as the object and the mark under the key
//    NSAnimationProgressMark (declared in the public header, which gives no
//    string value; the documentation names the key NSAnimationProgressMark);
//  - several marks may be reached by one advance;
//  - -removeProgressMark: removes a mark added earlier, -setProgressMarks:nil
//    clears all marks;
//  - -setCurrentProgress: pins values outside 0.0 ... 1.0.
// The GUESS choices of the implementation are pinned too: marks reached in
// one step arrive in ascending order, a value added twice is reported once,
// a mark is not reported while the animation is not running or when progress
// moves backwards.
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
    NSAnimationProgress stopAt; // stop the animation from the callback at this mark, 0 for never
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
    if (stopAt != 0 && progress == stopAt)
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

        // out-of-range marks are pinned (0.0 and 1.0); 0.0 is never reached
        [animation addProgressMark: -3];
        [animation addProgressMark: 7];
        CHECK([[animation progressMarks] count] == 2, "two marks added");
        CHECK([[[animation progressMarks] objectAtIndex: 0] floatValue] == 0, "negative pinned to 0");
        CHECK([[[animation progressMarks] objectAtIndex: 1] floatValue] == 1, "large pinned to 1");

        [animation removeProgressMark: -3];
        CHECK([[animation progressMarks] count] == 1, "removing -3 removes the mark added as -3");
        CHECK([[[animation progressMarks] objectAtIndex: 0] floatValue] == 1, "the mark at 1.0 is left");
        [animation removeProgressMark: 7];
        CHECK([[animation progressMarks] count] == 0, "removing 7 removes the mark added as 7");
        [animation addProgressMark: 0.5];
        [animation setProgressMarks: nil];
        CHECK([[animation progressMarks] count] == 0, "nil clears the marks");
        [animation addProgressMark: 0.5];
        CHECK([[animation progressMarks] count] == 1, "a mark can be added after clearing");

        [animation setProgressMarks: [NSArray array]];
        [animation addProgressMark: 0.75];
        [animation addProgressMark: 0.25];
        [animation addProgressMark: 0.25];
        [animation addProgressMark: 0.5];
        [animation addProgressMark: 1];
        [animation removeProgressMark: 0.5];
        [animation removeProgressMark: 0.6]; // absent: no effect, no exception
        CHECK([[animation progressMarks] count] == 4, "0.5 removed, %lu left", (unsigned long) [[animation progressMarks] count]);

        // not running: progress changes report nothing, and out-of-range values are pinned
        [animation setCurrentProgress: 0.9];
        CHECK([recorder->delegateMarks count] == 0, "no mark reported while not running");
        [animation setCurrentProgress: -1];
        CHECK([animation currentProgress] == 0, "negative progress pinned to 0");
        [animation setCurrentProgress: 5];
        CHECK([animation currentProgress] == 1, "large progress pinned to 1");
        [animation setCurrentProgress: 0];

        runBlocking(animation);
        const float all[] = {0.25f, 0.75f, 1.0f};
        CHECK(marksEqual(recorder->delegateMarks, all, 3), "delegate marks %s", [[recorder->delegateMarks description] UTF8String]);
        CHECK(marksEqual(recorder->notificationMarks, all, 3), "notification marks %s", [[recorder->notificationMarks description] UTF8String]);
        CHECK(recorder->notificationObject == animation, "notification object is the animation");
        CHECK([animation currentProgress] == 1, "ended at 1.0");

        // a finished animation starts again at 0.0 and reports its marks again
        [recorder->delegateMarks removeAllObjects];
        [recorder->notificationMarks removeAllObjects];
        runBlocking(animation);
        CHECK(marksEqual(recorder->delegateMarks, all, 3), "second run delegate marks %s", [[recorder->delegateMarks description] UTF8String]);

        // one advance past several marks reports each, in ascending order
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0];
        [animation setAnimationBlockingMode: NSAnimationNonblocking];
        [animation setFrameRate: 1]; // the timer never fires during the test
        [animation startAnimation];
        [animation setCurrentProgress: 0.8];
        const float two[] = {0.25f, 0.75f};
        CHECK(marksEqual(recorder->delegateMarks, two, 2), "marks of one advance %s", [[recorder->delegateMarks description] UTF8String]);

        // moving backwards and forwards again reports a mark only when crossed forward
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0.1];
        CHECK([recorder->delegateMarks count] == 0, "backwards reports nothing");
        [animation setCurrentProgress: 0.3];
        const float one[] = {0.25f};
        CHECK(marksEqual(recorder->delegateMarks, one, 1), "crossing 0.25 again %s", [[recorder->delegateMarks description] UTF8String]);
        [animation stopAnimation];

        // stopping the animation from the callback ends the reports of that step
        [recorder->delegateMarks removeAllObjects];
        [animation setCurrentProgress: 0];
        [animation startAnimation];
        recorder->stopAt = 0.25f;
        [animation setCurrentProgress: 0.8];
        recorder->stopAt = 0;
        CHECK(marksEqual(recorder->delegateMarks, one, 1), "stopped from the callback %s",
              [[recorder->delegateMarks description] UTF8String]);
        CHECK(![animation isAnimating], "animation stopped from the callback");

        // a removed mark is not reported
        [recorder->delegateMarks removeAllObjects];
        [animation removeProgressMark: 0.25];
        [animation setCurrentProgress: 0];
        runBlocking(animation);
        const float rest[] = {0.75f, 1.0f};
        CHECK(marksEqual(recorder->delegateMarks, rest, 2), "after removal %s", [[recorder->delegateMarks description] UTF8String]);

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
