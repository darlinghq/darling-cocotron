/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <Foundation/NSProxy.h>

// What -animator of an NSAnimatablePropertyContainer (NSView) returns: a proxy that sends every message it
// gets to the container. Property changes made through it are applied at once; no animation is run, so an
// NSAnimationContext group is over, and its completion handler can run, as soon as its changes block returns.
@interface NSAnimatorProxy : NSProxy {
    id _target;
}

+ (instancetype) animatorProxyForTarget: (id) target;
- (id) animatorTarget;

@end
