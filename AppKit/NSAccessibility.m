#import <AppKit/AppKitExport.h>
#import <Foundation/NSString.h>
#import <AppKit/NSAccessibility.h>
#import <AppKit/NSAccessibilityConstants.h>
#import <AppKit/NSErrors.h>
#import <AppKit/NSView.h>

NSString *const NSAccessibilityChildrenAttribute =
        @"AXChildren";
NSString *const NSAccessibilityContentsAttribute =
        @"AXContents";
NSString *const NSAccessibilityDescriptionAttribute =
        @"AXDescription";
NSString *const NSAccessibilityEnabledAttribute =
        @"AXEnabled";
NSString *const NSAccessibilityFocusedAttribute =
        @"AXFocused";
NSString *const NSAccessibilityRequiredAttribute = @"AXRequired";
NSString *const NSAccessibilityHelpAttribute = @"AXHelp";
NSString *const NSAccessibilityMaxValueAttribute =
        @"AXMaxValue";
NSString *const NSAccessibilityMinValueAttribute =
        @"AXMinValue";
NSString *const NSAccessibilityParentAttribute =
        @"AXParent";
NSString *const NSAccessibilityPositionAttribute =
        @"AXPosition";
NSString *const NSAccessibilityRoleAttribute = @"AXRole";
NSString *const NSAccessibilityRoleDescriptionAttribute =
        @"AXRoleDescription";
NSString *const NSAccessibilitySelectedChildrenAttribute =
        @"AXSelectedChildren";
NSString *const NSAccessibilityShownMenuAttribute =
        @"AXShownMenuUIElement";
NSString *const NSAccessibilitySizeAttribute = @"AXSize";
NSString *const NSAccessibilitySubroleAttribute =
        @"AXSubrole";
NSString *const NSAccessibilityTitleAttribute =
        @"AXTitle";
NSString *const NSAccessibilityTopLevelUIElementAttribute =
        @"AXTopLevelUIElement";
NSString *const NSAccessibilityValueAttribute =
        @"AXValue";
NSString *const NSAccessibilityValueDescriptionAttribute =
        @"AXValueDescription";
NSString *const NSAccessibilityVisibleChildrenAttribute =
        @"AXVisibleChildren";
NSString *const NSAccessibilityWindowAttribute =
        @"AXWindow";
NSString *const NSAccessibilityIdentifierAttribute =
        @"AXIdentifier";

NSString *const NSAccessibilityInsertionPointLineNumberAttribute =
        @"AXInsertionPointLineNumber";
NSString *const NSAccessibilityNumberOfCharactersAttribute =
        @"AXNumberOfCharacters";
NSString *const NSAccessibilitySelectedTextAttribute =
        @"AXSelectedText";
NSString *const NSAccessibilitySelectedTextRangeAttribute =
        @"AXSelectedTextRange";
NSString *const NSAccessibilitySelectedTextRangesAttribute =
        @"AXSelectedTextRanges";
NSString *const NSAccessibilitySharedCharacterRangeAttribute =
        @"AXSharedCharacterRange";
NSString *const NSAccessibilitySharedTextUIElementsAttribute =
        @"AXSharedTextUIElements";
NSString *const NSAccessibilityVisibleCharacterRangeAttribute =
        @"AXVisibleCharacterRange";

NSString *const NSAccessibilityAttributedStringForRangeParameterizedAttribute =
        @"AXAttributedStringForRange";
NSString *const NSAccessibilityBoundsForRangeParameterizedAttribute =
        @"AXBoundsForRange";
NSString *const NSAccessibilityLineForIndexParameterizedAttribute =
        @"AXLineForIndex";
NSString *const NSAccessibilityRTFForRangeParameterizedAttribute =
        @"AXRTFForRange";
NSString *const NSAccessibilityRangeForIndexParameterizedAttribute =
        @"AXRangeForIndex";
NSString *const NSAccessibilityRangeForLineParameterizedAttribute =
        @"AXRangeForLine";
NSString *const NSAccessibilityRangeForPositionParameterizedAttribute =
        @"AXRangeForPosition";
