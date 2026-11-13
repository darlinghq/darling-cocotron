// Copyright (C) 2026 Lubos Dolezel
//
// CADisplayLink.preferredFrameRateRange: it is stored and read back, and a
// range with a nonzero maximum sets how often the link fires (its preferred
// rate when inside the range, else its maximum). The class method that
// creates the link is unavailable on macOS (it returns nil there), so on a
// Mac the test only checks that and exits 0.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <stdio.h>

@interface Counter : NSObject {
@public
    int ticks;
}
- (void)tick:(CADisplayLink *)link;
@end
@implementation Counter
- (void)tick:(CADisplayLink *)link { ticks++; }
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static int ticksOver(CADisplayLink *link, Counter *c, NSTimeInterval seconds) {
    c->ticks = 0;
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
    return c->ticks;
}

int main(void) {
    @autoreleasepool {
        Counter *c = [Counter new];
        CADisplayLink *(*create)(id, SEL, id, SEL) = (void *) objc_msgSend;
        CADisplayLink *link = create(NSClassFromString(@"CADisplayLink"), NSSelectorFromString(@"displayLinkWithTarget:selector:"), c,
                                     @selector(tick:));
        if (link == nil) {
            puts("SKIP: no class factory (macOS)");
            return 0;
        }
        CAFrameRateRange r = CAFrameRateRangeMake(20, 40, 30);
        link.preferredFrameRateRange = r;
        CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, r), "range read back");
        [link addToRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
        int at30 = ticksOver(link, c, 1.0);
        CHECK(at30 >= 20 && at30 <= 36, "preferred 30 fps gave %d ticks in a second", at30);

        link.preferredFrameRateRange = CAFrameRateRangeMake(5, 10, 0);
        int atMax10 = ticksOver(link, c, 1.0);
        CHECK(atMax10 >= 6 && atMax10 <= 12, "no preferred rate: the maximum 10 fps gave %d ticks", atMax10);

        link.preferredFrameRateRange = CAFrameRateRangeMake(5, 10, 50);
        int outside = ticksOver(link, c, 1.0);
        CHECK(outside >= 6 && outside <= 12, "preferred outside the range: the maximum gave %d ticks", outside);

        link.preferredFrameRateRange = CAFrameRateRangeDefault;
        CHECK(CAFrameRateRangeIsEqualToRange(link.preferredFrameRateRange, CAFrameRateRangeDefault), "default range");
        [link invalidate];
        if (failures == 0) puts("PASS: CADisplayLink preferredFrameRateRange");
        return failures != 0;
    }
}
