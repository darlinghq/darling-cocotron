#import <Foundation/NSObject.h>

@protocol NSValidatedUserInterfaceItem
- (NSInteger) tag;
- (SEL) action;
@end
