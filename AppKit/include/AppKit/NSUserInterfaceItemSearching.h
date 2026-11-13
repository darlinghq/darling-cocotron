#import <AppKit/NSApplication.h>
#import <Foundation/NSObject.h>

@protocol NSUserInterfaceItemSearching <NSObject>

// TODO

@end

@interface NSApplication (NSUserInterfaceItemSearching)
- (void) registerUserInterfaceItemSearchHandler: (id<NSUserInterfaceItemSearching>) handler;
- (void) unregisterUserInterfaceItemSearchHandler: (id<NSUserInterfaceItemSearching>) handler;
@end
