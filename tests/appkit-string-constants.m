/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// String constants AppKit exports (public ones and ones no public header declares) must exist and hold the
// value a Mac holds: each is non-nil and equals the string printed for it on macOS 26.7.3, and where the
// symbol exists on macOS 10.14 (Mojave) the same string was printed there. Before the constants were added
// this test did not link.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

// Exported by AppKit, not declared in the public headers.
extern NSString *const NSSharingServiceNameUseAsAccountPicture;
extern NSString *const NSAppleMenuName;
extern NSString *const NSFlowLayoutCommonRowHorizontalAlignmentKey;
extern NSString *const NSFlowLayoutLastRowHorizontalAlignmentKey;
extern NSString *const NSFlowLayoutRowVerticalAlignmentKey;
extern NSString *const NSAccessibilityOpenAction;
extern NSString *const NSImageHintSymbolFont;
extern NSString *const NSSharingServiceParametersDefaultRecipientsKey;
extern NSString *const NSMenuDidCompleteInteractionNotification;
extern NSString *const NSControlWillBeginContinuousTrackingNotification;
extern NSString *const NSControlDidEndContinuousTrackingNotification;
extern NSString *const NSWorkspaceAccessibilityFocusedElementDidChangeNotification;
extern NSString *const NSAccessibilityFocusedElementKey;
extern NSString *const NSAccessibilityEnhancedUserInterfaceAttribute;
extern NSString *const NSInspectorBarFontFamilyItemIdentifier;
extern NSString *const NSInspectorBarFontSizeItemIdentifier;
extern NSString *const NSInspectorBarFontStyleItemIdentifier;
extern NSString *const NSInspectorBarSpaceItemIdentifier;
extern NSString *const NSInspectorBarTextAlignmentItemIdentifier;
extern NSString *const NSInspectorBarTextBackgroundColorItemIdentifier;
extern NSString *const NSInspectorBarTextForegroundColorItemIdentifier;
extern NSString *const NSInspectorBarTextListItemIdentifier;
extern NSString *const NSImageNameToolbarBookmarks;

static int failures;