NSString *const NSAccessibilityStringForRangeParameterizedAttribute =
        @"AXStringForRange";
NSString *const NSAccessibilityStyleRangeForIndexParameterizedAttribute =
        @"AXStyleRangeForIndex";

NSString *const NSAccessibilityAttachmentTextAttribute =
        @"AXAttachment";
NSString *const NSAccessibilityBackgroundColorTextAttribute =
        @"AXBackgroundColor";
NSString *const NSAccessibilityFontFamilyKey = @"AXFontFamily";
NSString *const NSAccessibilityFontNameKey = @"AXFontName";
NSString *const NSAccessibilityFontSizeKey = @"AXFontSize";
NSString *const NSAccessibilityFontTextAttribute =
        @"AXFont";
NSString *const NSAccessibilityForegroundColorTextAttribute =
        @"AXForegroundColor";
NSString *const NSAccessibilityLinkTextAttribute =
        @"AXLink";
NSAttributedStringKey const NSAccessibilityMarkedMisspelledTextAttribute = @"AXMarkedMisspelled";
NSString *const NSAccessibilityMisspelledTextAttribute =
        @"AXMisspelled";
NSString *const NSAccessibilityShadowTextAttribute =
        @"AXShadow";
NSString *const NSAccessibilityStrikethroughColorTextAttribute =
        @"AXStrikethroughColor";
NSString *const NSAccessibilityStrikethroughTextAttribute =
        @"AXStrikethrough";
NSString *const NSAccessibilitySuperscriptTextAttribute =
        @"AXSuperscript";
NSString *const NSAccessibilityUnderlineColorTextAttribute =
        @"AXUnderlineColor";
NSString *const NSAccessibilityUnderlineTextAttribute =
        @"AXUnderline";
NSString *const NSAccessibilityVisibleNameKey =
        @"AXVisibleName";

NSString *const NSAccessibilityCancelButtonAttribute =
        @"AXCancelButton";
NSString *const NSAccessibilityCloseButtonAttribute =
        @"AXCloseButton";
NSString *const NSAccessibilityFullScreenButtonAttribute =
        @"AXFullScreenButton";
NSString *const NSAccessibilityDefaultButtonAttribute =
        @"AXDefaultButton";
NSString *const NSAccessibilityGrowAreaAttribute =
        @"AXGrowArea";
NSString *const NSAccessibilityMainAttribute = @"AXMain";
NSString *const NSAccessibilityMinimizeButtonAttribute =
        @"AXMinimizeButton";
NSString *const NSAccessibilityMinimizedAttribute =
        @"AXMinimized";
NSString *const NSAccessibilityModalAttribute =
        @"AXModal";
NSString *const NSAccessibilityProxyAttribute =
        @"AXProxy";
NSString *const NSAccessibilityToolbarButtonAttribute =
        @"AXToolbarButton";
NSString *const NSAccessibilityZoomButtonAttribute =
        @"AXZoomButton";

NSString *const NSAccessibilityHorizontalOrientationValue =
        @"AXHorizontalOrientation";
NSString *const NSAccessibilityVerticalOrientationValue =
        @"AXVerticalOrientation";
NSString *const NSAccessibilityUnknownOrientationValue =
        @"AXUnknownOrientation";

NSString *const NSAccessibilityClearButtonAttribute =
        @"AXClearButton";
NSString *const NSAccessibilityColumnTitlesAttribute =
        @"AXColumnTitles";
NSString *const NSAccessibilityFocusedUIElementAttribute =
        @"AXFocusedUIElement";
NSString *const NSAccessibilityFocusedWindowAttribute =
        @"AXFocusedWindow";
NSString *const NSAccessibilityFrontmostAttribute =
        @"AXFrontmost";
NSString *const NSAccessibilityHiddenAttribute =
        @"AXHidden";
NSString *const NSAccessibilityMainWindowAttribute =
        @"AXMainWindow";
NSString *const NSAccessibilityMenuBarAttribute =
        @"AXMenuBar";
