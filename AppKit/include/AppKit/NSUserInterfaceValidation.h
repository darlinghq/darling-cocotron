#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NSValidatedUserInterfaceItem
- (NSInteger) tag;
- (nullable SEL) action;
@end

@protocol NSUserInterfaceValidations

// TODO

@end

NS_ASSUME_NONNULL_END
