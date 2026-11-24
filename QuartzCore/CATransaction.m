#import "CATransactionGroup.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CATransaction.h>
#import <QuartzCore/CATransactionPrivate.h>
#import <Block.h>

NSString *const kCATransactionAnimationDuration =
        @"kCATransactionAnimationDuration";
NSString *const kCATransactionDisableActions = @"kCATransactionDisableActions";
NSString *const kCATransactionAnimationTimingFunction =
        @"kCATransactionAnimationTimingFunction";
NSString *const kCATransactionCompletionBlock =
        @"kCATransactionCompletionBlock";

@implementation CATransaction

static NSMutableArray *transactionStack() {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    id stack = [shared objectForKey: @"CATransactionStack"];

    if (stack == nil) {
        stack = [NSMutableArray array];
        [shared setObject: stack forKey: @"CATransactionStack"];
    }

    return stack;
}

static CATransactionGroup *currentTransactionGroup() {
    id stack = transactionStack();

    CATransactionGroup *result = [stack lastObject];

    return result;
}

static id implicitTransactionDidBeginHandler;

static CATransactionGroup *createImplicitTransactionGroupIfNeeded() {
    CATransactionGroup *check = currentTransactionGroup();

    if (check == nil) {
        check = [[CATransactionGroup alloc] initImplicit: YES];

        [transactionStack() addObject: check];
        [check release]; // The stack owns the active transaction.
        [[NSRunLoop currentRunLoop]
                performSelector: @selector(_commitImplicitTransaction)
                         target: [CATransaction class]
                       argument: nil
                          order: 0
                          modes: [NSArray arrayWithObject:
                                                  NSDefaultRunLoopMode]];

        id handler = nil;
        @synchronized([CATransaction class]) {
            handler = [implicitTransactionDidBeginHandler retain];
        }
        if (handler != nil) {
            ((void (^)(void)) handler)();
            [handler release];
        }
    }

    return check;
}

#define COMMIT_PHASE_COUNT (kCATransactionPhasePostCommit + 1)

// The current thread's commit handlers, one array per phase. They belong to
// the thread's outermost transaction, whichever group they were added in.
static NSMutableArray *commitHandlers(CATransactionPhase phase) {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    NSMutableArray *phases =
            [shared objectForKey: @"CATransactionCommitHandlers"];

    if (phases == nil) {
        phases = [NSMutableArray arrayWithCapacity: COMMIT_PHASE_COUNT];
        for (int i = 0; i < COMMIT_PHASE_COUNT; i++)
            [phases addObject: [NSMutableArray array]];
        [shared setObject: phases forKey: @"CATransactionCommitHandlers"];
    }

    return [phases objectAtIndex: phase];
}

// Runs the handlers of one phase. They are taken out first, so a handler
// that adds another one for the same phase defers it to the next commit.
static void runCommitHandlers(CATransactionPhase phase) {
    NSMutableArray *handlers = commitHandlers(phase);

    if ([handlers count] == 0)
        return;

    NSArray *batch = [handlers copy];
    [handlers removeAllObjects];

    for (void (^handler)(void) in batch)
        handler();

    [batch release];
}

// The completion blocks of the transactions committed so far in the current
// outermost transaction, in commit order.
static NSMutableArray *pendingCompletionBlocks(void) {
    NSMutableDictionary *shared = [NSCurrentThread() sharedDictionary];
    NSMutableArray *blocks =
            [shared objectForKey: @"CATransactionCompletionBlocks"];

    if (blocks == nil) {
        blocks = [NSMutableArray array];
        [shared setObject: blocks forKey: @"CATransactionCompletionBlocks"];
    }
    return blocks;
}

// QUIRK: completion blocks run after +commit has returned, on the main run
// loop's next pass, after every PostCommit handler of that commit. The
// public documentation only says the block is called on the main thread
// once the transaction's animations are done; when it runs relative to
// +commit and the commit handler SPI is undocumented. Evidence: macOS
// 27.0.1 black-box, tier 2: a commit with completion C and a PostCommit
// handler B logs "B" when +commit returns and "BC" after one run loop turn.
// Nothing here tracks animations, so this is the whole delay.
// Test: quartzcore_commit_handlers (impl/P114-tests), "completion block
// runs after +commit returns".
static void scheduleCompletionBlocks(void) {
    NSMutableArray *blocks = pendingCompletionBlocks();

    if ([blocks count] == 0)
        return;

    NSArray *batch = [blocks copy];
    [blocks removeAllObjects];

    CFRunLoopRef mainLoop = CFRunLoopGetMain();
    CFRunLoopPerformBlock(mainLoop, kCFRunLoopCommonModes, ^{
        for (void (^block)(void) in batch)
            block();
        [batch release];
    });
    CFRunLoopWakeUp(mainLoop);
}

+ (void) addCommitHandler: (void (^)(void)) handler
                 forPhase: (CATransactionPhase) phase
{
    if (handler == nil || phase > kCATransactionPhasePostCommit)
        return;

    // QUIRK: adding a handler does not start an implicit transaction; with
    // no transaction open it waits for the next commit. The SPI is
    // undocumented. Evidence: macOS 27.0.1 black-box, tier 2: a PostCommit
    // handler added outside any transaction had not run after the following
    // run loop turn.
    // Test: quartzcore_commit_handlers (impl/P114-tests), "a handler added
    // outside a transaction waits for the next commit".
    void (^copy)(void) = Block_copy(handler);
    [commitHandlers(phase) addObject: copy];
    Block_release(copy);
}

+ (BOOL) disableActions {
    return [[self valueForKey: kCATransactionDisableActions] boolValue];
}

+ (CFTimeInterval) animationDuration {
    return [[self valueForKey: kCATransactionAnimationDuration] doubleValue];
}

