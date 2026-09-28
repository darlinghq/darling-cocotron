// Link with Foundation and QuartzCore. Run with assertions enabled.
#import <Foundation/Foundation.h>
#import <QuartzCore/CATransaction.h>

static NSUInteger destroyed;
@interface TransactionSentinel : NSObject
@end
@implementation TransactionSentinel
- (void) dealloc {
    destroyed++;
    [super dealloc];
}
@end

static void installSentinel(void) {
    id sentinel = [[TransactionSentinel alloc] init];
    [CATransaction setValue: sentinel forKey: @"OwnershipProbe"];
    [sentinel release];
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [CATransaction begin];
    installSentinel();
    [CATransaction begin];
    installSentinel();
    NSCAssert(destroyed == 0, @"active transactions must retain values");
    [CATransaction commit];
    NSCAssert(destroyed == 1, @"inner commit releases only inner values");
    [CATransaction commit];
    NSCAssert(destroyed == 2, @"outer commit releases outer values");

    installSentinel(); // Creates an implicit transaction.
    NSCAssert(destroyed == 2, @"implicit transaction must retain values");
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 1.0];
    while (destroyed == 2 && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                               beforeDate: deadline];
    NSCAssert(destroyed == 3, @"run-loop commit releases implicit values");
    [pool drain];
    return 0;
}
