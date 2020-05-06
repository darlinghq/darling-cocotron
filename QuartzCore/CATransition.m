#import <QuartzCore/CATransition.h>

@implementation CATransition

- (NSString *) type {
    return _type;
}

- (void) setType: (NSString *) value {
    value = [value copy];
    [_type release];
    _type = value;
}

- (NSString *) subtype {
    return _subtype;
}

- (void) setSubtype: (NSString *) value {
    value = [value copy];
    [_subtype release];
    _subtype = value;
}

- (CGFloat) startProgress {
    return _startProgress;
}

- (void) setStartProgress: (CGFloat) value {
    _startProgress = value;
}

- (CGFloat) endProgress {
    return _endProgress;
}

- (void) setEndProgress: (CGFloat) value {
    _endProgress = value;
}

@end
