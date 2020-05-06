#import <AppKit/AppKitExport.h>
#import <Foundation/NSString.h>

#import <AppKit/NSAccessibilityConstants.h>
#import <AppKit/NSAccessibilityProtocols.h>

APPKIT_EXPORT void NSAccessibilityPostNotification(id element,
                                                   NSString *notification);

APPKIT_EXPORT NSString *const NSAccessibilityRoleDescription(NSString *role,
                                                             NSString *subrole);

APPKIT_EXPORT id NSAccessibilityUnignoredAncestor(id element);

@interface NSObject (NSAccessibility)
- (NSArray *) accessibilityAttributeNames;
- accessibilityAttributeValue: (NSString *) attribute;
@end
