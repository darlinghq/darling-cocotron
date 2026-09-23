#import <Foundation/Foundation.h>
#import <QuartzCore/CADisplayLink.h>

@interface CADisplayLink (DisplayLinkPrivateTest)
+ (instancetype)displayLinkWithDisplay:(id)display target:(id)target selector:(SEL)selector;
- (id)display;
@end

static BOOL targetDeallocated;

@interface DisplayLinkTarget : NSObject {
@public
    NSUInteger frames;
    CFTimeInterval lastTimestamp;
    BOOL invalidTime;
}
- (void)frame:(CADisplayLink *)link;
@end

@implementation DisplayLinkTarget
- (void)dealloc {
    targetDeallocated = YES;
    [super dealloc];
}

- (void)frame:(CADisplayLink *)link {
    if (link.timestamp <= 0 || link.targetTimestamp <= link.timestamp ||
        (lastTimestamp > 0 && link.timestamp < lastTimestamp))
        invalidTime = YES;
    lastTimestamp = link.timestamp;
    frames++;
}
@end

static void run_for(NSTimeInterval interval) {
    [[NSRunLoop currentRunLoop] runUntilDate:
        [NSDate dateWithTimeIntervalSinceNow:interval]];
}

int main(void) {
    @autoreleasepool {
        DisplayLinkTarget *target = [[DisplayLinkTarget alloc] init];
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:target
                                                        selector:@selector(frame:)];
        if (!link || link.duration <= 0 || link.preferredFramesPerSecond != 60)
            return 10;

        link.paused = YES;
        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        run_for(0.08);
        if (target->frames != 0)
            return 11;

        link.paused = NO;
        run_for(0.10);
        if (target->frames < 2 || target->invalidTime)
            return 12;

        link.preferredFramesPerSecond = 30;
        if (link.preferredFramesPerSecond != 30 || link.frameInterval != 2)
            return 13;
        NSUInteger previous = target->frames;
        run_for(0.10);
        if (target->frames <= previous)
            return 14;

        [link removeFromRunLoop:[NSRunLoop currentRunLoop]
                         forMode:NSDefaultRunLoopMode];
        previous = target->frames;
        run_for(0.08);
        if (target->frames != previous)
            return 15;

        [link addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [link invalidate];
        run_for(0.08);
        if (target->frames != previous)
            return 16;
        [target release];
        if (!targetDeallocated)
            return 17;

        DisplayLinkTarget *privateTarget = [[DisplayLinkTarget alloc] init];
        NSObject *display = [[NSObject alloc] init];
        CADisplayLink *privateLink = [CADisplayLink displayLinkWithDisplay:display
                                                                  target:privateTarget
                                                                selector:@selector(frame:)];
        if ([privateLink display] != display)
            return 18;
        [privateLink invalidate];
        [privateTarget release];
        [display release];
    }
    return 0;
}
