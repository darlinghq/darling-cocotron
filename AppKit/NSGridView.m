#import <AppKit/NSView.h>
#import <AppKit/AppKitIvarLayout.h>

const CGFloat NSGridViewSizeForContent = 0;

@interface NSGridView : NSView {
    NS_LEGACY_IVAR_PAD(_NSGridViewReserved, 48)
}
@end
@interface NSGridCell : NSObject {
    NS_LEGACY_IVAR_PAD(_NSGridCellReserved, 44)
}
@end
@interface NSGridColumn : NSObject {
    NS_LEGACY_IVAR_PAD(_NSGridColumnReserved, 44)
}
@end
@interface NSGridRow : NSObject {
    NS_LEGACY_IVAR_PAD(_NSGridRowReserved, 52)
}
@end

@implementation NSGridView

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSGridCell

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSGridColumn

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end

@implementation NSGridRow

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
