#import <Foundation/NSObject.h>

// DUMMY

@interface NSAccessibilityCustomChooser : NSObject
@end

@implementation NSAccessibilityCustomChooser
- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"Stub called: %@ in %@",
          NSStringFromSelector([anInvocation selector]), [self class]);
}
@end

@interface NSAccessibilityCustomChooserItemResult : NSObject
@end

@implementation NSAccessibilityCustomChooserItemResult
- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"Stub called: %@ in %@",
          NSStringFromSelector([anInvocation selector]), [self class]);
}
@end
