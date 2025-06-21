#import <Foundation/NSObject.h>

const NSNotificationName NSPopoverDidCloseNotification = @"NSPopoverDidCloseNotification";
const NSNotificationName NSPopoverWillCloseNotification = @"NSPopoverWillCloseNotification";
const NSNotificationName NSPopoverWillShowNotification = @"NSPopoverWillShowNotification";
const NSNotificationName NSPopoverDidShowNotification = @"NSPopoverDidShowNotification";

@interface NSPopover : NSObject
@end

@implementation NSPopover
- (NSMethodSignature *) methodSignatureForSelector: (SEL) aSelector {
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void) forwardInvocation: (NSInvocation *) anInvocation {
    NSLog(@"Stub called: %@ in %@",
          NSStringFromSelector([anInvocation selector]), [self class]);
}
@end
