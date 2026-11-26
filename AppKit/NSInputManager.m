#import <AppKit/NSInputManager.h>

@implementation NSInputManager

// Cocotron has no input method plug-ins.
+ (NSInputManager *) currentInputManager {
    return nil;
}

- (void) markedTextAbandoned: (id) client {
}

- (void) markedTextSelectionChanged: (NSRange) newSelection client: (id) client {
}

// Without an input method there is none to give mouse events to.
- (BOOL) wantsToHandleMouseEvents {
    return NO;
}

- (BOOL) handleMouseEvent: (NSEvent *) event {
    return NO;
}

@end
