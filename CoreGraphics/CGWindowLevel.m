#import <CoreGraphics/CGWindowLevel.h>

// Maps each key to the level the header defines for it. Keys outside the
// enumeration get the normal level.
CGWindowLevel CGWindowLevelForKey(CGWindowLevelKey key)
{
    switch (key) {
    case kCGBaseWindowLevelKey:
        return kCGBaseWindowLevel;
    case kCGMinimumWindowLevelKey:
        return kCGMinimumWindowLevel;
    case kCGDesktopWindowLevelKey:
        return kCGDesktopWindowLevel;
    case kCGBackstopMenuLevelKey:
        return kCGBackstopMenuLevel;
    case kCGNormalWindowLevelKey:
        return kCGNormalWindowLevel;
    case kCGFloatingWindowLevelKey:
        return kCGFloatingWindowLevel;
    case kCGTornOffMenuWindowLevelKey:
        return kCGTornOffMenuWindowLevel;
    case kCGDockWindowLevelKey:
        return kCGDockWindowLevel;
    case kCGMainMenuWindowLevelKey:
        return kCGMainMenuWindowLevel;
    case kCGStatusWindowLevelKey:
        return kCGStatusWindowLevel;
    case kCGModalPanelWindowLevelKey:
        return kCGModalPanelWindowLevel;
    case kCGPopUpMenuWindowLevelKey:
        return kCGPopUpMenuWindowLevel;
    case kCGDraggingWindowLevelKey:
        return kCGDraggingWindowLevel;
    case kCGScreenSaverWindowLevelKey:
        return kCGScreenSaverWindowLevel;
    case kCGMaximumWindowLevelKey:
        return kCGMaximumWindowLevel;
    case kCGOverlayWindowLevelKey:
        return kCGOverlayWindowLevel;
    case kCGHelpWindowLevelKey:
        return kCGHelpWindowLevel;
    case kCGUtilityWindowLevelKey:
        return kCGUtilityWindowLevel;
    case kCGDesktopIconWindowLevelKey:
        return kCGDesktopIconWindowLevel;
    case kCGCursorWindowLevelKey:
        return kCGCursorWindowLevel;
    case kCGAssistiveTechHighWindowLevelKey:
        return kCGAssistiveTechHighWindowLevel;
    default:
        return kCGNormalWindowLevel;
    }
}