NSString *const NSAccessibilityOrientationAttribute =
        @"AXOrientation";
NSString *const NSAccessibilitySearchButtonAttribute =
        @"AXSearchButton";
NSString *const NSAccessibilitySearchMenuAttribute =
        @"AXSearchMenu";
NSString *const NSAccessibilityWindowsAttribute =
        @"AXWindows";

NSString *const NSAccessibilityColumnCountAttribute =
        @"AXColumnCount";
NSString *const NSAccessibilityOrderedByRowAttribute =
        @"AXOrderedByRow";
NSString *const NSAccessibilityRowCountAttribute =
        @"AXRowCount";

NSString *const NSAccessibilityColumnHeaderUIElementsAttribute =
        @"AXColumnHeaderUIElements";
NSString *const NSAccessibilityColumnsAttribute =
        @"AXColumns";
NSString *const NSAccessibilityRowHeaderUIElementsAttribute =
        @"AXRowHeaderUIElements";
NSString *const NSAccessibilityRowsAttribute = @"AXRows";
NSString *const NSAccessibilitySelectedColumnsAttribute =
        @"AXSelectedColumns";
NSString *const NSAccessibilitySelectedRowsAttribute =
        @"AXSelectedRows";
NSString *const NSAccessibilitySortDirectionAttribute =
        @"AXSortDirection";
NSString *const NSAccessibilityVisibleColumnsAttribute =
        @"AXVisibleColumns";
NSString *const NSAccessibilityVisibleRowsAttribute =
        @"AXVisibleRows";

NSString *const NSAccessibilityDisclosedByRowAttribute =
        @"AXDisclosedByRow";
NSString *const NSAccessibilityDisclosedRowsAttribute =
        @"AXDisclosedRows";
NSString *const NSAccessibilityDisclosingAttribute =
        @"AXDisclosing";
NSString *const NSAccessibilityDisclosureLevelAttribute =
        @"AXDisclosureLevel";

NSString *const NSAccessibilitySelectedCellsAttribute =
        @"AXSelectedCells";
NSString *const NSAccessibilityVisibleCellsAttribute =
        @"AXVisibleCells";

NSString *const NSAccessibilityCellForColumnAndRowParameterizedAttribute =
        @"AXCellForColumnAndRow";

NSString *const NSAccessibilityRowIndexRangeAttribute =
        @"AXRowIndexRange";
NSString *const NSAccessibilityColumnIndexRangeAttribute =
        @"AXColumnIndexRange";

NSString *const NSAccessibilityAscendingSortDirectionValue =
        @"AXAscendingSortDirection";
NSString *const NSAccessibilityDescendingSortDirectionValue =
        @"AXDescendingSortDirection";
NSString *const NSAccessibilityUnknownSortDirectionValue =
        @"AXUnknownSortDirection";

NSString *const NSAccessibilityHorizontalUnitsAttribute =
        @"AXHorizontalUnits";
NSString *const NSAccessibilityVerticalUnitsAttribute =
        @"AXVerticalUnits";
NSString *const NSAccessibilityHorizontalUnitDescriptionAttribute =
        @"AXHorizontalUnitDescription";
NSString *const NSAccessibilityVerticalUnitDescriptionAttribute =
        @"AXVerticalUnitDescription";

NSString *const NSAccessibilityLayoutPointForScreenPointParameterizedAttribute =
        @"AXLayoutPointForScreenPoint";
NSString *const NSAccessibilityLayoutSizeForScreenSizeParameterizedAttribute =
        @"AXLayoutSizeForScreenSize";
NSString *const NSAccessibilityScreenPointForLayoutPointParameterizedAttribute =
        @"AXScreenPointForLayoutPoint";
NSString *const NSAccessibilityScreenSizeForLayoutSizeParameterizedAttribute =
        @"AXScreenSizeForLayoutSize";

NSString *const NSAccessibilityHandlesAttribute =
        @"AXHandles";

NSString *const NSAccessibilityAllowedValuesAttribute =
        @"AXAllowedValues";
