#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>

// Mac Catalyst frameworks send +[CATransaction setImplicitTransactionDidBeginHandler:]; it is
// private and undocumented, so the block is kept and released but never called.
@interface CATransaction (ImplicitDidBeginPrivate)
+ (void)setImplicitTransactionDidBeginHandler:(id)handler;
@end

static int failures;
static BOOL tokenDeallocated;
static int calls;

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        failures++;
    }
}

@interface Token : NSObject
@end
@implementation Token
- (void)dealloc
{
    tokenDeallocated = YES;
    [super dealloc];
}
@end

int main(void)
{
    @autoreleasepool
    {
        expect([CATransaction respondsToSelector:@selector(setImplicitTransactionDidBeginHandler:)],
               @"CATransaction answers +setImplicitTransactionDidBeginHandler:");

        Token *token = [[Token alloc] init];
        void (^handler)(void) = ^{ (void)token; calls++; };
        [CATransaction setImplicitTransactionDidBeginHandler:handler];
        [token release];
        expect(!tokenDeallocated, @"the handler is copied and kept");

        // transactions behave as before
        [CATransaction setAnimationDuration:0.25];
        expect([CATransaction animationDuration] == 0.25, @"transaction properties still work");
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.5];
        expect([CATransaction animationDuration] == 0.5, @"an explicit transaction still takes properties");
        [CATransaction commit];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        expect(calls == 0, @"the handler is never called, its signature is unknown");

        [CATransaction setImplicitTransactionDidBeginHandler:nil];
        expect(tokenDeallocated, @"clearing the handler releases the block");

        if (failures == 0)
            NSLog(@"PASS: CATransaction +setImplicitTransactionDidBeginHandler:");
    }
    return failures == 0 ? 0 : 1;
}
