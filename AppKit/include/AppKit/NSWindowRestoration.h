#import <Foundation/NSObject.h>

@class NSCoder, NSError, NSString, NSWindow;

@protocol NSWindowRestoration <NSObject>
+ (void) restoreWindowWithIdentifier: (NSString *) identifier
                               state: (NSCoder *) state
                   completionHandler: (void (^)(NSWindow *window, NSError *error)) completionHandler;
@end
