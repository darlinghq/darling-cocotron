#import <Foundation/NSString.h>
#import <QuartzCore/CAValueFunction.h>

NSString *const kCAValueFunctionTranslate = @"kCAValueFunctionTranslate";
NSString *const kCAValueFunctionTranslateX = @"kCAValueFunctionTranslateX";
NSString *const kCAValueFunctionTranslateY = @"kCAValueFunctionTranslateY";
NSString *const kCAValueFunctionTranslateZ = @"kCAValueFunctionTranslateZ";

NSString *const kCAValueFunctionScale = @"kCAValueFunctionScale";
NSString *const kCAValueFunctionScaleX = @"kCAValueFunctionScaleX";
NSString *const kCAValueFunctionScaleY = @"kCAValueFunctionScaleY";
NSString *const kCAValueFunctionScaleZ = @"kCAValueFunctionScaleZ";

NSString *const kCAValueFunctionRotateX = @"kCAValueFunctionRotateX";
NSString *const kCAValueFunctionRotateY = @"kCAValueFunctionRotateY";
NSString *const kCAValueFunctionRotateZ = @"kCAValueFunctionRotateZ";

@implementation CAValueFunction

- initWithName: (NSString *) name {
    NS_EXTRA(CAValueFunction, self)->_name = [name copy];
    return self;
}

- (void) dealloc {
    [NS_EXTRA(CAValueFunction, self)->_name release];
    NS_EXTRA_FREE(CAValueFunction, self);
    [super dealloc];
}

+ functionWithName: (NSString *) name {
    return [[[self alloc] initWithName: name] autorelease];
}

- (NSString *) name {
    return NS_EXTRA(CAValueFunction, self)->_name;
}

@end
