#import <Foundation/NSObject.h>
#import <Foundation/NSRange.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSEvent;

@interface NSInputManager : NSObject {
    NS_LEGACY_IVAR_PAD(_NSInputManagerReserved, 60)
}

+ (NSInputManager *) currentInputManager;
- (void) markedTextAbandoned: (id) client;
- (void) markedTextSelectionChanged: (NSRange) newSelection client: (id) client;
- (BOOL) wantsToHandleMouseEvents;
- (BOOL) handleMouseEvent: (NSEvent *) event;

@end
