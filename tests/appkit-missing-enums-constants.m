/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Enumerators and string constants of the public AppKit API that the headers lacked: every enumerator has the
// public value (a compile-time check, so a mismatch fails the build of this test) and every string constant
// the documented value. The values were observed by printing them on macOS 26.7.3. The Touch Bar image names
// used to be defined as their own C names.
#import <AppKit/AppKit.h>
#import <AppKit/NSTabViewController.h>
#import <AppKit/NSTableViewRowAction.h>
#include <stdio.h>
#include <string.h>

_Static_assert((long long) NSApplicationOcclusionStateVisible == 2LL, "NSApplicationOcclusionStateVisible");
_Static_assert((long long) NSAscendingPageOrder == 1LL, "NSAscendingPageOrder");
_Static_assert((long long) NSBrowserAutoColumnResizing == 1LL, "NSBrowserAutoColumnResizing");
_Static_assert((long long) NSBrowserDropAbove == 1LL, "NSBrowserDropAbove");
_Static_assert((long long) NSBrowserDropOn == 0LL, "NSBrowserDropOn");
_Static_assert((long long) NSBrowserNoColumnResizing == 0LL, "NSBrowserNoColumnResizing");
_Static_assert((long long) NSBrowserUserColumnResizing == 2LL, "NSBrowserUserColumnResizing");
_Static_assert((long long) NSCollectionElementCategoryDecorationView == 2LL, "NSCollectionElementCategoryDecorationView");
_Static_assert((long long) NSCollectionElementCategoryInterItemGap == 3LL, "NSCollectionElementCategoryInterItemGap");
_Static_assert((long long) NSCollectionElementCategoryItem == 0LL, "NSCollectionElementCategoryItem");
_Static_assert((long long) NSCollectionElementCategorySupplementaryView == 1LL, "NSCollectionElementCategorySupplementaryView");
_Static_assert((long long) NSCollectionUpdateActionDelete == 1LL, "NSCollectionUpdateActionDelete");
_Static_assert((long long) NSCollectionUpdateActionInsert == 0LL, "NSCollectionUpdateActionInsert");
_Static_assert((long long) NSCollectionUpdateActionMove == 3LL, "NSCollectionUpdateActionMove");
_Static_assert((long long) NSCollectionUpdateActionNone == 4LL, "NSCollectionUpdateActionNone");
_Static_assert((long long) NSCollectionUpdateActionReload == 2LL, "NSCollectionUpdateActionReload");
_Static_assert((long long) NSCollectionViewDropBefore == 1LL, "NSCollectionViewDropBefore");
_Static_assert((long long) NSCollectionViewDropOn == 0LL, "NSCollectionViewDropOn");
_Static_assert((long long) NSCollectionViewItemHighlightAsDropTarget == 3LL, "NSCollectionViewItemHighlightAsDropTarget");
_Static_assert((long long) NSCollectionViewItemHighlightForDeselection == 2LL, "NSCollectionViewItemHighlightForDeselection");
_Static_assert((long long) NSCollectionViewItemHighlightForSelection == 1LL, "NSCollectionViewItemHighlightForSelection");
_Static_assert((long long) NSCollectionViewItemHighlightNone == 0LL, "NSCollectionViewItemHighlightNone");
_Static_assert((long long) NSCollectionViewScrollDirectionHorizontal == 1LL, "NSCollectionViewScrollDirectionHorizontal");
_Static_assert((long long) NSCollectionViewScrollDirectionVertical == 0LL, "NSCollectionViewScrollDirectionVertical");
_Static_assert((long long) NSCollectionViewScrollPositionBottom == 4LL, "NSCollectionViewScrollPositionBottom");
_Static_assert((long long) NSCollectionViewScrollPositionCenteredHorizontally == 16LL, "NSCollectionViewScrollPositionCenteredHorizontally");
_Static_assert((long long) NSCollectionViewScrollPositionCenteredVertically == 2LL, "NSCollectionViewScrollPositionCenteredVertically");
_Static_assert((long long) NSCollectionViewScrollPositionLeadingEdge == 64LL, "NSCollectionViewScrollPositionLeadingEdge");
_Static_assert((long long) NSCollectionViewScrollPositionLeft == 8LL, "NSCollectionViewScrollPositionLeft");
_Static_assert((long long) NSCollectionViewScrollPositionNearestHorizontalEdge == 512LL, "NSCollectionViewScrollPositionNearestHorizontalEdge");
_Static_assert((long long) NSCollectionViewScrollPositionNearestVerticalEdge == 256LL, "NSCollectionViewScrollPositionNearestVerticalEdge");
_Static_assert((long long) NSCollectionViewScrollPositionNone == 0LL, "NSCollectionViewScrollPositionNone");
_Static_assert((long long) NSCollectionViewScrollPositionRight == 32LL, "NSCollectionViewScrollPositionRight");
_Static_assert((long long) NSCollectionViewScrollPositionTop == 1LL, "NSCollectionViewScrollPositionTop");
_Static_assert((long long) NSCollectionViewScrollPositionTrailingEdge == 128LL, "NSCollectionViewScrollPositionTrailingEdge");
_Static_assert((long long) NSColorSpaceModelCMYK == 2LL, "NSColorSpaceModelCMYK");
_Static_assert((long long) NSColorSpaceModelDeviceN == 4LL, "NSColorSpaceModelDeviceN");
_Static_assert((long long) NSColorSpaceModelGray == 0LL, "NSColorSpaceModelGray");
_Static_assert((long long) NSColorSpaceModelIndexed == 5LL, "NSColorSpaceModelIndexed");
_Static_assert((long long) NSColorSpaceModelLAB == 3LL, "NSColorSpaceModelLAB");
_Static_assert((long long) NSColorSpaceModelPatterned == 6LL, "NSColorSpaceModelPatterned");
_Static_assert((long long) NSColorSpaceModelRGB == 1LL, "NSColorSpaceModelRGB");
_Static_assert((long long) NSColorSpaceModelUnknown == (-1LL), "NSColorSpaceModelUnknown");
_Static_assert((long long) NSColorSystemEffectDeepPressed == 2LL, "NSColorSystemEffectDeepPressed");
_Static_assert((long long) NSColorSystemEffectDisabled == 3LL, "NSColorSystemEffectDisabled");
_Static_assert((long long) NSColorSystemEffectNone == 0LL, "NSColorSystemEffectNone");
_Static_assert((long long) NSColorSystemEffectPressed == 1LL, "NSColorSystemEffectPressed");
_Static_assert((long long) NSColorSystemEffectRollover == 4LL, "NSColorSystemEffectRollover");
_Static_assert((long long) NSControlCharacterActionContainerBreak == 32LL, "NSControlCharacterActionContainerBreak");
_Static_assert((long long) NSControlCharacterActionHorizontalTab == 4LL, "NSControlCharacterActionHorizontalTab");
_Static_assert((long long) NSControlCharacterActionLineBreak == 8LL, "NSControlCharacterActionLineBreak");
_Static_assert((long long) NSControlCharacterActionParagraphBreak == 16LL, "NSControlCharacterActionParagraphBreak");
_Static_assert((long long) NSControlCharacterActionWhitespace == 2LL, "NSControlCharacterActionWhitespace");
_Static_assert((long long) NSControlCharacterActionZeroAdvancement == 1LL, "NSControlCharacterActionZeroAdvancement");
_Static_assert((long long) NSDescendingPageOrder == (-1LL), "NSDescendingPageOrder");
_Static_assert((long long) NSDisplayGamutP3 == 2LL, "NSDisplayGamutP3");
_Static_assert((long long) NSDisplayGamutSRGB == 1LL, "NSDisplayGamutSRGB");
_Static_assert((long long) NSDraggingContextOutsideApplication == 0LL, "NSDraggingContextOutsideApplication");
_Static_assert((long long) NSDraggingContextWithinApplication == 1LL, "NSDraggingContextWithinApplication");
_Static_assert((long long) NSDraggingFormationDefault == 0LL, "NSDraggingFormationDefault");
_Static_assert((long long) NSDraggingFormationList == 3LL, "NSDraggingFormationList");
_Static_assert((long long) NSDraggingFormationNone == 1LL, "NSDraggingFormationNone");
_Static_assert((long long) NSDraggingFormationPile == 2LL, "NSDraggingFormationPile");
_Static_assert((long long) NSDraggingFormationStack == 4LL, "NSDraggingFormationStack");
_Static_assert((long long) NSDraggingItemEnumerationClearNonenumeratedImages == 65536LL, "NSDraggingItemEnumerationClearNonenumeratedImages");
_Static_assert((long long) NSDraggingItemEnumerationConcurrent == 1LL, "NSDraggingItemEnumerationConcurrent");
_Static_assert((long long) NSEventButtonMaskPenLowerSide == 2LL, "NSEventButtonMaskPenLowerSide");
_Static_assert((long long) NSEventButtonMaskPenTip == 1LL, "NSEventButtonMaskPenTip");
_Static_assert((long long) NSEventButtonMaskPenUpperSide == 4LL, "NSEventButtonMaskPenUpperSide");
_Static_assert((long long) NSEventGestureAxisHorizontal == 1LL, "NSEventGestureAxisHorizontal");
_Static_assert((long long) NSEventGestureAxisNone == 0LL, "NSEventGestureAxisNone");
_Static_assert((long long) NSEventGestureAxisVertical == 2LL, "NSEventGestureAxisVertical");
_Static_assert((long long) NSEventSwipeTrackingClampGestureAmount == 2LL, "NSEventSwipeTrackingClampGestureAmount");
_Static_assert((long long) NSEventSwipeTrackingLockDirection == 1LL, "NSEventSwipeTrackingLockDirection");
_Static_assert((long long) NSFindPanelSubstringMatchTypeContains == 0LL, "NSFindPanelSubstringMatchTypeContains");
_Static_assert((long long) NSFindPanelSubstringMatchTypeEndsWith == 3LL, "NSFindPanelSubstringMatchTypeEndsWith");
_Static_assert((long long) NSFindPanelSubstringMatchTypeFullWord == 2LL, "NSFindPanelSubstringMatchTypeFullWord");
_Static_assert((long long) NSFindPanelSubstringMatchTypeStartsWith == 1LL, "NSFindPanelSubstringMatchTypeStartsWith");
_Static_assert((long long) NSFontCollectionApplicationOnlyMask == 1LL, "NSFontCollectionApplicationOnlyMask");
_Static_assert((long long) NSFontCollectionVisibilityComputer == 4LL, "NSFontCollectionVisibilityComputer");
_Static_assert((long long) NSFontCollectionVisibilityProcess == 1LL, "NSFontCollectionVisibilityProcess");
_Static_assert((long long) NSFontCollectionVisibilityUser == 2LL, "NSFontCollectionVisibilityUser");
_Static_assert((long long) NSFontDescriptorClassClarendonSerifs == 1073741824LL, "NSFontDescriptorClassClarendonSerifs");
_Static_assert((long long) NSFontDescriptorClassFreeformSerifs == 1879048192LL, "NSFontDescriptorClassFreeformSerifs");
_Static_assert((long long) NSFontDescriptorClassMask == 4026531840LL, "NSFontDescriptorClassMask");
_Static_assert((long long) NSFontDescriptorClassModernSerifs == 805306368LL, "NSFontDescriptorClassModernSerifs");
_Static_assert((long long) NSFontDescriptorClassOldStyleSerifs == 268435456LL, "NSFontDescriptorClassOldStyleSerifs");
_Static_assert((long long) NSFontDescriptorClassOrnamentals == 2415919104LL, "NSFontDescriptorClassOrnamentals");
_Static_assert((long long) NSFontDescriptorClassSansSerif == 2147483648LL, "NSFontDescriptorClassSansSerif");
_Static_assert((long long) NSFontDescriptorClassScripts == 2684354560LL, "NSFontDescriptorClassScripts");
_Static_assert((long long) NSFontDescriptorClassSlabSerifs == 1342177280LL, "NSFontDescriptorClassSlabSerifs");
_Static_assert((long long) NSFontDescriptorClassSymbolic == 3221225472LL, "NSFontDescriptorClassSymbolic");
_Static_assert((long long) NSFontDescriptorClassTransitionalSerifs == 536870912LL, "NSFontDescriptorClassTransitionalSerifs");
_Static_assert((long long) NSFontDescriptorClassUnknown == 0LL, "NSFontDescriptorClassUnknown");
_Static_assert((long long) NSFontDescriptorTraitBold == 2LL, "NSFontDescriptorTraitBold");
_Static_assert((long long) NSFontDescriptorTraitCondensed == 64LL, "NSFontDescriptorTraitCondensed");
_Static_assert((long long) NSFontDescriptorTraitExpanded == 32LL, "NSFontDescriptorTraitExpanded");
_Static_assert((long long) NSFontDescriptorTraitItalic == 1LL, "NSFontDescriptorTraitItalic");
_Static_assert((long long) NSFontDescriptorTraitLooseLeading == 65536LL, "NSFontDescriptorTraitLooseLeading");
_Static_assert((long long) NSFontDescriptorTraitMonoSpace == 1024LL, "NSFontDescriptorTraitMonoSpace");
_Static_assert((long long) NSFontDescriptorTraitTightLeading == 32768LL, "NSFontDescriptorTraitTightLeading");
_Static_assert((long long) NSFontDescriptorTraitUIOptimized == 4096LL, "NSFontDescriptorTraitUIOptimized");
_Static_assert((long long) NSFontDescriptorTraitVertical == 2048LL, "NSFontDescriptorTraitVertical");
_Static_assert((long long) NSFontPanelModeMaskAllEffects == 1048320LL, "NSFontPanelModeMaskAllEffects");
_Static_assert((long long) NSFontPanelModeMaskCollection == 4LL, "NSFontPanelModeMaskCollection");
_Static_assert((long long) NSFontPanelModeMaskDocumentColorEffect == 2048LL, "NSFontPanelModeMaskDocumentColorEffect");
_Static_assert((long long) NSFontPanelModeMaskFace == 1LL, "NSFontPanelModeMaskFace");
_Static_assert((long long) NSFontPanelModeMaskShadowEffect == 4096LL, "NSFontPanelModeMaskShadowEffect");
_Static_assert((long long) NSFontPanelModeMaskSize == 2LL, "NSFontPanelModeMaskSize");
_Static_assert((long long) NSFontPanelModeMaskStrikethroughEffect == 512LL, "NSFontPanelModeMaskStrikethroughEffect");
_Static_assert((long long) NSFontPanelModeMaskTextColorEffect == 1024LL, "NSFontPanelModeMaskTextColorEffect");
_Static_assert((long long) NSFontPanelModeMaskUnderlineEffect == 256LL, "NSFontPanelModeMaskUnderlineEffect");
_Static_assert((long long) NSFontPanelModesMaskAllModes == 4294967295LL, "NSFontPanelModesMaskAllModes");
_Static_assert((long long) NSFontPanelModesMaskStandardModes == 65535LL, "NSFontPanelModesMaskStandardModes");
_Static_assert((long long) NSGlyphPropertyControlCharacter == 2LL, "NSGlyphPropertyControlCharacter");
_Static_assert((long long) NSGlyphPropertyElastic == 4LL, "NSGlyphPropertyElastic");
_Static_assert((long long) NSGlyphPropertyNonBaseCharacter == 8LL, "NSGlyphPropertyNonBaseCharacter");
_Static_assert((long long) NSGlyphPropertyNull == 1LL, "NSGlyphPropertyNull");
_Static_assert((long long) NSImageLayoutDirectionLeftToRight == 2LL, "NSImageLayoutDirectionLeftToRight");
_Static_assert((long long) NSImageLayoutDirectionRightToLeft == 3LL, "NSImageLayoutDirectionRightToLeft");
_Static_assert((long long) NSImageLayoutDirectionUnspecified == (-1LL), "NSImageLayoutDirectionUnspecified");
_Static_assert((long long) NSImageLoadStatusCancelled == 1LL, "NSImageLoadStatusCancelled");
_Static_assert((long long) NSImageLoadStatusCompleted == 0LL, "NSImageLoadStatusCompleted");
_Static_assert((long long) NSImageLoadStatusInvalidData == 2LL, "NSImageLoadStatusInvalidData");
_Static_assert((long long) NSImageLoadStatusReadError == 4LL, "NSImageLoadStatusReadError");
_Static_assert((long long) NSImageLoadStatusUnexpectedEOF == 3LL, "NSImageLoadStatusUnexpectedEOF");
_Static_assert((long long) NSImageRepLoadStatusCompleted == (-6LL), "NSImageRepLoadStatusCompleted");
_Static_assert((long long) NSImageRepLoadStatusInvalidData == (-4LL), "NSImageRepLoadStatusInvalidData");
_Static_assert((long long) NSImageRepLoadStatusReadingHeader == (-2LL), "NSImageRepLoadStatusReadingHeader");
_Static_assert((long long) NSImageRepLoadStatusUnexpectedEOF == (-5LL), "NSImageRepLoadStatusUnexpectedEOF");
_Static_assert((long long) NSImageRepLoadStatusUnknownType == (-1LL), "NSImageRepLoadStatusUnknownType");
_Static_assert((long long) NSImageRepLoadStatusWillNeedAllData == (-3LL), "NSImageRepLoadStatusWillNeedAllData");
_Static_assert((long long) NSLevelIndicatorPlaceholderVisibilityAlways == 1LL, "NSLevelIndicatorPlaceholderVisibilityAlways");
_Static_assert((long long) NSLevelIndicatorPlaceholderVisibilityAutomatic == 0LL, "NSLevelIndicatorPlaceholderVisibilityAutomatic");
_Static_assert((long long) NSLevelIndicatorPlaceholderVisibilityWhileEditing == 2LL, "NSLevelIndicatorPlaceholderVisibilityWhileEditing");
_Static_assert((long long) NSMenuPropertyItemAccessibilityDescription == 32LL, "NSMenuPropertyItemAccessibilityDescription");
_Static_assert((long long) NSMenuPropertyItemAttributedTitle == 2LL, "NSMenuPropertyItemAttributedTitle");
_Static_assert((long long) NSMenuPropertyItemEnabled == 16LL, "NSMenuPropertyItemEnabled");
_Static_assert((long long) NSMenuPropertyItemImage == 8LL, "NSMenuPropertyItemImage");
_Static_assert((long long) NSMenuPropertyItemKeyEquivalent == 4LL, "NSMenuPropertyItemKeyEquivalent");
_Static_assert((long long) NSMenuPropertyItemTitle == 1LL, "NSMenuPropertyItemTitle");
_Static_assert((long long) NSMenuSelectionModeAutomatic == 0LL, "NSMenuSelectionModeAutomatic");
_Static_assert((long long) NSMenuSelectionModeSelectAny == 2LL, "NSMenuSelectionModeSelectAny");
_Static_assert((long long) NSMenuSelectionModeSelectOne == 1LL, "NSMenuSelectionModeSelectOne");
_Static_assert((long long) NSPageControllerTransitionStyleHorizontalStrip == 2LL, "NSPageControllerTransitionStyleHorizontalStrip");
_Static_assert((long long) NSPageControllerTransitionStyleStackBook == 1LL, "NSPageControllerTransitionStyleStackBook");
_Static_assert((long long) NSPageControllerTransitionStyleStackHistory == 0LL, "NSPageControllerTransitionStyleStackHistory");
_Static_assert((long long) NSPageLayoutResultCancelled == 0LL, "NSPageLayoutResultCancelled");
_Static_assert((long long) NSPageLayoutResultChanged == 1LL, "NSPageLayoutResultChanged");
_Static_assert((long long) NSPaperOrientationLandscape == 1LL, "NSPaperOrientationLandscape");
_Static_assert((long long) NSPaperOrientationPortrait == 0LL, "NSPaperOrientationPortrait");
_Static_assert((long long) NSPasteboardContentsCurrentHostOnly == 1LL, "NSPasteboardContentsCurrentHostOnly");
_Static_assert((long long) NSPasteboardReadingAsData == 0LL, "NSPasteboardReadingAsData");
_Static_assert((long long) NSPasteboardReadingAsKeyedArchive == 4LL, "NSPasteboardReadingAsKeyedArchive");
_Static_assert((long long) NSPasteboardReadingAsPropertyList == 2LL, "NSPasteboardReadingAsPropertyList");
_Static_assert((long long) NSPasteboardReadingAsString == 1LL, "NSPasteboardReadingAsString");
_Static_assert((long long) NSPasteboardWritingPromised == 512LL, "NSPasteboardWritingPromised");
_Static_assert((long long) NSPointingDeviceTypeCursor == 2LL, "NSPointingDeviceTypeCursor");
_Static_assert((long long) NSPointingDeviceTypeEraser == 3LL, "NSPointingDeviceTypeEraser");
_Static_assert((long long) NSPointingDeviceTypePen == 1LL, "NSPointingDeviceTypePen");
_Static_assert((long long) NSPointingDeviceTypeUnknown == 0LL, "NSPointingDeviceTypeUnknown");
_Static_assert((long long) NSPopoverAppearanceHUD == 1LL, "NSPopoverAppearanceHUD");
_Static_assert((long long) NSPopoverAppearanceMinimal == 0LL, "NSPopoverAppearanceMinimal");
_Static_assert((long long) NSPrintPanelResultCancelled == 0LL, "NSPrintPanelResultCancelled");
_Static_assert((long long) NSPrintPanelResultPrinted == 1LL, "NSPrintPanelResultPrinted");
_Static_assert((long long) NSPrintRenderingQualityBest == 0LL, "NSPrintRenderingQualityBest");
_Static_assert((long long) NSPrintRenderingQualityResponsive == 1LL, "NSPrintRenderingQualityResponsive");
_Static_assert((long long) NSPrinterTableError == 2LL, "NSPrinterTableError");
_Static_assert((long long) NSPrinterTableNotFound == 1LL, "NSPrinterTableNotFound");
_Static_assert((long long) NSPrinterTableOK == 0LL, "NSPrinterTableOK");
_Static_assert((long long) NSProgressIndicatorPreferredAquaThickness == 12LL, "NSProgressIndicatorPreferredAquaThickness");
_Static_assert((long long) NSProgressIndicatorPreferredLargeThickness == 18LL, "NSProgressIndicatorPreferredLargeThickness");
_Static_assert((long long) NSProgressIndicatorPreferredSmallThickness == 10LL, "NSProgressIndicatorPreferredSmallThickness");
_Static_assert((long long) NSProgressIndicatorPreferredThickness == 14LL, "NSProgressIndicatorPreferredThickness");
_Static_assert((long long) NSRemoteNotificationTypeAlert == 4LL, "NSRemoteNotificationTypeAlert");
_Static_assert((long long) NSRemoteNotificationTypeBadge == 1LL, "NSRemoteNotificationTypeBadge");
_Static_assert((long long) NSRemoteNotificationTypeNone == 0LL, "NSRemoteNotificationTypeNone");
_Static_assert((long long) NSRemoteNotificationTypeSound == 2LL, "NSRemoteNotificationTypeSound");
_Static_assert((long long) NSRuleEditorNestingModeCompound == 2LL, "NSRuleEditorNestingModeCompound");
_Static_assert((long long) NSRuleEditorNestingModeList == 1LL, "NSRuleEditorNestingModeList");
_Static_assert((long long) NSRuleEditorNestingModeSimple == 3LL, "NSRuleEditorNestingModeSimple");
_Static_assert((long long) NSRuleEditorNestingModeSingle == 0LL, "NSRuleEditorNestingModeSingle");
_Static_assert((long long) NSRuleEditorRowTypeCompound == 1LL, "NSRuleEditorRowTypeCompound");
_Static_assert((long long) NSRuleEditorRowTypeSimple == 0LL, "NSRuleEditorRowTypeSimple");
_Static_assert((long long) NSScrollViewFindBarPositionAboveContent == 1LL, "NSScrollViewFindBarPositionAboveContent");
_Static_assert((long long) NSScrollViewFindBarPositionAboveHorizontalRuler == 0LL, "NSScrollViewFindBarPositionAboveHorizontalRuler");
_Static_assert((long long) NSScrollViewFindBarPositionBelowContent == 2LL, "NSScrollViewFindBarPositionBelowContent");
_Static_assert((long long) NSScrubberAlignmentCenter == 3LL, "NSScrubberAlignmentCenter");
_Static_assert((long long) NSScrubberAlignmentLeading == 1LL, "NSScrubberAlignmentLeading");
_Static_assert((long long) NSScrubberAlignmentNone == 0LL, "NSScrubberAlignmentNone");
_Static_assert((long long) NSScrubberAlignmentTrailing == 2LL, "NSScrubberAlignmentTrailing");
_Static_assert((long long) NSScrubberModeFixed == 0LL, "NSScrubberModeFixed");
_Static_assert((long long) NSScrubberModeFree == 1LL, "NSScrubberModeFree");
_Static_assert((long long) NSSegmentDistributionFill == 1LL, "NSSegmentDistributionFill");
_Static_assert((long long) NSSegmentDistributionFillEqually == 2LL, "NSSegmentDistributionFillEqually");
_Static_assert((long long) NSSegmentDistributionFillProportionally == 3LL, "NSSegmentDistributionFillProportionally");
_Static_assert((long long) NSSegmentDistributionFit == 0LL, "NSSegmentDistributionFit");
_Static_assert((long long) NSSharingContentScopeFull == 2LL, "NSSharingContentScopeFull");
_Static_assert((long long) NSSharingContentScopeItem == 0LL, "NSSharingContentScopeItem");
_Static_assert((long long) NSSharingContentScopePartial == 1LL, "NSSharingContentScopePartial");
_Static_assert((long long) NSSpecialPageOrder == 0LL, "NSSpecialPageOrder");
_Static_assert((long long) NSSplitViewItemCollapseBehaviorDefault == 0LL, "NSSplitViewItemCollapseBehaviorDefault");
_Static_assert((long long) NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView == 2LL, "NSSplitViewItemCollapseBehaviorPreferResizingSiblingsWithFixedSplitView");
_Static_assert((long long) NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings == 1LL, "NSSplitViewItemCollapseBehaviorPreferResizingSplitViewWithFixedSiblings");
_Static_assert((long long) NSSplitViewItemCollapseBehaviorUseConstraints == 3LL, "NSSplitViewItemCollapseBehaviorUseConstraints");
_Static_assert((long long) NSSpringLoadingContinuousActivation == 2LL, "NSSpringLoadingContinuousActivation");
_Static_assert((long long) NSSpringLoadingDisabled == 0LL, "NSSpringLoadingDisabled");
_Static_assert((long long) NSSpringLoadingEnabled == 1LL, "NSSpringLoadingEnabled");
_Static_assert((long long) NSSpringLoadingHighlightEmphasized == 2LL, "NSSpringLoadingHighlightEmphasized");
_Static_assert((long long) NSSpringLoadingHighlightNone == 0LL, "NSSpringLoadingHighlightNone");
_Static_assert((long long) NSSpringLoadingHighlightStandard == 1LL, "NSSpringLoadingHighlightStandard");
_Static_assert((long long) NSSpringLoadingNoHover == 8LL, "NSSpringLoadingNoHover");
_Static_assert((long long) NSTabViewBorderTypeBezel == 2LL, "NSTabViewBorderTypeBezel");
_Static_assert((long long) NSTabViewBorderTypeLine == 1LL, "NSTabViewBorderTypeLine");
_Static_assert((long long) NSTabViewBorderTypeNone == 0LL, "NSTabViewBorderTypeNone");
_Static_assert((long long) NSTabViewControllerTabStyleSegmentedControlOnBottom == 1LL, "NSTabViewControllerTabStyleSegmentedControlOnBottom");
_Static_assert((long long) NSTabViewControllerTabStyleSegmentedControlOnTop == 0LL, "NSTabViewControllerTabStyleSegmentedControlOnTop");
_Static_assert((long long) NSTabViewControllerTabStyleToolbar == 2LL, "NSTabViewControllerTabStyleToolbar");
_Static_assert((long long) NSTabViewControllerTabStyleUnspecified == (-1LL), "NSTabViewControllerTabStyleUnspecified");
_Static_assert((long long) NSTableRowActionEdgeLeading == 0LL, "NSTableRowActionEdgeLeading");
_Static_assert((long long) NSTableRowActionEdgeTrailing == 1LL, "NSTableRowActionEdgeTrailing");
_Static_assert((long long) NSTableViewDraggingDestinationFeedbackStyleGap == 2LL, "NSTableViewDraggingDestinationFeedbackStyleGap");
_Static_assert((long long) NSTableViewDraggingDestinationFeedbackStyleNone == (-1LL), "NSTableViewDraggingDestinationFeedbackStyleNone");
_Static_assert((long long) NSTableViewDraggingDestinationFeedbackStyleRegular == 0LL, "NSTableViewDraggingDestinationFeedbackStyleRegular");
_Static_assert((long long) NSTableViewDraggingDestinationFeedbackStyleSourceList == 1LL, "NSTableViewDraggingDestinationFeedbackStyleSourceList");
_Static_assert((long long) NSTableViewFirstColumnOnlyAutoresizingStyle == 5LL, "NSTableViewFirstColumnOnlyAutoresizingStyle");
_Static_assert((long long) NSTableViewLastColumnOnlyAutoresizingStyle == 4LL, "NSTableViewLastColumnOnlyAutoresizingStyle");
_Static_assert((long long) NSTableViewNoColumnAutoresizing == 0LL, "NSTableViewNoColumnAutoresizing");
_Static_assert((long long) NSTableViewReverseSequentialColumnAutoresizingStyle == 3LL, "NSTableViewReverseSequentialColumnAutoresizingStyle");
_Static_assert((long long) NSTableViewRowActionStyleDestructive == 1LL, "NSTableViewRowActionStyleDestructive");
_Static_assert((long long) NSTableViewRowActionStyleRegular == 0LL, "NSTableViewRowActionStyleRegular");
_Static_assert((long long) NSTableViewSequentialColumnAutoresizingStyle == 2LL, "NSTableViewSequentialColumnAutoresizingStyle");
_Static_assert((long long) NSTableViewUniformColumnAutoresizingStyle == 1LL, "NSTableViewUniformColumnAutoresizingStyle");
_Static_assert((long long) NSTextFinderActionHideFindInterface == 11LL, "NSTextFinderActionHideFindInterface");
_Static_assert((long long) NSTextFinderActionHideReplaceInterface == 13LL, "NSTextFinderActionHideReplaceInterface");
_Static_assert((long long) NSTextFinderActionNextMatch == 2LL, "NSTextFinderActionNextMatch");
_Static_assert((long long) NSTextFinderActionPreviousMatch == 3LL, "NSTextFinderActionPreviousMatch");
_Static_assert((long long) NSTextFinderActionReplace == 5LL, "NSTextFinderActionReplace");
_Static_assert((long long) NSTextFinderActionReplaceAll == 4LL, "NSTextFinderActionReplaceAll");
_Static_assert((long long) NSTextFinderActionReplaceAllInSelection == 8LL, "NSTextFinderActionReplaceAllInSelection");
_Static_assert((long long) NSTextFinderActionReplaceAndFind == 6LL, "NSTextFinderActionReplaceAndFind");
_Static_assert((long long) NSTextFinderActionSelectAll == 9LL, "NSTextFinderActionSelectAll");
_Static_assert((long long) NSTextFinderActionSelectAllInSelection == 10LL, "NSTextFinderActionSelectAllInSelection");
_Static_assert((long long) NSTextFinderActionSetSearchString == 7LL, "NSTextFinderActionSetSearchString");
_Static_assert((long long) NSTextFinderActionShowFindInterface == 1LL, "NSTextFinderActionShowFindInterface");
_Static_assert((long long) NSTextFinderActionShowReplaceInterface == 12LL, "NSTextFinderActionShowReplaceInterface");
_Static_assert((long long) NSTextFinderMatchingTypeContains == 0LL, "NSTextFinderMatchingTypeContains");
_Static_assert((long long) NSTextFinderMatchingTypeEndsWith == 3LL, "NSTextFinderMatchingTypeEndsWith");
_Static_assert((long long) NSTextFinderMatchingTypeFullWord == 2LL, "NSTextFinderMatchingTypeFullWord");
_Static_assert((long long) NSTextFinderMatchingTypeStartsWith == 1LL, "NSTextFinderMatchingTypeStartsWith");
_Static_assert((long long) NSTextMovementBacktab == 18LL, "NSTextMovementBacktab");
_Static_assert((long long) NSTextMovementCancel == 23LL, "NSTextMovementCancel");
_Static_assert((long long) NSTextMovementDown == 22LL, "NSTextMovementDown");
_Static_assert((long long) NSTextMovementLeft == 19LL, "NSTextMovementLeft");
_Static_assert((long long) NSTextMovementOther == 0LL, "NSTextMovementOther");
_Static_assert((long long) NSTextMovementReturn == 16LL, "NSTextMovementReturn");
_Static_assert((long long) NSTextMovementRight == 20LL, "NSTextMovementRight");
_Static_assert((long long) NSTextMovementTab == 17LL, "NSTextMovementTab");
_Static_assert((long long) NSTextMovementUp == 21LL, "NSTextMovementUp");
_Static_assert((long long) NSTextScalingStandard == 0LL, "NSTextScalingStandard");
_Static_assert((long long) NSTextScalingiOS == 1LL, "NSTextScalingiOS");
_Static_assert((long long) NSToolbarItemGroupControlRepresentationAutomatic == 0LL, "NSToolbarItemGroupControlRepresentationAutomatic");
_Static_assert((long long) NSToolbarItemGroupControlRepresentationCollapsed == 2LL, "NSToolbarItemGroupControlRepresentationCollapsed");
_Static_assert((long long) NSToolbarItemGroupControlRepresentationExpanded == 1LL, "NSToolbarItemGroupControlRepresentationExpanded");
_Static_assert((long long) NSToolbarItemGroupSelectionModeMomentary == 2LL, "NSToolbarItemGroupSelectionModeMomentary");
_Static_assert((long long) NSToolbarItemGroupSelectionModeSelectAny == 1LL, "NSToolbarItemGroupSelectionModeSelectAny");
_Static_assert((long long) NSToolbarItemGroupSelectionModeSelectOne == 0LL, "NSToolbarItemGroupSelectionModeSelectOne");
_Static_assert((long long) NSUnknownPageOrder == 2LL, "NSUnknownPageOrder");
_Static_assert((long long) NSViewControllerTransitionAllowUserInteraction == 4096LL, "NSViewControllerTransitionAllowUserInteraction");
_Static_assert((long long) NSViewControllerTransitionCrossfade == 1LL, "NSViewControllerTransitionCrossfade");
_Static_assert((long long) NSViewControllerTransitionNone == 0LL, "NSViewControllerTransitionNone");
_Static_assert((long long) NSViewControllerTransitionSlideBackward == 384LL, "NSViewControllerTransitionSlideBackward");
_Static_assert((long long) NSViewControllerTransitionSlideDown == 32LL, "NSViewControllerTransitionSlideDown");
_Static_assert((long long) NSViewControllerTransitionSlideForward == 320LL, "NSViewControllerTransitionSlideForward");
_Static_assert((long long) NSViewControllerTransitionSlideLeft == 64LL, "NSViewControllerTransitionSlideLeft");
_Static_assert((long long) NSViewControllerTransitionSlideRight == 128LL, "NSViewControllerTransitionSlideRight");
_Static_assert((long long) NSViewControllerTransitionSlideUp == 16LL, "NSViewControllerTransitionSlideUp");
_Static_assert((long long) NSWindowUserTabbingPreferenceAlways == 1LL, "NSWindowUserTabbingPreferenceAlways");
_Static_assert((long long) NSWindowUserTabbingPreferenceInFullScreen == 2LL, "NSWindowUserTabbingPreferenceInFullScreen");
_Static_assert((long long) NSWindowUserTabbingPreferenceManual == 0LL, "NSWindowUserTabbingPreferenceManual");
_Static_assert((long long) NSWorkspaceAuthorizationTypeCreateSymbolicLink == 0LL, "NSWorkspaceAuthorizationTypeCreateSymbolicLink");
_Static_assert((long long) NSWorkspaceAuthorizationTypeReplaceFile == 2LL, "NSWorkspaceAuthorizationTypeReplaceFile");
_Static_assert((long long) NSWorkspaceAuthorizationTypeSetAttributes == 1LL, "NSWorkspaceAuthorizationTypeSetAttributes");
_Static_assert((long long) NSWritingDirectionEmbedding == 0LL, "NSWritingDirectionEmbedding");
_Static_assert((long long) NSWritingDirectionOverride == 2LL, "NSWritingDirectionOverride");
_Static_assert(NSScrollerNoPart == 0 && NSScrollerDecrementPage == 1 && NSScrollerKnob == 2 && NSScrollerIncrementPage == 3 &&
                       NSScrollerDecrementLine == 4 && NSScrollerIncrementLine == 5 && NSScrollerKnobSlot == 6,
               "NSScrollerPart has the public values");