NSString *const NSAccessibilityLabelUIElementsAttribute =
        @"AXLabelUIElements";
NSString *const NSAccessibilityLabelValueAttribute =
        @"AXLabelValue";

NSString *const NSAccessibilityMatteContentUIElementAttribute =
        @"AXMatteContentUIElement";
NSString *const NSAccessibilityMatteHoleAttribute =
        @"AXMatteHole";

NSString *const NSAccessibilityMarkerGroupUIElementAttribute =
        @"AXMarkerGroupUIElement";
NSString *const NSAccessibilityMarkerTypeAttribute =
        @"AXMarkerType";
NSString *const NSAccessibilityMarkerTypeDescriptionAttribute =
        @"AXMarkerTypeDescription";
NSString *const NSAccessibilityMarkerUIElementsAttribute =
        @"AXMarkerUIElements";
NSString *const NSAccessibilityMarkerValuesAttribute =
        @"AXMarkerValues";
NSString *const NSAccessibilityUnitDescriptionAttribute =
        @"AXUnitDescription";
NSString *const NSAccessibilityUnitsAttribute =
        @"AXUnits";

NSString *const NSAccessibilityCenterTabStopMarkerTypeValue =
        @"AXCenterTabStopMarkerType";
NSString *const NSAccessibilityDecimalTabStopMarkerTypeValue =
        @"AXDecimalTabStopMarkerType";
NSString *const NSAccessibilityFirstLineIndentMarkerTypeValue =
        @"AXFirstLineIndentMarkerType";
NSString *const NSAccessibilityHeadIndentMarkerTypeValue =
        @"AXHeadIndentMarkerType";
NSString *const NSAccessibilityLeftTabStopMarkerTypeValue =
        @"AXLeftTabStopMarkerType";
NSString *const NSAccessibilityRightTabStopMarkerTypeValue =
        @"AXRightTabStopMarkerType";
NSString *const NSAccessibilityTailIndentMarkerTypeValue =
        @"AXTailIndentMarkerType";
NSString *const NSAccessibilityUnknownMarkerTypeValue =
        @"AXUnknownMarkerType";

NSString *const NSAccessibilityCentimetersUnitValue =
        @"AXCentimentersUnit";
NSString *const NSAccessibilityInchesUnitValue =
        @"AXInchesUnit";
NSString *const NSAccessibilityPicasUnitValue =
        @"AXPicasUnit";
NSString *const NSAccessibilityPointsUnitValue =
        @"AXPointsUnit";
NSString *const NSAccessibilityUnknownUnitValue =
        @"AXUnknownUnit";

NSString *const NSAccessibilityLinkedUIElementsAttribute =
        @"AXLinkedUIElements";
NSString *const NSAccessibilityServesAsTitleForUIElementsAttribute =
        @"AXServesAsTitleForUIElements";
NSString *const NSAccessibilityTitleUIElementAttribute =
        @"AXTitleUIElement";

NSString *const NSAccessibilityDecrementButtonAttribute =
        @"AXDecrementButton";
NSString *const NSAccessibilityDocumentAttribute =
        @"AXDocument";
NSString *const NSAccessibilityEditedAttribute =
        @"AXEdited";
NSString *const NSAccessibilityExpandedAttribute =
        @"AXExpanded";
NSString *const NSAccessibilityFilenameAttribute =
        @"AXFilename";
NSString *const NSAccessibilityHeaderAttribute =
        @"AXHeader";
NSString *const NSAccessibilityHorizontalScrollBarAttribute =
        @"AXHorizontalScrollBar";
NSString *const NSAccessibilityIncrementButtonAttribute =
        @"AXIncrementButton";
NSString *const NSAccessibilityIndexAttribute =
        @"AXIndex";
NSString *const NSAccessibilityNextContentsAttribute =
        @"AXNextContents";
NSString *const NSAccessibilityOverflowButtonAttribute =
        @"AXOverflowButton";
NSString *const NSAccessibilityPreviousContentsAttribute =
        @"AXPreviousContents";
NSString *const NSAccessibilitySelectedAttribute =
        @"AXSelected";
