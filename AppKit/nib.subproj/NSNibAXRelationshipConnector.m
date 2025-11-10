#import "NSNibAXRelationshipConnector.h"

@implementation NSNibAXRelationshipConnector

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSNibAXAttributeConnector

- (void) encodeWithCoder: (NSCoder *) aCoder {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

- (id) initWithCoder: (NSCoder *) coder {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return [[NSNibAXAttributeConnector alloc] init];
}

@end
