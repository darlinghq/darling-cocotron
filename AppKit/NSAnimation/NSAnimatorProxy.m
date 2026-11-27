/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import <AppKit/NSAnimatorProxy.h>
#import <AppKit/NSLayoutConstraint.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>

@implementation NSAnimatorProxy

+ (instancetype) animatorProxyForTarget: (id) target {
    NSAnimatorProxy *proxy = [self alloc];
    proxy->_target = [target retain];
    return [proxy autorelease];
}

- (void) dealloc {
    [_target release];
    [super dealloc];
}

- (id) animatorTarget {
    return _target;
}

- (NSMethodSignature *) methodSignatureForSelector: (SEL) selector {
    return [_target methodSignatureForSelector: selector];
}

- (void) forwardInvocation: (NSInvocation *) invocation {
    [invocation invokeWithTarget: _target];
}

- (BOOL) respondsToSelector: (SEL) selector {
    return [_target respondsToSelector: selector];
}

- (BOOL) isKindOfClass: (Class) cls {
    return [_target isKindOfClass: cls];
}

- (BOOL) isMemberOfClass: (Class) cls {
    return [_target isMemberOfClass: cls];
}

- (BOOL) conformsToProtocol: (Protocol *) protocol {
    return [_target conformsToProtocol: protocol];
}

- (NSUInteger) hash {
    return [_target hash];
}

- (NSString *) description {
    return [_target description];
}

@end

@implementation NSLayoutConstraint (NSAnimatablePropertyContainer)

- (instancetype) animator {
    return (id)[NSAnimatorProxy animatorProxyForTarget: self];
}

@end