NSString *const NSAccessibilitySplittersAttribute =
        @"AXSplitters";
NSString *const NSAccessibilityTabsAttribute = @"AXTabs";
NSString *const NSAccessibilityURLAttribute = @"AXURL";
NSString *const NSAccessibilityVerticalScrollBarAttribute =
        @"AXVerticalScrollBar";
NSString *const NSAccessibilityWarningValueAttribute =
        @"AXWarningValue";
NSString *const NSAccessibilityCriticalValueAttribute =
        @"AXCriticalValue";
NSString *const NSAccessibilityPlaceholderValueAttribute =
        @"AXPlaceholderValue";

NSString *const NSAccessibilityApplicationRole =
        @"AXApplication";
NSString *const NSAccessibilityBrowserRole = @"AXBrowser";
NSString *const NSAccessibilityBusyIndicatorRole =
        @"AXBusyIndicator";
NSString *const NSAccessibilityButtonRole = @"AXButton";
NSString *const NSAccessibilityCellRole = @"AXCell";
NSString *const NSAccessibilityCheckBoxRole = @"AXCheckBox";
NSString *const NSAccessibilityColorWellRole = @"AXColorWell";
NSString *const NSAccessibilityColumnRole = @"AXColumn";
NSString *const NSAccessibilityComboBoxRole = @"AXComboBox";
NSString *const NSAccessibilityDisclosureTriangleRole =
        @"AXDisclosureTriangle";
NSString *const NSAccessibilityDrawerRole = @"AXDrawer";
NSString *const NSAccessibilityGridRole = @"AXGrid";
NSString *const NSAccessibilityGroupRole = @"AXGroup";
NSString *const NSAccessibilityGrowAreaRole = @"AXGrowArea";
NSString *const NSAccessibilityHandleRole = @"AXHandle";
NSString *const NSAccessibilityHelpTagRole = @"AXHelpTag";
NSString *const NSAccessibilityImageRole = @"AXImage";
NSString *const NSAccessibilityIncrementorRole =
        @"AXIncrementor";
NSString *const NSAccessibilityLayoutAreaRole =
        @"AXLayoutArea";
NSString *const NSAccessibilityLayoutItemRole =
        @"AXLayoutItem";
NSAccessibilityRole const NSAccessibilityLevelIndicatorRole = @"AXLevelIndicator";
NSString *const NSAccessibilityLinkRole = @"AXLink";
NSString *const NSAccessibilityListRole = @"AXList";
NSString *const NSAccessibilityMatteRole = @"AXMatte";
NSAccessibilityRole const NSAccessibilityMenuBarItemRole = @"AXMenuBarItem";
NSString *const NSAccessibilityMenuBarRole = @"AXMenuBar";
NSString *const NSAccessibilityMenuButtonRole =
        @"AXMenuButton";
NSString *const NSAccessibilityMenuItemRole = @"AXMenuItem";
NSString *const NSAccessibilityMenuRole = @"AXMenu";
NSString *const NSAccessibilityOutlineRole = @"AXOutline";
NSString *const NSAccessibilityPopUpButtonRole =
        @"AXPopUpButton";
NSString *const NSAccessibilityProgressIndicatorRole =
        @"AXProgressIndicator";
NSString *const NSAccessibilityRadioButtonRole =
        @"AXRadioButton";
NSString *const NSAccessibilityRadioGroupRole =
        @"AXRadioGroup";
NSString *const NSAccessibilityRelevanceIndicatorRole =
        @"AXRelevanceIndicator";
NSString *const NSAccessibilityRowRole = @"AXRow";
NSString *const NSAccessibilityRulerMarkerRole =
        @"AXRulerMarker";
NSString *const NSAccessibilityRulerRole = @"AXRuler";
NSString *const NSAccessibilityScrollAreaRole =
        @"AXScrollArea";
NSString *const NSAccessibilityScrollBarRole = @"AXScrollBar";
NSString *const NSAccessibilitySheetRole = @"AXSheet";
NSString *const NSAccessibilitySliderRole = @"AXSlider";
NSString *const NSAccessibilitySortButtonRole =
        @"AXSortButton";
