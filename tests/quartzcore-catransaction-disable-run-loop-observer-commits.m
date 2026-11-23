#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>

// Mac Catalyst frameworks send +[CATransaction setDisableRunLoopObserverCommits:] and
// +setDefaultDisableRunLoopObserverCommits:; both are private and undocumented. Cocotron has no
// run loop observer commit, so neither changes anything.
@interface CATransaction (DisableRunLoopObserverCommitsPrivate)
+ (void)setDisableRunLoopObserverCommits:(BOOL)value;
+ (void)setDefaultDisableRunLoopObserverCommits:(BOOL)value;
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

        expect([CATransaction respondsToSelector:@selector(setDefaultDisableRunLoopObserverCommits:)],
               @"CATransaction answers +setDefaultDisableRunLoopObserverCommits:");
        [CATransaction setDefaultDisableRunLoopObserverCommits:YES];
        expect(explicitTransactionStillWorks(), @"an explicit transaction works with the default YES");
        [CATransaction setDefaultDisableRunLoopObserverCommits:NO];
        expect(explicitTransactionStillWorks(), @"an explicit transaction works with the default NO");

        if (failures == 0)
            NSLog(@"PASS: CATransaction +setDisableRunLoopObserverCommits: and +setDefaultDisableRunLoopObserverCommits:");
    }
    return failures == 0 ? 0 : 1;
}
