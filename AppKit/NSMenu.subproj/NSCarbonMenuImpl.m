#import <Foundation/NSObject.h>

// DUMMY

@interface NSCarbonMenuImpl : NSObject
@end

@implementation NSCarbonMenuImpl
- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"Stub called: %@ in %@",
          NSStringFromSelector([anInvocation selector]), [self class]);
}
@end