+ (CAMediaTimingFunction *) animationTimingFunction {
    return [self valueForKey: kCATransactionAnimationTimingFunction];
}

+ (void (^)(void)) completionBlock {
    return [self valueForKey: kCATransactionCompletionBlock];
}

+ valueForKey: (NSString *) key {
    CATransactionGroup *group = createImplicitTransactionGroupIfNeeded();

    return [group valueForKey: key];
}

+ (void) setAnimationDuration: (CFTimeInterval) value {
    [self setValue: [NSNumber numberWithDouble: value]
            forKey: kCATransactionAnimationDuration];
}

+ (void) setAnimationTimingFunction: (CAMediaTimingFunction *) value {
    [self setValue: value forKey: kCATransactionAnimationTimingFunction];
}

+ (void) setCompletionBlock: (void (^)(void)) value {
    void (^copy)(void) = value ? Block_copy(value) : nil;

    [self setValue: copy forKey: kCATransactionCompletionBlock];
    if (copy)
        Block_release(copy);
}

+ (void) setDisableActions: (BOOL) value {
    [self setValue: [NSNumber numberWithBool: value]
            forKey: kCATransactionDisableActions];
}

+ (void) setValue: value forKey: (NSString *) key {
    CATransactionGroup *group = createImplicitTransactionGroupIfNeeded();

    [group setValue: value forKey: key];
}

+ (void) begin {
    CATransactionGroup *group = [[CATransactionGroup alloc] init];

    [transactionStack() addObject: group];
    [group release];
}

+ (void) _commitImplicitTransaction {
    NSMutableArray *stack = transactionStack();
    CATransactionGroup *bottom = [stack count] ? [stack objectAtIndex: 0] : nil;

    if (bottom == nil || ![bottom isImplicit])
        return;

    if ([stack count] == 1)
        [self commit];
    else
        // Explicit transactions are still open in it: commit once they are
        // done.
        [bottom setCommitWhenUnnested: YES];
}

+ (void) commit {
    NSMutableArray *stack = transactionStack();
    CATransactionGroup *group = [stack lastObject];

    if (group == nil)
        return;

    void (^completion)(void) =
            [group valueForKey: kCATransactionCompletionBlock];

    // A nested transaction's completion block waits for the outermost
    // commit too.
    if (completion != nil)
        [pendingCompletionBlocks() addObject: completion];

    if ([stack count] > 1) {
        [stack removeLastObject];

        CATransactionGroup *bottom = [stack objectAtIndex: 0];
        if ([stack count] == 1 && [bottom isImplicit] &&
            [bottom commitWhenUnnested])
            [self commit];
        return;
    }

    [group retain];

    runCommitHandlers(kCATransactionPhasePreLayout);
    runCommitHandlers(kCATransactionPhasePreCommit);

    // A handler may have begun a transaction and left it open, in which
    // case the group is no longer the innermost one.
    [stack removeObjectIdenticalTo: group];
    [group release];

    runCommitHandlers(kCATransactionPhasePostCommit);
    scheduleCompletionBlocks();

    // QUIRK: a handler added for a phase this commit had already passed
    // stays pending until some later commit; no implicit transaction is
    // started for it. The SPI is undocumented. Evidence: macOS 27.0.1
    // black-box, tier 2: a PreLayout handler added from a PreCommit handler
    // had not run after the following run loop turn.
    // Test: quartzcore_commit_handlers (impl/P114-tests), "a handler added
    // for a passed phase waits for the next commit".
}

// Private, sent to the class by Mac Catalyst frameworks and not documented. The block is kept (a
// new one replaces the old one, nil clears it) and is called, without arguments, each time an
// implicit transaction begins (see createImplicitTransactionGroupIfNeeded). Observed on macOS
// 26.7.3 (black-box, tier 2): the selector takes a block, the block is called once per implicit
// transaction, synchronously on the thread that began it, and not for an explicit +begin;
// 10.14.4 has no such selector, which is why this is the superset behaviour.
// Test: quartzcore-catransaction-implicit-did-begin-handler.
+ (void) setImplicitTransactionDidBeginHandler: (id) handler {
    @synchronized([CATransaction class]) {
        id previous = implicitTransactionDidBeginHandler;
        implicitTransactionDidBeginHandler = [handler copy];
        [previous release];
    }
}

// Private, sent to the class by Mac Catalyst frameworks and not documented. The argument is a
// BOOL (type encoding observed on macOS 10.14.4 and 26.7.3). The name asks to stop a run loop
// observer from committing transactions. Cocotron commits an implicit transaction from a run loop
// perform, not from an observer, so there is nothing to switch off: the flag is kept and has no
// effect. Test: quartzcore-catransaction-disable-run-loop-observer-commits.
static BOOL disableRunLoopObserverCommits;

+ (void) setDisableRunLoopObserverCommits: (BOOL) value {
    @synchronized([CATransaction class]) {
        disableRunLoopObserverCommits = value;
    }
}

// Private, sent to the class by Mac Catalyst frameworks and not documented. The argument is a
// BOOL (observed on macOS 26.7.3; Mojave 10.14.4 has no such selector, so this is the superset
// behaviour). The name asks for the default of the flag above for transactions to come. The flag
// has no effect here, so the default has none either: it is kept and nothing reads it.
static BOOL defaultDisableRunLoopObserverCommits;

+ (void) setDefaultDisableRunLoopObserverCommits: (BOOL) value {
    @synchronized([CATransaction class]) {
        defaultDisableRunLoopObserverCommits = value;
    }
}

+ (void) flush {
    [self _commitImplicitTransaction];
}

+ (void) lock {
}

+ (void) unlock {
}

@end
