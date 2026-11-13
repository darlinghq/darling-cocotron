#import <Foundation/NSObject.h>

@interface NSInputManager : NSObject

+ (NSInputManager *) currentInputManager;
- (void) markedTextAbandoned: (id) client;

@end
