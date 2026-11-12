#import <Foundation/NSString.h>

typedef NSString *NSUserInterfaceItemIdentifier NS_TYPED_EXTENSIBLE_ENUM;

@protocol NSUserInterfaceItemIdentification

@property(copy) NSUserInterfaceItemIdentifier identifier;

@end

@interface NSObject (NSUserInterfaceItemIdentification)

@property(copy) NSUserInterfaceItemIdentifier userInterfaceItemIdentifier;

@end