NSString *const NSAccessibilitySplitGroupRole =
        @"AXSplitGroup";
NSString *const NSAccessibilitySplitterRole = @"AXSplitter";
NSString *const NSAccessibilityStaticTextRole =
        @"AXStaticText";
NSString *const NSAccessibilitySystemWideRole =
        @"AXSystemWide";
NSString *const NSAccessibilityTabGroupRole = @"AXTabGroup";
NSString *const NSAccessibilityTableRole = @"AXTable";
NSString *const NSAccessibilityTextAreaRole = @"AXTextArea";
NSString *const NSAccessibilityTextFieldRole = @"AXTextField";
NSString *const NSAccessibilityToolbarRole = @"AXToolbar";
NSString *const NSAccessibilityUnknownRole = @"AXUnknown";
NSString *const NSAccessibilityValueIndicatorRole =
        @"AXValueIndicator";
NSString *const NSAccessibilityWindowRole = @"AXWindow";

NSString *const NSAccessibilityCloseButtonSubrole =
        @"AXCloseButton";
NSString *const NSAccessibilityDecrementArrowSubrole =
        @"AXDecrementArrow";
NSString *const NSAccessibilityDecrementPageSubrole =
        @"AXDecrementPage";
NSString *const NSAccessibilityDialogSubrole = @"AXDialog";
NSString *const NSAccessibilityFloatingWindowSubrole =
        @"AXFloatingWindow";
NSString *const NSAccessibilityIncrementArrowSubrole =
        @"AXIncrementArrow";
NSString *const NSAccessibilityIncrementPageSubrole =
        @"AXIncrementPage";
NSString *const NSAccessibilityMinimizeButtonSubrole =
        @"AXMinimizeButton";
NSString *const NSAccessibilityOutlineRowSubrole =
        @"AXOutlineRow";
NSString *const NSAccessibilitySearchFieldSubrole =
        @"AXSearchField";
NSString *const NSAccessibilitySecureTextFieldSubrole =
        @"AXSecureTextField";
NSString *const NSAccessibilityStandardWindowSubrole =
        @"AXStandardWindow";
NSString *const NSAccessibilitySystemDialogSubrole =
        @"AXSystemDialog";
NSString *const NSAccessibilitySystemFloatingWindowSubrole =
        @"AXSystemFloatingWindow";
NSString *const NSAccessibilityTabButtonSubrole = @"AXTabButton";
NSString *const NSAccessibilityTableRowSubrole =
        @"AXTableRow";
NSString *const NSAccessibilityTextAttachmentSubrole =
        @"AXTextAttachment";
NSString *const NSAccessibilityTextLinkSubrole =
        @"AXTextLink";
NSString *const NSAccessibilityTimelineSubrole =
        @"AXTimeline";
NSString *const NSAccessibilityToolbarButtonSubrole =
        @"AXToolbarButton";
NSString *const NSAccessibilityUnknownSubrole =
        @"AXUnknown";
NSString *const NSAccessibilityZoomButtonSubrole =
        @"AXZoomButton";
NSString *const NSAccessibilitySortButtonSubrole =
        @"AXSortButton";
NSString *const NSAccessibilityRatingIndicatorSubrole =
        @"AXRatingIndicator";
NSString *const NSAccessibilityContentListSubrole =
        @"AXContentList";
NSString *const NSAccessibilityDefinitionListSubrole =
        @"AXDefinitionList";

NSString *const NSAccessibilityCancelAction = @"AXCancel";
NSString *const NSAccessibilityConfirmAction = @"AXConfirm";
NSString *const NSAccessibilityDecrementAction = @"AXDecrement";
NSString *const NSAccessibilityDeleteAction = @"AXDelete";
NSString *const NSAccessibilityIncrementAction = @"AXIncrement";
NSString *const NSAccessibilityPickAction = @"AXPick";
NSString *const NSAccessibilityPressAction = @"AXPress";
NSString *const NSAccessibilityRaiseAction = @"AXRaise";
NSAccessibilityActionName const NSAccessibilityShowAlternateUIAction = @"AXShowAlternateUI";
NSAccessibilityActionName const NSAccessibilityShowDefaultUIAction = @"AXShowDefaultUI";
NSString *const NSAccessibilityShowMenuAction = @"AXShowMenu";

