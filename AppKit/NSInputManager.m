#import <AppKit/NSInputManager.h>

@implementation NSInputManager

// Cocotron has no input method plug-ins.
+ (NSInputManager *) currentInputManager {
    return nil;
}

- (void) markedTextAbandoned: (id) client {
}

@end