static int failures;

static const struct {
    NSString *const *constant;
    const char *name;
    const char *value;
} constants[] = {
    {&NSAboutPanelOptionCredits, "NSAboutPanelOptionCredits", "Credits"},
    {&NSAboutPanelOptionApplicationName, "NSAboutPanelOptionApplicationName", "ApplicationName"},
    {&NSAboutPanelOptionApplicationIcon, "NSAboutPanelOptionApplicationIcon", "ApplicationIcon"},
    {&NSAboutPanelOptionVersion, "NSAboutPanelOptionVersion", "Version"},
    {&NSAboutPanelOptionApplicationVersion, "NSAboutPanelOptionApplicationVersion", "ApplicationVersion"},
    {&NSApplicationLaunchRemoteNotificationKey, "NSApplicationLaunchRemoteNotificationKey", "NSApplicationLaunchRemoteNotificationKey"},
    {&NSApplicationDidChangeOcclusionStateNotification, "NSApplicationDidChangeOcclusionStateNotification", "NSApplicationDidChangeOcclusionStateNotification"},
    {&NSFontCollectionDidChangeNotification, "NSFontCollectionDidChangeNotification", "NSFontCollectionDidChange"},
    {&NSFontTextStyleLargeTitle, "NSFontTextStyleLargeTitle", "UICTFontTextStyleTitle0"},
    {&NSFontTextStyleTitle1, "NSFontTextStyleTitle1", "UICTFontTextStyleTitle1"},
    {&NSFontTextStyleTitle2, "NSFontTextStyleTitle2", "UICTFontTextStyleTitle2"},
    {&NSFontTextStyleTitle3, "NSFontTextStyleTitle3", "UICTFontTextStyleTitle3"},
    {&NSFontTextStyleHeadline, "NSFontTextStyleHeadline", "UICTFontTextStyleHeadline"},
    {&NSFontTextStyleSubheadline, "NSFontTextStyleSubheadline", "UICTFontTextStyleSubhead"},
    {&NSFontTextStyleBody, "NSFontTextStyleBody", "UICTFontTextStyleBody"},
    {&NSFontTextStyleCallout, "NSFontTextStyleCallout", "UICTFontTextStyleCallout"},
    {&NSFontTextStyleFootnote, "NSFontTextStyleFootnote", "UICTFontTextStyleFootnote"},
    {&NSFontTextStyleCaption1, "NSFontTextStyleCaption1", "UICTFontTextStyleCaption1"},
    {&NSFontTextStyleCaption2, "NSFontTextStyleCaption2", "UICTFontTextStyleCaption2"},
    {&NSImageNameTouchBarAddDetailTemplate, "NSImageNameTouchBarAddDetailTemplate", "NSTouchBarAddDetailTemplate"},
    {&NSImageNameTouchBarAddTemplate, "NSImageNameTouchBarAddTemplate", "NSTouchBarAddTemplate"},
    {&NSImageNameTouchBarAlarmTemplate, "NSImageNameTouchBarAlarmTemplate", "NSTouchBarAlarmTemplate"},
    {&NSImageNameTouchBarAudioInputMuteTemplate, "NSImageNameTouchBarAudioInputMuteTemplate", "NSTouchBarAudioInputMuteTemplate"},
    {&NSImageNameTouchBarAudioInputTemplate, "NSImageNameTouchBarAudioInputTemplate", "NSTouchBarAudioInputTemplate"},
    {&NSImageNameTouchBarAudioOutputMuteTemplate, "NSImageNameTouchBarAudioOutputMuteTemplate", "NSTouchBarAudioOutputMuteTemplate"},
    {&NSImageNameTouchBarAudioOutputVolumeHighTemplate, "NSImageNameTouchBarAudioOutputVolumeHighTemplate", "NSTouchBarAudioOutputVolumeHighTemplate"},
    {&NSImageNameTouchBarAudioOutputVolumeLowTemplate, "NSImageNameTouchBarAudioOutputVolumeLowTemplate", "NSTouchBarAudioOutputVolumeLowTemplate"},
    {&NSImageNameTouchBarAudioOutputVolumeMediumTemplate, "NSImageNameTouchBarAudioOutputVolumeMediumTemplate", "NSTouchBarAudioOutputVolumeMediumTemplate"},
    {&NSImageNameTouchBarAudioOutputVolumeOffTemplate, "NSImageNameTouchBarAudioOutputVolumeOffTemplate", "NSTouchBarAudioOutputVolumeOffTemplate"},
    {&NSImageNameTouchBarBookmarksTemplate, "NSImageNameTouchBarBookmarksTemplate", "NSTouchBarBookmarksTemplate"},
    {&NSImageNameTouchBarColorPickerFill, "NSImageNameTouchBarColorPickerFill", "NSTouchBarColorPickerFill"},
    {&NSImageNameTouchBarColorPickerFont, "NSImageNameTouchBarColorPickerFont", "NSTouchBarColorPickerFont"},
    {&NSImageNameTouchBarColorPickerStroke, "NSImageNameTouchBarColorPickerStroke", "NSTouchBarColorPickerStroke"},
    {&NSImageNameTouchBarCommunicationAudioTemplate, "NSImageNameTouchBarCommunicationAudioTemplate", "NSTouchBarCommunicationAudioTemplate"},
    {&NSImageNameTouchBarCommunicationVideoTemplate, "NSImageNameTouchBarCommunicationVideoTemplate", "NSTouchBarCommunicationVideoTemplate"},
    {&NSImageNameTouchBarComposeTemplate, "NSImageNameTouchBarComposeTemplate", "NSTouchBarComposeTemplate"},
    {&NSImageNameTouchBarDownloadTemplate, "NSImageNameTouchBarDownloadTemplate", "NSTouchBarDownloadTemplate"},
    {&NSImageNameTouchBarEnterFullScreenTemplate, "NSImageNameTouchBarEnterFullScreenTemplate", "NSTouchBarEnterFullScreenTemplate"},
    {&NSImageNameTouchBarExitFullScreenTemplate, "NSImageNameTouchBarExitFullScreenTemplate", "NSTouchBarExitFullScreenTemplate"},
    {&NSImageNameTouchBarFastForwardTemplate, "NSImageNameTouchBarFastForwardTemplate", "NSTouchBarFastForwardTemplate"},
    {&NSImageNameTouchBarFolderCopyToTemplate, "NSImageNameTouchBarFolderCopyToTemplate", "NSTouchBarFolderCopyToTemplate"},
    {&NSImageNameTouchBarFolderMoveToTemplate, "NSImageNameTouchBarFolderMoveToTemplate", "NSTouchBarFolderMoveToTemplate"},
    {&NSImageNameTouchBarFolderTemplate, "NSImageNameTouchBarFolderTemplate", "NSTouchBarFolderTemplate"},
    {&NSImageNameTouchBarGetInfoTemplate, "NSImageNameTouchBarGetInfoTemplate", "NSTouchBarGetInfoTemplate"},
    {&NSImageNameTouchBarGoBackTemplate, "NSImageNameTouchBarGoBackTemplate", "NSTouchBarGoBackTemplate"},
    {&NSImageNameTouchBarGoDownTemplate, "NSImageNameTouchBarGoDownTemplate", "NSTouchBarGoDownTemplate"},
    {&NSImageNameTouchBarGoForwardTemplate, "NSImageNameTouchBarGoForwardTemplate", "NSTouchBarGoForwardTemplate"},
    {&NSImageNameTouchBarGoUpTemplate, "NSImageNameTouchBarGoUpTemplate", "NSTouchBarGoUpTemplate"},
    {&NSImageNameTouchBarHistoryTemplate, "NSImageNameTouchBarHistoryTemplate", "NSTouchBarHistoryTemplate"},
    {&NSImageNameTouchBarIconViewTemplate, "NSImageNameTouchBarIconViewTemplate", "NSTouchBarIconViewTemplate"},
    {&NSImageNameTouchBarListViewTemplate, "NSImageNameTouchBarListViewTemplate", "NSTouchBarListViewTemplate"},
    {&NSImageNameTouchBarMailTemplate, "NSImageNameTouchBarMailTemplate", "NSTouchBarMailTemplate"},
    {&NSImageNameTouchBarNewFolderTemplate, "NSImageNameTouchBarNewFolderTemplate", "NSTouchBarNewFolderTemplate"},
    {&NSImageNameTouchBarNewMessageTemplate, "NSImageNameTouchBarNewMessageTemplate", "NSTouchBarNewMessageTemplate"},
    {&NSImageNameTouchBarOpenInBrowserTemplate, "NSImageNameTouchBarOpenInBrowserTemplate", "NSTouchBarOpenInBrowserTemplate"},
    {&NSImageNameTouchBarPlayPauseTemplate, "NSImageNameTouchBarPlayPauseTemplate", "NSTouchBarPlayPauseTemplate"},
    {&NSImageNameTouchBarQuickLookTemplate, "NSImageNameTouchBarQuickLookTemplate", "NSTouchBarQuickLookTemplate"},
    {&NSImageNameTouchBarRecordStartTemplate, "NSImageNameTouchBarRecordStartTemplate", "NSTouchBarRecordStartTemplate"},
    {&NSImageNameTouchBarRefreshTemplate, "NSImageNameTouchBarRefreshTemplate", "NSTouchBarRefreshTemplate"},
    {&NSImageNameTouchBarRemoveTemplate, "NSImageNameTouchBarRemoveTemplate", "NSTouchBarRemoveTemplate"},
    {&NSImageNameTouchBarRewindTemplate, "NSImageNameTouchBarRewindTemplate", "NSTouchBarRewindTemplate"},
    {&NSImageNameTouchBarRotateLeftTemplate, "NSImageNameTouchBarRotateLeftTemplate", "NSTouchBarRotateLeftTemplate"},
    {&NSImageNameTouchBarRotateRightTemplate, "NSImageNameTouchBarRotateRightTemplate", "NSTouchBarRotateRightTemplate"},
    {&NSImageNameTouchBarSearchTemplate, "NSImageNameTouchBarSearchTemplate", "NSTouchBarSearchTemplate"},
    {&NSImageNameTouchBarShareTemplate, "NSImageNameTouchBarShareTemplate", "NSTouchBarShareTemplate"},
    {&NSImageNameTouchBarSidebarTemplate, "NSImageNameTouchBarSidebarTemplate", "NSTouchBarSidebarTemplate"},
    {&NSImageNameTouchBarSkipAhead15SecondsTemplate, "NSImageNameTouchBarSkipAhead15SecondsTemplate", "NSTouchBarSkipAhead15SecondsTemplate"},
    {&NSImageNameTouchBarSkipAhead30SecondsTemplate, "NSImageNameTouchBarSkipAhead30SecondsTemplate", "NSTouchBarSkipAhead30SecondsTemplate"},
    {&NSImageNameTouchBarSkipAheadTemplate, "NSImageNameTouchBarSkipAheadTemplate", "NSTouchBarSkipAheadTemplate"},
    {&NSImageNameTouchBarSkipBack15SecondsTemplate, "NSImageNameTouchBarSkipBack15SecondsTemplate", "NSTouchBarSkipBack15SecondsTemplate"},
    {&NSImageNameTouchBarSkipBack30SecondsTemplate, "NSImageNameTouchBarSkipBack30SecondsTemplate", "NSTouchBarSkipBack30SecondsTemplate"},
    {&NSImageNameTouchBarSkipBackTemplate, "NSImageNameTouchBarSkipBackTemplate", "NSTouchBarSkipBackTemplate"},
    {&NSImageNameTouchBarSkipToEndTemplate, "NSImageNameTouchBarSkipToEndTemplate", "NSTouchBarSkipToEndTemplate"},
    {&NSImageNameTouchBarSkipToStartTemplate, "NSImageNameTouchBarSkipToStartTemplate", "NSTouchBarSkipToStartTemplate"},
    {&NSImageNameTouchBarSlideshowTemplate, "NSImageNameTouchBarSlideshowTemplate", "NSTouchBarSlideshowTemplate"},
    {&NSImageNameTouchBarTagIconTemplate, "NSImageNameTouchBarTagIconTemplate", "NSTouchBarTagIconTemplate"},
    {&NSImageNameTouchBarTextBoldTemplate, "NSImageNameTouchBarTextBoldTemplate", "NSTouchBarTextBoldTemplate"},
    {&NSImageNameTouchBarTextBoxTemplate, "NSImageNameTouchBarTextBoxTemplate", "NSTouchBarTextBoxTemplate"},
    {&NSImageNameTouchBarTextCenterAlignTemplate, "NSImageNameTouchBarTextCenterAlignTemplate", "NSTouchBarTextCenterAlignTemplate"},
    {&NSImageNameTouchBarTextItalicTemplate, "NSImageNameTouchBarTextItalicTemplate", "NSTouchBarTextItalicTemplate"},
    {&NSImageNameTouchBarTextJustifiedAlignTemplate, "NSImageNameTouchBarTextJustifiedAlignTemplate", "NSTouchBarTextJustifiedAlignTemplate"},
    {&NSImageNameTouchBarTextLeftAlignTemplate, "NSImageNameTouchBarTextLeftAlignTemplate", "NSTouchBarTextLeftAlignTemplate"},
    {&NSImageNameTouchBarTextListTemplate, "NSImageNameTouchBarTextListTemplate", "NSTouchBarTextListTemplate"},
    {&NSImageNameTouchBarTextRightAlignTemplate, "NSImageNameTouchBarTextRightAlignTemplate", "NSTouchBarTextRightAlignTemplate"},
    {&NSImageNameTouchBarTextStrikethroughTemplate, "NSImageNameTouchBarTextStrikethroughTemplate", "NSTouchBarTextStrikethroughTemplate"},
    {&NSImageNameTouchBarTextUnderlineTemplate, "NSImageNameTouchBarTextUnderlineTemplate", "NSTouchBarTextUnderlineTemplate"},
    {&NSImageNameTouchBarUserAddTemplate, "NSImageNameTouchBarUserAddTemplate", "NSTouchBarUserAddTemplate"},
    {&NSImageNameTouchBarUserGroupTemplate, "NSImageNameTouchBarUserGroupTemplate", "NSTouchBarUserGroupTemplate"},
    {&NSImageNameTouchBarUserTemplate, "NSImageNameTouchBarUserTemplate", "NSTouchBarUserTemplate"},
    {&NSImageNameTouchBarVolumeDownTemplate, "NSImageNameTouchBarVolumeDownTemplate", "NSTouchBarVolumeDownTemplate"},
    {&NSImageNameTouchBarVolumeUpTemplate, "NSImageNameTouchBarVolumeUpTemplate", "NSTouchBarVolumeUpTemplate"},
    {&NSImageNameTouchBarPlayheadTemplate, "NSImageNameTouchBarPlayheadTemplate", "NSTouchBarPlayheadTemplate"},
    {&NSPasteboardTypeSound, "NSPasteboardTypeSound", "com.apple.cocoa.pasteboard.sound"},
    {&NSPasteboardTypeTextFinderOptions, "NSPasteboardTypeTextFinderOptions", "com.apple.cocoa.pasteboard.find-panel-search-options"},
    {&NSPasteboardTypeFindPanelSearchOptions, "NSPasteboardTypeFindPanelSearchOptions", "com.apple.cocoa.pasteboard.find-panel-search-options"},
    {&NSPopoverCloseReasonKey, "NSPopoverCloseReasonKey", "NSPopoverCloseReasonKey"},
    {&NSPrintReversePageOrder, "NSPrintReversePageOrder", "NSReversePageOrder"},
    {&NSPrintPagesAcross, "NSPrintPagesAcross", "NSPagesAcross"},
    {&NSPrintPagesDown, "NSPrintPagesDown", "NSPagesDown"},
    {&NSPrintTime, "NSPrintTime", "NSPrintTime"},
    {&NSPrintFaxNumber, "NSPrintFaxNumber", "NSFaxNumber"},
    {&NSPrintJobSavingFileNameExtensionHidden, "NSPrintJobSavingFileNameExtensionHidden", "NSJobSavingFileNameExtensionHidden"},
    {&NSPrintFormName, "NSPrintFormName", "NSFormName"},
    {&NSPrintJobFeatures, "NSPrintJobFeatures", "NSJobFeatures"},
    {&NSPrintManualFeed, "NSPrintManualFeed", "NSPrintManualFeed"},
    {&NSPrintPagesPerSheet, "NSPrintPagesPerSheet", "NSPagesPerSheet"},
    {&NSPrintPaperFeed, "NSPrintPaperFeed", "NSPaperFeed"},
    {&NSScrollViewWillStartLiveMagnifyNotification, "NSScrollViewWillStartLiveMagnifyNotification", "NSScrollViewWillStartLiveMagnifyNotification"},
    {&NSScrollViewDidEndLiveMagnifyNotification, "NSScrollViewDidEndLiveMagnifyNotification", "NSScrollViewDidEndLiveMagnifyNotification"},
    {&NSPreferredScrollerStyleDidChangeNotification, "NSPreferredScrollerStyleDidChangeNotification", "NSPreferredScrollerStyleDidChangeNotification"},
    {&NSTextMovementUserInfoKey, "NSTextMovementUserInfoKey", "NSTextMovement"},
    {&NSWindowDidChangeBackingPropertiesNotification, "NSWindowDidChangeBackingPropertiesNotification", "NSWindowDidChangeBackingPropertiesNotification"},
    {&NSBackingPropertyOldColorSpaceKey, "NSBackingPropertyOldColorSpaceKey", "NSBackingPropertyOldColorSpaceKey"},
    {&NSWorkspaceDidHideApplicationNotification, "NSWorkspaceDidHideApplicationNotification", "NSWorkspaceDidHideApplicationNotification"},
    {&NSWorkspaceDidUnhideApplicationNotification, "NSWorkspaceDidUnhideApplicationNotification", "NSWorkspaceDidUnhideApplicationNotification"},
    {&NSWorkspaceVolumeLocalizedNameKey, "NSWorkspaceVolumeLocalizedNameKey", "NSWorkspaceVolumeLocalizedNameKey"},
    {&NSWorkspaceVolumeURLKey, "NSWorkspaceVolumeURLKey", "NSWorkspaceVolumeURLKey"},
    {&NSWorkspaceVolumeOldLocalizedNameKey, "NSWorkspaceVolumeOldLocalizedNameKey", "NSWorkspaceVolumeOldLocalizedNameKey"},
    {&NSWorkspaceVolumeOldURLKey, "NSWorkspaceVolumeOldURLKey", "NSWorkspaceVolumeOldURLKey"},
    {&NSWorkspaceDidRenameVolumeNotification, "NSWorkspaceDidRenameVolumeNotification", "NSWorkspaceDidRenameVolumeNotification"},
    {&NSWorkspaceDidChangeFileLabelsNotification, "NSWorkspaceDidChangeFileLabelsNotification", "NSWorkspaceDidChangeFileLabelsNotification"},
};

int main(void)
{
    for (size_t i = 0; i < sizeof(constants) / sizeof(constants[0]); i++) {
        NSString *value = *constants[i].constant;
        if (value == nil || strcmp([value UTF8String], constants[i].value) != 0) {
            printf("FAIL %s\n", constants[i].name);
            failures++;
        }
    }
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures != 0;
}
