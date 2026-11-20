#import <AppKit/AppKitExport.h>
#import <Foundation/NSString.h>

#import <AppKit/NSAccessibilityConstants.h>
#import <AppKit/NSAccessibilityProtocols.h>

@class NSView;

APPKIT_EXPORT void NSAccessibilityPostNotification(id element,
                                                   NSString *notification);

APPKIT_EXPORT NSRect NSAccessibilityFrameInView(NSView *parentView, NSRect frame);
APPKIT_EXPORT NSPoint NSAccessibilityPointInView(NSView *parentView, NSPoint point);

APPKIT_EXPORT NSString *NSAccessibilityRoleDescription(NSString *role,
                                                       NSString *subrole);
APPKIT_EXPORT NSString *NSAccessibilityRoleDescriptionForUIElement(id element);
APPKIT_EXPORT void NSAccessibilityRaiseBadArgumentException(id element,
                                                            NSString *attribute,
                                                            id value);

APPKIT_EXPORT NSString *NSAccessibilityActionDescription(NSString *action);

APPKIT_EXPORT id NSAccessibilityUnignoredAncestor(id element);
APPKIT_EXPORT id NSAccessibilityUnignoredDescendant(id element);
APPKIT_EXPORT NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren);
APPKIT_EXPORT NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild);

// The legacy attribute-based accessibility methods. NSView, NSWindow, NSCell and
// NSApplication implement them on top of the NSAccessibility protocol's methods.
@interface NSObject (NSAccessibility)
- (NSArray *) accessibilityAttributeNames;
- accessibilityAttributeValue: (NSString *) attribute;
- (BOOL) accessibilityIsAttributeSettable: (NSString *) attribute;
- (void) accessibilitySetValue: (id) value forAttribute: (NSString *) attribute;
- (NSArray *) accessibilityParameterizedAttributeNames;
- (NSArray *) accessibilityActionNames;
- (NSString *) accessibilityActionDescription: (NSString *) action;
- (void) accessibilityPerformAction: (NSString *) action;
- (BOOL) accessibilityIsIgnored;
@end

// There is no accessibility server: overrides aren't kept.
@interface NSObject (NSAccessibilityAdditions)
- (BOOL) accessibilitySetOverrideValue: (id) value forAttribute: (NSString *) attribute;
@end
