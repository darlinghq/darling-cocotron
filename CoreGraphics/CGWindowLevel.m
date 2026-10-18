#import <CoreGraphics/CGWindowLevel.h>

// Maps each key to the level constant this header defines for it. The header has no level for the
// remaining keys (desktop, dock, dragging, overlay, ...), so they keep the normal level.
CGWindowLevel CGWindowLevelForKey(CGWindowLevelKey key)
{
    switch (key) {
    case kCGNormalWindowLevelKey:
        return kCGNormalWindowLevel;
    case kCGFloatingWindowLevelKey:
        return kCGFloatingWindowLevel;
    case kCGTornOffMenuWindowLevelKey:
        return kCGTornOffMenuWindowLevel;
    case kCGMainMenuWindowLevelKey:
        return kCGMainMenuWindowLevel;
    case kCGStatusWindowLevelKey:
        return kCGStatusWindowLevel;
    case kCGModalPanelWindowLevelKey:
        return kCGModalPanelWindowLevel;
    case kCGPopUpMenuWindowLevelKey:
        return kCGPopUpMenuWindowLevel;
    case kCGScreenSaverWindowLevelKey:
        return kCGScreenSaverWindowLevel;
    default:
        return kCGNormalWindowLevel;
    }
}
