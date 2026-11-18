#import <QuartzCore/CAAnimation.h>

@implementation CABasicAnimation

- fromValue {
    return NS_EXTRA(CABasicAnimation, self)->_fromValue;
}

- (void) setFromValue: value {
    value = [value retain];
    [NS_EXTRA(CABasicAnimation, self)->_fromValue release];
    NS_EXTRA(CABasicAnimation, self)->_fromValue = value;
}

- toValue {
    return NS_EXTRA(CABasicAnimation, self)->_toValue;
}

- (void) setToValue: value {
    value = [value retain];
    [NS_EXTRA(CABasicAnimation, self)->_toValue release];
    NS_EXTRA(CABasicAnimation, self)->_toValue = value;
}

- byValue {
    return NS_EXTRA(CABasicAnimation, self)->_byValue;
}

- (void) setByValue: value {
    value = [value retain];
    [NS_EXTRA(CABasicAnimation, self)->_byValue release];
    NS_EXTRA(CABasicAnimation, self)->_byValue = value;
}

@end