NSString *const NSAccessibilityMainWindowChangedNotification =
        @"AXMainWindowChanged";
NSString *const NSAccessibilityFocusedWindowChangedNotification =
        @"AXFocusedWindowChanged";
NSString *const NSAccessibilityFocusedUIElementChangedNotification =
        @"AXFocusedUIElementChanged";

NSString *const NSAccessibilityWindowCreatedNotification =
        @"AXWindowCreated";
NSString *const NSAccessibilityWindowDeminiaturizedNotification =
        @"AXWindowDeminiaturized";
NSString *const NSAccessibilityWindowMiniaturizedNotification =
        @"AXWindowMiniaturized";
NSString *const NSAccessibilityWindowMovedNotification =
        @"AXWindowMoved";
NSString *const NSAccessibilityWindowResizedNotification =
        @"AXWindowResized";

NSString *const NSAccessibilityApplicationActivatedNotification =
        @"AXApplicationActivated";
NSString *const NSAccessibilityApplicationDeactivatedNotification =
        @"AXApplicationDeactivated";
NSString *const NSAccessibilityApplicationHiddenNotification =
        @"AXApplicationHidden";
NSString *const NSAccessibilityApplicationShownNotification =
        @"AXApplicationShown";

NSString *const NSAccessibilityDrawerCreatedNotification =
        @"AXDrawerCreated";
NSString *const NSAccessibilitySheetCreatedNotification =
        @"AXSheetCreated";

NSString *const NSAccessibilityCreatedNotification =
        @"AXCreated";
NSString *const NSAccessibilityMovedNotification =
        @"AXMoved";
NSString *const NSAccessibilityResizedNotification =
        @"AXResized";
NSString *const NSAccessibilityTitleChangedNotification =
        @"AXTitleChanged";
NSString *const NSAccessibilityUIElementDestroyedNotification =
        @"AXUIElementDestroyed";
NSString *const NSAccessibilityValueChangedNotification =
        @"AXValueChanged";

NSString *const NSAccessibilityHelpTagCreatedNotification =
        @"AXHelpTagCreated";
NSString *const NSAccessibilityRowCountChangedNotification =
        @"AXRowCountChanged";
NSString *const NSAccessibilitySelectedChildrenChangedNotification =
        @"AXSelectedChildrenChanged";
NSString *const NSAccessibilitySelectedColumnsChangedNotification =
        @"AXSelectedColumnsChanged";
NSString *const NSAccessibilitySelectedRowsChangedNotification =
        @"AXSelectedRowsChanged";
NSString *const NSAccessibilitySelectedTextChangedNotification =
        @"AXSelectedTextChanged";
NSString *const NSAccessibilityRowExpandedNotification =
        @"AXRowExpanded";
NSString *const NSAccessibilityRowCollapsedNotification =
        @"AXRowCollapsed";
NSString *const NSAccessibilitySelectedCellsChangedNotification =
        @"AXSelectedCellsChanged";
NSString *const NSAccessibilityUnitsChangedNotification =
        @"AXUnitsChanged";
NSString *const NSAccessibilitySelectedChildrenMovedNotification =
        @"AXSelectedChildrenMoved";

// Checked against macOS: this is the only constant here whose value is its own name.
NSString *const NSAccessibilityErrorCodeExceptionInfo =
        @"NSAccessibilityErrorCodeExceptionInfo";

NSString *const NSAccessibilityActivationPointAttribute = @"AXActivationPoint";

/* Undocumented */
NSString *const NSAccessibilityEventProcessedNotification = @"AXEventProcessed";
NSString *const NSAccessibilityEventSourceProcessIDKey =
        @"AXEventSourceProcessIDKey";
