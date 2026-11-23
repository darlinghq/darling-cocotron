#import <AppKit/NSPathControl.h>

#import "AppKit/NSRaise.h"
#import <objc/runtime.h>

@implementation NSPathControl

// Operated at once: the click that activates the window is delivered to it
// (see -[NSWindow sendEvent:]).
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    return YES;
}

- (BOOL) isFlipped {
    return YES;
}

- (NSPathStyle) pathStyle; {
    NSPathCell *cell = [self cell];
    return [cell pathStyle];
}

- (void) setPathStyle: (NSPathStyle) style; {
    NSPathCell *cell = [self cell];
    [cell setPathStyle: style];
}

- (NSColor *) backgroundColor; {
    NSPathCell *cell = [self cell];
    return [cell backgroundColor];
}

- (void) setBackgroundColor: (NSColor *) color; {
    NSPathCell *cell = [self cell];
    [cell setBackgroundColor: color];
}

- (NSPathComponentCell *) clickedPathComponentCell {
    NSPathCell *cell = [self cell];
    return [cell clickedPathComponentCell];
}

- (NSArray *) pathComponentCells; {
    NSPathCell *cell = [self cell];
    return [cell pathComponentCells];
}

- (void) setPathComponentCells: (NSArray *) cells; {
    NSPathCell *cell = [self cell];
    [cell setPathComponentCells: cells];
}

- (SEL) doubleAction; {
    NSPathCell *cell = [self cell];
    return [cell doubleAction];
}

- (void) setDoubleAction: (SEL) action; {
    NSPathCell *cell = [self cell];
    [cell setDoubleAction: action];
}

- (NSURL *) URL; {
    NSPathCell *cell = [self cell];
    return [cell URL];
}
- (void) setURL: (NSURL *) url; {
    NSPathCell *cell = [self cell];
    [cell setURL: url];
}

// Apple's SDK declares the delegate property weak, so it is kept as a zeroing
// weak reference in the extra ivars and cannot dangle.
- (id<NSPathControlDelegate>) delegate; {
    return objc_loadWeak(&NS_EXTRA(NSPathControl, self)->_delegate);
}

- (void) setDelegate: (id<NSPathControlDelegate>) delegate; {
    objc_storeWeak(&NS_EXTRA(NSPathControl, self)->_delegate, delegate);
}

- (void) dealloc {
    // A weak slot has to be unregistered before the memory holding it goes.
    if (NS_EXTRA_ALLOCATED(NSPathControl, self))
        objc_storeWeak(&NS_EXTRA(NSPathControl, self)->_delegate, nil);
    NS_EXTRA_FREE(NSPathControl, self);
    [super dealloc];
}

- (void) setDraggingSourceOperationMask: (NSDragOperation) mask
                               forLocal: (BOOL) isLocal;
{
    NSUnimplementedMethod();
}

- (NSMenu *) menu; {
    NSPathCell *cell = [self cell];
    //	return [cell menu];
    return nil;
}

- (void) setMenu: (NSMenu *) menu; {
    NSPathCell *cell = [self cell];
    //	[cell setMenu: menu];
}

+ (void) initialize; {
    if (self == [NSPathControl class]) {
        [self setCellClass: [NSPathCell class]];
    }
}

@end
