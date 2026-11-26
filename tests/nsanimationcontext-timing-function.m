#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

static void expect(BOOL cond, const char *msg) {
    if (!cond) {
        printf("FAIL: %s\n", msg);
        fflush(stdout);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        CAMediaTimingFunction *ease = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        expect(ease != nil, "CAMediaTimingFunction should be created");

        NSAnimationContext *base = [NSAnimationContext currentContext];
        expect([base respondsToSelector:@selector(setTimingFunction:)], "setTimingFunction: selector exists");
        expect([base respondsToSelector:@selector(timingFunction)], "timingFunction selector exists");
        expect([base timingFunction] == nil, "initial timingFunction should be nil");

        [base setTimingFunction:ease];
        expect([base timingFunction] == ease, "base timingFunction should match assigned value");

        [NSAnimationContext beginGrouping];
        NSAnimationContext *inner = [NSAnimationContext currentContext];
        expect([inner timingFunction] == ease, "nested grouping should inherit outer timingFunction");

        CAMediaTimingFunction *linear = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [inner setTimingFunction:linear];
        expect([inner timingFunction] == linear, "the group can change its timingFunction");
        [NSAnimationContext endGrouping];

        // Whether or not a group has a context object of its own, ending it restores the outer value.
        expect([[NSAnimationContext currentContext] timingFunction] == ease, "endGrouping should restore the outer timingFunction");
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            expect([ctx timingFunction] == ease, "runAnimationGroup should inherit the outer timingFunction");
        } completionHandler:nil];

        [base setTimingFunction:nil];
        expect([base timingFunction] == nil, "setting nil should clear timingFunction");

        __block BOOL ran = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            [ctx setTimingFunction:ease];
            expect([ctx timingFunction] == ease, "runAnimationGroup context should retain timingFunction");
            ran = YES;
        } completionHandler:^{
            expect(ran, "completionHandler runs after block");
        }];
        expect(ran, "runAnimationGroup should run synchronously");

        puts("PASS: NSAnimationContext timingFunction");
    }
    return 0;
}
