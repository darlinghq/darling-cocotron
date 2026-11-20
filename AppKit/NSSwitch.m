#import <AppKit/NSSwitch.h>

@implementation NSSwitch

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

- (NSControlStateValue) state {
    return _state;
}

- (void) setState: (NSControlStateValue) state {
    if (state == _state)
        return;
    _state = state;
    [self setNeedsDisplay: YES];
}

// Everything else on NSSwitch is still unimplemented; keep the logging stub so
// an unknown selector reports itself instead of raising.
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