NSString *const NSAccessibilityEventSourceStateIDKey = @"AXEventSourceStateID";
NSString *const NSAccessibilityEventSourceUserDataKey =
        @"AXEventSourceUserDataKey";
NSString *const NSAccessibilityEventTimestampKey = @"AXEventTimestampKey";
NSString *const NSAccessibilityMainThreadIdleNotification = @"AXMainThreadIdle";
NSString *const NSAccessibilitySupportsMainThreadIdleNotificationAttribute =
        @"AXSupportsMainThreadIdleNotification";
/* End undocumented */

NSString *const NSAccessibilityLayoutChangedNotification = @"AXLayoutChanged";
NSString *const NSAccessibilityUIElementsKey = @"AXUIElementsKey";
NSString *const NSAccessibilityToggleSubrole = @"AXToggle";

NSString *const NSAccessibilityFullScreenButtonSubrole = @"AXFullScreenButton";

NSString *const NSAccessibilityAnnouncementKey = @"AXAnnouncementKey";
NSString *const NSAccessibilityAnnouncementRequestedNotification = @"AXAnnouncementRequested";
NSString *const NSAccessibilityPriorityKey = @"AXPriorityKey";

NSRect NSAccessibilityFrameInView(NSView *parentView, NSRect frame) {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return frame;
}

void NSAccessibilityPostNotification(id element, NSString *notification) {
}

NSString *NSAccessibilityRoleDescription(NSString *role, NSString *subrole) {
    return nil;
}

NSString *NSAccessibilityRoleDescriptionForUIElement(id element) {
    return nil;
}

void NSAccessibilityRaiseBadArgumentException(id element, NSString *attribute,
                                              id value)
{
    [NSException raise: NSAccessibilityException
                format: @"Bad argument %@ for attribute %@ of %@", value,
                        attribute, element];
}

// Cocotron never treats an element as ignored, so each of these returns what it was given.
id NSAccessibilityUnignoredAncestor(id element) {
    return element;
}

id NSAccessibilityUnignoredDescendant(id element) {
    return element;
}

NSArray *NSAccessibilityUnignoredChildren(NSArray *originalChildren) {
    return originalChildren;
}

NSArray *NSAccessibilityUnignoredChildrenForOnlyChild(id originalChild) {
    return originalChild ? [NSArray arrayWithObject: originalChild] : [NSArray array];
}

@implementation NSObject (NSAccessibility)

- (BOOL) accessibilitySetOverrideValue: (id) value forAttribute: (NSString *) attribute {
    return NO;
}

@end

void NSAccessibilityPostNotificationWithUserInfo(id element,
                                                 NSAccessibilityNotificationName notification,
                                                 NSDictionary<NSAccessibilityNotificationUserInfoKey, id> *userInfo)
{
    printf("STUB %s\n", __PRETTY_FUNCTION__);
}

NSString *NSAccessibilityActionDescription(NSString *action) {
    if (action == nil)
        return @"";

    static struct {
        NSString *const *action;
        NSString *description;
    } const descriptions[] = {
        {&NSAccessibilityCancelAction, @"cancel"},
        {&NSAccessibilityConfirmAction, @"confirm"},
        {&NSAccessibilityDecrementAction, @"decrement"},
        {&NSAccessibilityDeleteAction, @"delete"},
        {&NSAccessibilityIncrementAction, @"increment"},
        {&NSAccessibilityPickAction, @"pick"},
        {&NSAccessibilityPressAction, @"press"},
        {&NSAccessibilityRaiseAction, @"raise"},
        {&NSAccessibilityShowAlternateUIAction, @"show alternate items"},
        {&NSAccessibilityShowDefaultUIAction, @"show default items"},
        {&NSAccessibilityShowMenuAction, @"show menu"},
    };

    for (size_t i = 0; i < sizeof(descriptions) / sizeof(descriptions[0]); i++) {
        if ([action isEqualToString: *descriptions[i].action])
            return descriptions[i].description;
    }

    // An action AppKit does not define is described by its own name.
    return action;
}
