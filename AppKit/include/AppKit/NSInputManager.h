#import <Foundation/NSObject.h>
#import <AppKit/AppKitIvarLayout.h>

@interface NSInputManager : NSObject {
    NS_LEGACY_IVAR_PAD(_NSInputManagerReserved, 60)
}

+ (NSInputManager *) currentInputManager;
- (void) markedTextAbandoned: (id) client;

@end
