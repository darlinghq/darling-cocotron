#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>

// Mac Catalyst frameworks send +[CATransaction setImplicitTransactionDidBeginHandler:]; it is
// private and undocumented; the block is called, without arguments, when an implicit transaction
// begins (observed on macOS 26.7.3, which has the selector; 10.14.4 does not).
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
        expect(calls == 0, @"setting the handler does not call it");

        // an explicit transaction does not call it (OBSERVED on macOS 26.7.3)
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.5];
        expect([CATransaction animationDuration] == 0.5, @"an explicit transaction still takes properties");
        [CATransaction commit];
        expect(calls == 0, @"an explicit transaction does not call the handler");

        // a property change of a layer outside any transaction begins an implicit one, and the
        // handler runs once, at once, for it (OBSERVED on macOS 26.7.3)
        CALayer *layer = [CALayer layer];
        layer.opacity = 0.5;
        expect(calls == 1, @"an implicit transaction calls the handler once");
        layer.opacity = 0.6;
        expect(calls == 1, @"the open implicit transaction does not call it again");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        layer.opacity = 0.7;
        expect(calls == 2, @"the next implicit transaction calls it again");
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];

        [CATransaction setImplicitTransactionDidBeginHandler:nil];
        expect(tokenDeallocated, @"clearing the handler releases the block");
        layer.opacity = 0.8;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        expect(calls == 2, @"a cleared handler is not called");

        if (failures == 0)
            NSLog(@"PASS: CATransaction +setImplicitTransactionDidBeginHandler:");
    }
    return failures == 0 ? 0 : 1;
}
