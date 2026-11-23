#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>

// Mac Catalyst frameworks send +[CATransaction setDisableRunLoopObserverCommits:]; it is private
// and undocumented. Cocotron has no run loop observer commit, so the flag changes nothing.
@interface CATransaction (DisableRunLoopObserverCommitsPrivate)
+ (void)setDisableRunLoopObserverCommits:(BOOL)value;
@end

static int failures;

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        failures++;
    }
}

// an explicit transaction still takes and returns properties
static BOOL explicitTransactionStillWorks(void)
{
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.5];
    BOOL ok = [CATransaction animationDuration] == 0.5;
    [CATransaction commit];
    return ok;
}

int main(void)
{
    @autoreleasepool
    {
        expect([CATransaction respondsToSelector:@selector(setDisableRunLoopObserverCommits:)],
               @"CATransaction answers +setDisableRunLoopObserverCommits:");

        expect(explicitTransactionStillWorks(), @"an explicit transaction works (flag never set)");
        [CATransaction setDisableRunLoopObserverCommits:YES];
        expect(explicitTransactionStillWorks(), @"an explicit transaction works with the flag YES");
        [CATransaction setDisableRunLoopObserverCommits:NO];
        expect(explicitTransactionStillWorks(), @"an explicit transaction works with the flag NO");

        if (failures == 0)
            NSLog(@"PASS: CATransaction +setDisableRunLoopObserverCommits:");
    }
    return failures == 0 ? 0 : 1;
}
