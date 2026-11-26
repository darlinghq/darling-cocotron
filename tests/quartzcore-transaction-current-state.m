// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: +[CATransaction currentState], SPI that WebKit uses to tell
// whether a transaction is open, and that reading a transaction value doesn't
// open one. Every expectation was observed on macOS 26.7.3 (x86_64) with the
// same calls.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <unistd.h>

@interface CATransaction (CurrentStateSPI)
+ (uint32_t)currentState;
@end

static int failures;

static void expect(const char *name, uint32_t expected)
{
    uint32_t state = [CATransaction currentState];
    printf("%s: %s (%u)\n", state == expected ? "PASS" : "FAIL", name, state);
    if (state != expected)
        failures++;
}

int main(void)
{
    @autoreleasepool {
        expect("none open", 0);

        [CATransaction begin];
        expect("explicit", 2);
        [CATransaction begin];
        expect("nested explicit", 2);
        [CATransaction commit];
        expect("after the inner commit", 2);
        [CATransaction commit];
        expect("after the outer commit", 0);

        CALayer *layer = [CALayer layer];
        expect("creating a layer opens none", 0);
        layer.opacity = 0.5;
        expect("changing a layer opens an implicit one", 1);
        [CATransaction flush];
        expect("flush commits it", 0);

        [CATransaction setDisableActions: YES];
        expect("a setter opens an implicit one", 1);
        [CATransaction begin];
        expect("explicit inside implicit", 1);
        [CATransaction commit];
        expect("after committing the explicit one", 1);
        [CATransaction flush];
        expect("after flush", 0);

        BOOL disabled = [CATransaction disableActions];
        expect("disableActions opens none", 0);
        CFTimeInterval duration = [CATransaction animationDuration];
        expect("animationDuration opens none", 0);
        (void)[CATransaction completionBlock];
        (void)[CATransaction valueForKey: @"OtherKey"];
        expect("other getters open none", 0);
        BOOL defaults = !disabled && duration == 0.25;
        printf("%s: the getters give the defaults\n", defaults ? "PASS" : "FAIL");
        if (!defaults)
            failures++;

        [CATransaction begin];
        [CATransaction setDisableActions: YES];
        expect("a setter in an explicit one", 2);
        [CATransaction commit];
        expect("committed", 0);

        [CATransaction begin];
        __block uint32_t other = 99;
        NSThread *thread = [[[NSThread alloc] initWithBlock: ^{ other = [CATransaction currentState]; }] autorelease];
        [thread start];
        while (![thread isFinished])
            usleep(1000);
        printf("%s: another thread has its own state (%u)\n", other == 0 ? "PASS" : "FAIL", other);
        if (other != 0)
            failures++;
        [CATransaction commit];
    }
    return failures != 0;
}
