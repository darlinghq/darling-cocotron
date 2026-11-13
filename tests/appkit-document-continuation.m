// Copyright (C) 2026 Lubos Dolezel
//
// -[NSDocument unblockUserInteraction] returns, and
// -[NSDocument continueAsynchronousWorkOnMainThreadUsingBlock:] runs its block on the main queue.
#import <AppKit/AppKit.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        NSDocument *doc = [[NSDocument alloc] init];
        [doc unblockUserInteraction];

        __block BOOL ran = NO, onMain = NO;
        [doc continueAsynchronousWorkOnMainThreadUsingBlock:^{
            ran = YES;
            onMain = [NSThread isMainThread];
        }];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        [doc continueAsynchronousWorkOnMainThreadUsingBlock:nil];
        [doc release];
        if (!ran || !onMain) {
            printf("FAIL: ran=%d onMain=%d\n", ran, onMain);
            return 1;
        }
        printf("PASS\n");
    }
    return 0;
}
