/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The values of the AppKit enums and option sets that the Swift names are built on, and that the old
// spellings kept for source compatibility equal the modern ones. Values are the public ones.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static void expect(BOOL condition, const char *label)
{
    printf("%s %s\n", condition ? "PASS" : "FAIL", label);
    failures += !condition;
}

static void checkSizes(void)
{
    expect(sizeof(NSAlertStyle) == sizeof(NSUInteger), "NSAlertStyle is NSUInteger sized");
    expect(sizeof(NSButtonType) == sizeof(NSUInteger) && sizeof(NSBezelStyle) == sizeof(NSUInteger),
           "button enums are NSUInteger sized");
    expect(sizeof(NSDragOperation) == sizeof(NSUInteger), "NSDragOperation is NSUInteger sized");
    expect(sizeof(NSApplicationActivationPolicy) == sizeof(NSInteger), "NSApplicationActivationPolicy is NSInteger sized");
    expect(sizeof(NSTableViewGridLineStyle) == sizeof(NSUInteger), "NSTableViewGridLineStyle is NSUInteger sized");
}

static void checkValues(void)
{
    expect(NSEventTypeLeftMouseDown == 1 && NSEventTypeKeyDown == 10 && NSEventTypeScrollWheel == 22, "NSEventType values");
    expect(NSWindowStyleMaskTitled == 1 && NSWindowStyleMaskResizable == 8 && NSWindowStyleMaskFullSizeContentView == 0x8000,
           "NSWindowStyleMask values");
    expect(NSWindowStyleMaskUnifiedTitleAndToolbar == 0x1000, "NSWindowStyleMaskUnifiedTitleAndToolbar value");
    expect(NSAlertStyleWarning == 0 && NSAlertStyleCritical == 2, "NSAlertStyle values");
    expect(NSBezelStyleRounded == 1 && NSBezelStyleTexturedRounded == 11 && NSBezelStyleInline == 15, "NSBezelStyle values");
    expect(NSButtonTypeSwitch == 3 && NSButtonTypeRadio == 4, "NSButtonType values");
    expect(NSBitmapImageFileTypePNG == 4 && NSBitmapImageFileTypeJPEG == 3, "NSBitmapImageFileType values");
    expect(NSBitmapFormatAlphaFirst == 1 && NSBitmapFormatFloatingPointSamples == 4, "NSBitmapFormat values");
    expect(NSLineCapStyleRound == 1 && NSLineJoinStyleBevel == 2 && NSWindingRuleEvenOdd == 1, "path style values");
    expect(NSBezierPathElementMoveTo == 0 && NSBezierPathElementClosePath == 3, "NSBezierPathElement values");
    expect(NSTabViewTypeTopTabsBezelBorder == 0 && NSTabViewTypeNoTabsNoBorder == 6, "NSTabViewType values");
    expect(NSSliderTypeCircular == 1 && NSTickMarkPositionAbove == 1 && NSTickMarkPositionLeading == NSTickMarkPositionAbove &&
                   NSTickMarkPositionTrailing == NSTickMarkPositionBelow,
           "slider values");
    expect(NSColorPanelModeNone == -1 && NSColorPanelModeRGB == 1 && NSColorPanelModeCrayon == 7, "NSColorPanelMode values");
    expect(NSDatePickerModeRange == 1 && NSDatePickerStyleClockAndCalendar == 1 &&
                   NSDatePickerElementFlagYearMonthDay == 0x00e0,
           "date picker values");
    expect(NSTableViewGridNone == 0 && NSTableViewSolidVerticalGridLineMask == 1 && NSTableViewSolidHorizontalGridLineMask == 2 &&
                   NSTableViewDashedHorizontalGridLineMask == 8,
           "NSTableViewGridLineStyle values");
    expect(NSTableColumnNoResizing == 0 && NSTableColumnAutoresizingMask == 1 && NSTableColumnUserResizingMask == 2,
           "NSTableColumnResizingOptions values");
    expect(NSSelectByCharacter == 0 && NSSelectByParagraph == 2 && NSTextViewSelectionAffinityDownstream == 1,
           "text view selection values");
    expect(NSBackgroundStyleNormal == 0 && NSBackgroundStyleEmphasized == 1 && NSBackgroundStyleRaised == 2, "NSBackgroundStyle values");
    expect(NSDragOperationCopy == 1 && NSDragOperationMove == 0x10 && NSDragOperationEvery == NSUIntegerMax, "NSDragOperation values");
    expect(NSExcludeQuickDrawElementsIconCreationOption == 2 && NSExclude10_4ElementsIconCreationOption == 4,
           "NSWorkspaceIconCreationOptions values");
    expect(NSOpenGLContextParameterSwapInterval == 222 && NSOpenGLContextParameterStateValidation == 301,
           "NSOpenGLContextParameter values");
}

