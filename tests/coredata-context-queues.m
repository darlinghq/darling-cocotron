#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

@protocol ContextQueueContract <NSObject>
- (instancetype)initWithConcurrencyType:(NSUInteger)type;
- (NSUInteger)concurrencyType;
- (void)performBlock:(void (^)(void))block;
- (void)performBlockAndWait:(void (^)(void))block;
@end

#define CHECK(condition) do { if (!(condition)) return 1; } while (0)

int main(void) {
    @autoreleasepool {
        Class contextClass = NSClassFromString(@"NSManagedObjectContext");
        if (![contextClass instancesRespondToSelector:@selector(initWithConcurrencyType:)])
            return 45;
        id<ContextQueueContract> main = [[contextClass alloc] initWithConcurrencyType:2];
        id<ContextQueueContract> background = [[contextClass alloc] initWithConcurrencyType:1];
        CHECK([main concurrencyType] == 2 && [background concurrencyType] == 1);
        __block NSUInteger mainCount = 0;
        __block BOOL valid = YES;
        [main performBlockAndWait:^{
            valid &= [NSThread isMainThread];
            [main performBlockAndWait:^{ mainCount++; }];
        }];
        CHECK(valid && mainCount == 1);
        [main performBlock:^{ valid &= [NSThread isMainThread]; mainCount++; }];
        CHECK(mainCount == 1);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (mainCount < 2 && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                    beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        CHECK(valid && mainCount == 2);
        __block NSUInteger privateCount = 0;
        [background performBlockAndWait:^{
            valid &= ![NSThread isMainThread];
            [background performBlockAndWait:^{ privateCount++; }];
        }];
        CHECK(valid && privateCount == 1);
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        [background performBlock:^{ privateCount++; }];
        [background performBlock:^{
            valid &= privateCount == 2 && ![NSThread isMainThread];
            privateCount++;
            dispatch_semaphore_signal(finished);
        }];
        CHECK(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
        CHECK(valid && privateCount == 3);
        dispatch_release(finished);
        [background release];
        [main release];
        puts("PASS_COREDATA_CONTEXT_QUEUES");
    }
    return 0;
}
