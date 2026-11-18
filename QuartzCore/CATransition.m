#import <QuartzCore/CATransition.h>

@implementation CATransition

- (NSString *) type {
    return NS_EXTRA(CATransition, self)->_type;
}

- (void) setType: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CATransition, self)->_type release];
    NS_EXTRA(CATransition, self)->_type = value;
}

- (NSString *) subtype {
    return NS_EXTRA(CATransition, self)->_subtype;
}

- (void) setSubtype: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(CATransition, self)->_subtype release];
    NS_EXTRA(CATransition, self)->_subtype = value;
}

- (CGFloat) startProgress {
    return NS_EXTRA(CATransition, self)->_startProgress;
}

- (void) setStartProgress: (CGFloat) value {
    NS_EXTRA(CATransition, self)->_startProgress = value;
}

- (CGFloat) endProgress {
    return NS_EXTRA(CATransition, self)->_endProgress;
}

- (void) setEndProgress: (CGFloat) value {
    NS_EXTRA(CATransition, self)->_endProgress = value;
}

@end