static void checkOldNames(void)
{
    expect(NSLeftMouseDown == NSEventTypeLeftMouseDown && NSScrollWheel == NSEventTypeScrollWheel &&
                   NSOtherMouseDragged == NSEventTypeOtherMouseDragged,
           "old NSEventType names");
    expect(NSWarningAlertStyle == NSAlertStyleWarning && NSCriticalAlertStyle == NSAlertStyleCritical, "old NSAlertStyle names");
    expect(NSRoundedBezelStyle == NSBezelStyleRounded && NSInlineBezelStyle == NSBezelStyleInline, "old NSBezelStyle names");
    expect(NSMomentaryLightButton == NSButtonTypeMomentaryLight && NSSwitchButton == NSButtonTypeSwitch &&
                   NSRadioButton == NSButtonTypeRadio,
           "old NSButtonType names");
    expect(NSTIFFFileType == NSBitmapImageFileTypeTIFF && NSPNGFileType == NSBitmapImageFileTypePNG, "old file type names");
    expect(NSButtLineCapStyle == NSLineCapStyleButt && NSBevelLineJoinStyle == NSLineJoinStyleBevel &&
                   NSEvenOddWindingRule == NSWindingRuleEvenOdd,
           "old path style names");
    expect(NSMoveToBezierPathElement == NSBezierPathElementMoveTo && NSCurveToBezierPathElement == NSBezierPathElementCurveTo,
           "old path element names");
    expect(NSTopTabsBezelBorder == NSTabViewTypeTopTabsBezelBorder && NSNoTabsNoBorder == NSTabViewTypeNoTabsNoBorder,
           "old NSTabViewType names");
    expect(NSLinearSlider == NSSliderTypeLinear && NSTickMarkBelow == NSTickMarkPositionBelow && NSTickMarkLeft == NSTickMarkAbove,
           "old slider names");
    expect(NSRGBModeColorPanel == NSColorPanelModeRGB && NSNoModeColorPanel == NSColorPanelModeNone, "old NSColorPanelMode names");
    expect(NSSingleDateMode == NSDatePickerModeSingle && NSClockAndCalendarDatePickerStyle == NSDatePickerStyleClockAndCalendar &&
                   NSEraDatePickerElementFlag == NSDatePickerElementFlagEra,
           "old date picker names");
    expect(NSOpenGLCPSwapInterval == NSOpenGLContextParameterSwapInterval, "old NSOpenGLContextParameter names");
    expect(NSBackgroundStyleLight == NSBackgroundStyleNormal && NSBackgroundStyleDark == NSBackgroundStyleEmphasized,
           "old NSBackgroundStyle names");
    expect(NSSelectionAffinityUpstream == NSTextViewSelectionAffinityUpstream, "old selection affinity names");
    expect(NSScaleProportionally == NSImageScaleProportionallyDown && NSScaleNone == NSImageScaleNone, "old NSImageScaling names");
    expect(NSDefaultTokenStyle == NSTokenStyleDefault && NSPlainTextTokenStyle == NSTokenStylePlainSquared,
           "old NSTokenStyle names");
    expect(NSRatingLevelIndicatorStyle == NSLevelIndicatorStyleRating, "old level indicator names");
    expect(NSLevelIndicatorStyleRelevancy == 0 && NSLevelIndicatorStyleContinuousCapacity == 1 &&
                   NSLevelIndicatorStyleDiscreteCapacity == 2 && NSLevelIndicatorStyleRating == 3,
           "NSLevelIndicatorStyle values");
}

int main(void)
{
    checkSizes();
    checkValues();
    checkOldNames();
    printf(failures ? "FAILED\n" : "ALL PASSED\n");
    return failures != 0;
}