static const struct {
    NSString *const *constant;
    const char *name;
    const char *value;
} constants[] = {
    {&NSWorkspaceMoveOperation, "NSWorkspaceMoveOperation", "move"},
    {&NSSharingServiceNameUseAsAccountPicture, "NSSharingServiceNameUseAsAccountPicture", "com.apple.share.System.set-account-picture"},
    {&NSAppleMenuName, "NSAppleMenuName", "NSAppleMenu"},
    {&NSToolbarToggleSidebarItemIdentifier, "NSToolbarToggleSidebarItemIdentifier", "NSToolbarToggleSidebarItem"},
    {&NSSharingServiceNameSendViaAirDrop, "NSSharingServiceNameSendViaAirDrop", "com.apple.share.AirDrop.send"},
    {&NSToolbarSidebarTrackingSeparatorItemIdentifier, "NSToolbarSidebarTrackingSeparatorItemIdentifier", "NSToolbarSidebarTrackingSeparatorItemIdentifier"},
    {&NSFlowLayoutCommonRowHorizontalAlignmentKey, "NSFlowLayoutCommonRowHorizontalAlignmentKey", "UIFlowLayoutCommonRowHorizontalAlignmentKey"},
    {&NSFlowLayoutLastRowHorizontalAlignmentKey, "NSFlowLayoutLastRowHorizontalAlignmentKey", "UIFlowLayoutLastRowHorizontalAlignmentKey"},
    {&NSFlowLayoutRowVerticalAlignmentKey, "NSFlowLayoutRowVerticalAlignmentKey", "UIFlowLayoutRowVerticalAlignmentKey"},
    {&NSSharingServiceNameCloudSharing, "NSSharingServiceNameCloudSharing", "com.apple.share.CloudSharing"},
    {&NSAccessibilityOpenAction, "NSAccessibilityOpenAction", "AXOpen"},
    {&NSAccessibilityDateTimeComponentsAttribute, "NSAccessibilityDateTimeComponentsAttribute", "AXDateTimeComponents"},
    {&NSImageHintSymbolFont, "NSImageHintSymbolFont", "NSImageHintSymbolFont"},
    {&NSSharingServiceParametersDefaultRecipientsKey, "NSSharingServiceParametersDefaultRecipientsKey", "NSSharingServiceParametersDefaultRecipientsKey"},
    {&NSApplicationShouldBeginSuppressingHighDynamicRangeContentNotification, "NSApplicationShouldBeginSuppressingHighDynamicRangeContentNotification", "NSApplicationShouldBeginSuppressingHighDynamicRangeContentNotification"},
    {&NSApplicationShouldEndSuppressingHighDynamicRangeContentNotification, "NSApplicationShouldEndSuppressingHighDynamicRangeContentNotification", "NSApplicationShouldEndSuppressingHighDynamicRangeContentNotification"},
    {&NSPopUpButtonCellWillPopUpNotification, "NSPopUpButtonCellWillPopUpNotification", "NSPopUpButtonCellWillPopUpNotification"},
    {&NSMenuDidCompleteInteractionNotification, "NSMenuDidCompleteInteractionNotification", "NSMenuDidCompleteInteractionNotification"},
    {&NSControlWillBeginContinuousTrackingNotification, "NSControlWillBeginContinuousTrackingNotification", "NSControlWillBeginContinuousTrackingNotification"},
    {&NSControlDidEndContinuousTrackingNotification, "NSControlDidEndContinuousTrackingNotification", "NSControlDidEndContinuousTrackingNotification"},
    {&NSWorkspaceAccessibilityFocusedElementDidChangeNotification, "NSWorkspaceAccessibilityFocusedElementDidChangeNotification", "NSWorkspaceAccessibilityFocusedElementDidChangeNotification"},
    {&NSAccessibilityChildrenInNavigationOrderAttribute, "NSAccessibilityChildrenInNavigationOrderAttribute", "AXChildrenInNavigationOrder"},
    {&NSAccessibilityFocusedElementKey, "NSAccessibilityFocusedElementKey", "NSAccessibilityFocusedElementKey"},
    {&NSAccessibilityPopoverRole, "NSAccessibilityPopoverRole", "AXPopover"},
    {&NSAccessibilityEnhancedUserInterfaceAttribute, "NSAccessibilityEnhancedUserInterfaceAttribute", "AXEnhancedUserInterface"},
    {&NSToolbarWritingToolsItemIdentifier, "NSToolbarWritingToolsItemIdentifier", "NSToolbarWritingToolsItem"},
    {&NSTouchBarItemIdentifierTextAlignment, "NSTouchBarItemIdentifierTextAlignment", "NSTouchBarItemIdentifierTextAlignment"},
    {&NSTouchBarItemIdentifierTextColorPicker, "NSTouchBarItemIdentifierTextColorPicker", "NSTouchBarItemIdentifierTextColorPicker"},
    {&NSTouchBarItemIdentifierTextList, "NSTouchBarItemIdentifierTextList", "NSTouchBarItemIdentifierTextList"},
    {&NSTouchBarItemIdentifierTextStyle, "NSTouchBarItemIdentifierTextStyle", "NSTouchBarItemIdentifierTextStyle"},
    {&NSInspectorBarFontFamilyItemIdentifier, "NSInspectorBarFontFamilyItemIdentifier", "NSInspectorBarFontFamilyItemIdentifier"},
    {&NSInspectorBarFontSizeItemIdentifier, "NSInspectorBarFontSizeItemIdentifier", "NSInspectorBarFontSizeItemIdentifier"},
    {&NSInspectorBarFontStyleItemIdentifier, "NSInspectorBarFontStyleItemIdentifier", "NSInspectorBarFontStyleItemIdentifier"},
    {&NSInspectorBarSpaceItemIdentifier, "NSInspectorBarSpaceItemIdentifier", "NSInspectorBarSpaceItemIdentifier"},
    {&NSInspectorBarTextAlignmentItemIdentifier, "NSInspectorBarTextAlignmentItemIdentifier", "NSInspectorBarTextAlignmentItemIdentifier"},
    {&NSInspectorBarTextBackgroundColorItemIdentifier, "NSInspectorBarTextBackgroundColorItemIdentifier", "NSInspectorBarTextBackgroundColorItemIdentifier"},
    {&NSInspectorBarTextForegroundColorItemIdentifier, "NSInspectorBarTextForegroundColorItemIdentifier", "NSInspectorBarTextForegroundColorItemIdentifier"},
    {&NSInspectorBarTextListItemIdentifier, "NSInspectorBarTextListItemIdentifier", "NSInspectorBarTextListItemIdentifier"},
    {&NSTextListMarkerHyphen, "NSTextListMarkerHyphen", "{hyphen}"},
    {&NSFontCollectionUser, "NSFontCollectionUser", "com.apple.UserFonts"},
    {&NSFullScreenModeAllScreens, "NSFullScreenModeAllScreens", "NSFullScreenModeAllScreens"},
    {&NSImageNameToolbarBookmarks, "NSImageNameToolbarBookmarks", "NSToolbarBookmarks"},
    {&NSToolbarItemKey, "NSToolbarItemKey", "item"},
    {&NSOutlineViewShowHideButtonKey, "NSOutlineViewShowHideButtonKey", "NSOutlineViewShowHideButtonKey"},
};

int main(void)
{
    for (size_t i = 0; i < sizeof(constants) / sizeof(constants[0]); i++) {
        NSString *value = *constants[i].constant;
        if (value == nil || ![value isKindOfClass: [NSString class]] || strcmp([value UTF8String], constants[i].value) != 0) {
            printf("FAIL %s\n", constants[i].name);
            failures++;
        }
    }
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures != 0;
}
