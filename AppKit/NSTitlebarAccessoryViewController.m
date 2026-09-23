#import <AppKit/NSTitlebarAccessoryViewController.h>
#import <AppKit/NSScrollEdgeEffectStyle.h>

@implementation NSTitlebarAccessoryViewController

@synthesize preferredScrollEdgeEffectStyle = _preferredScrollEdgeEffectStyle;

- (void) dealloc {
    [_preferredScrollEdgeEffectStyle release];
    [super dealloc];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
