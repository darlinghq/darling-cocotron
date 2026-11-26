#import <QuartzCore/CAAnimation.h>

@implementation CAPropertyAnimation

- initWithKeyPath: (NSString *) keyPath {
    [super init];
    NS_EXTRA(CAPropertyAnimation, self)->_keyPath = [keyPath copy];
    NS_EXTRA(CAPropertyAnimation, self)->_additive = NO;
    NS_EXTRA(CAPropertyAnimation, self)->_cumulative = NO;
    return self;
}

+ (instancetype) animationWithKeyPath: (NSString *) keyPath {
    return [[[self alloc] initWithKeyPath: keyPath] autorelease];
}

- (NSString *) keyPath {
    return NS_EXTRA(CAPropertyAnimation, self)->_keyPath;
}

- (void) setKeyPath: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CAPropertyAnimation, self)->_keyPath release];
    NS_EXTRA(CAPropertyAnimation, self)->_keyPath = value;
}

- (BOOL) isAdditive {
    return NS_EXTRA(CAPropertyAnimation, self)->_additive;
}

- (void) setAdditive: (BOOL) value {
    NS_EXTRA(CAPropertyAnimation, self)->_additive = value;
}

- (BOOL) isCumulative {
    return NS_EXTRA(CAPropertyAnimation, self)->_cumulative;
}

- (void) setCumulative: (BOOL) value {
    NS_EXTRA(CAPropertyAnimation, self)->_cumulative = value;
}

- (CAValueFunction *) valueFunction {
    return NS_EXTRA(CAPropertyAnimation, self)->_valueFunction;
}

- (void) setValueFunction: (CAValueFunction *) value {
    [value retain];
    [NS_EXTRA(CAPropertyAnimation, self)->_valueFunction release];
    NS_EXTRA(CAPropertyAnimation, self)->_valueFunction = value;
}

- (void) dealloc {
    [NS_EXTRA(CAPropertyAnimation, self)->_keyPath release];
    [NS_EXTRA(CAPropertyAnimation, self)->_valueFunction release];
    NS_EXTRA_FREE(CAPropertyAnimation, self);
    [super dealloc];
}

@end
