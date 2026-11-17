// Copyright (C) 2026 Lubos Dolezel
#import <Foundation/Foundation.h>
#import <QuartzCore/CADisplayLink.h>
#import <objc/message.h>
#include <math.h>
#include <stdio.h>

// A CADisplayLink follows the refresh rate of its display: its duration is one
// refresh interval, with no preference it fires once per refresh, and a
// preferred rate above the display's is limited to it. A rate change of the
// display (another mode, another screen) is picked up while the link runs.
// Created through Darling's class factory and its private refresh-rate hook,
// which stand in for a display of the given rate; macOS 14 offers neither
// (links come from NSView, NSWindow and NSScreen) so the test skips there.

@interface CADisplayLink (RefreshRateProbe)
- (void) _setRefreshRateProvider: (double (^)(void)) provider;
@end

@interface Counter : NSObject {
@public
    int ticks;
    CFTimeInterval firstTimestamp;
    CFTimeInterval lastTarget;
    CFTimeInterval lastTimestamp;
}
- (void) tick: (CADisplayLink *) link;
@end
@implementation Counter
- (void) tick: (CADisplayLink *) link {
    if (ticks == 0)
        firstTimestamp = link.timestamp;
    lastTimestamp = link.timestamp;
    lastTarget = link.targetTimestamp;
    ticks++;
}
@end

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static int ticksOver(Counter *c, NSTimeInterval seconds) {
    c->ticks = 0;
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
    return c->ticks;
}

static CADisplayLink *makeLink(Counter *c, double *rate) {
    CADisplayLink *(*create)(id, SEL, id, SEL) = (void *) objc_msgSend;
    Class cls = NSClassFromString(@"CADisplayLink");
    SEL factory = NSSelectorFromString(@"displayLinkWithTarget:selector:");
    if (cls == Nil || ![cls respondsToSelector: factory])
        return nil;
    CADisplayLink *link = create(cls, factory, c, @selector(tick:));
    if (link == nil || ![link respondsToSelector: @selector(_setRefreshRateProvider:)])
        return nil;
    [link _setRefreshRateProvider: ^double {
        return *rate;
    }];
    return link;
}

int main(void) {
    @autoreleasepool {
        Counter *c = [Counter new];
        double rate = 30;
        CADisplayLink *link = makeLink(c, &rate);
        if (link == nil) {
            puts("SKIP: no class factory or refresh-rate hook (macOS)");
            return 0;
        }

        CHECK(fabs(link.duration - 1.0 / 30) < 1e-6, "duration %g for a 30 Hz display", link.duration);
        CHECK(link.preferredFramesPerSecond == 0, "default preferredFramesPerSecond %ld", (long) link.preferredFramesPerSecond);
        [link addToRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
        int n = ticksOver(c, 1.0);
        CHECK(n >= 24 && n <= 33, "30 Hz display gave %d ticks in a second", n);
        CHECK(fabs((c->lastTarget - c->lastTimestamp) - 1.0 / 30) < 1e-3, "target interval %g", c->lastTarget - c->lastTimestamp);

        // A preferred rate above the display's is limited to it.
        link.preferredFramesPerSecond = 120;
        n = ticksOver(c, 1.0);
        CHECK(n <= 33, "120 fps preferred on a 30 Hz display gave %d ticks", n);
        link.preferredFramesPerSecond = 0;
        link.preferredFrameRateRange = (CAFrameRateRange){80, 120, 120};
        n = ticksOver(c, 1.0);
        CHECK(n <= 33, "range above the display's rate gave %d ticks", n);
        link.preferredFrameRateRange = (CAFrameRateRange){0, 0, 0};

        // The display changes to 75 Hz while the link runs: picked up within about a second.
        rate = 75;
        ticksOver(c, 1.4);
        CHECK(fabs(link.duration - 1.0 / 75) < 1e-6, "duration %g after the display changed to 75 Hz", link.duration);
        n = ticksOver(c, 1.0);
        CHECK(n >= 60 && n <= 80, "75 Hz display gave %d ticks in a second", n);

        // A lower preferred rate still works against the new display rate.
        link.preferredFrameRateRange = (CAFrameRateRange){20, 40, 25};
        n = ticksOver(c, 1.0);
        CHECK(n >= 19 && n <= 29, "25 fps preferred gave %d ticks", n);
        [link invalidate];

        // A display that reports no rate falls back to 60 Hz.
        double none = 0;
        Counter *d = [Counter new];
        CADisplayLink *fallback = makeLink(d, &none);
        CHECK(fabs(fallback.duration - 1.0 / 60) < 1e-6, "fallback duration %g", fallback.duration);
        [fallback invalidate];

        if (failures == 0)
            puts("PASS: CADisplayLink follows the display refresh rate");
        return failures != 0;
    }
}
