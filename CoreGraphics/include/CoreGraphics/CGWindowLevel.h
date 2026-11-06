#ifndef CGWINDOWLEVEL_H
#define CGWINDOWLEVEL_H

#import <CoreFoundation/CoreFoundation.h>

typedef int32_t CGWindowLevel;

// The level values the public CGWindowLevel.h documents for each key.
// macOS SDK headers define these names as CGWindowLevelForKey() calls; they
// are plain constants here so that AppKit can use them in enums, and
// CGWindowLevelForKey() returns the same values.
#define kCGNumReservedWindowLevels (16)
#define kCGNumReservedBaseWindowLevels (5)

#define kCGBaseWindowLevel INT32_MIN
#define kCGMinimumWindowLevel (kCGBaseWindowLevel + kCGNumReservedBaseWindowLevels)
#define kCGMaximumWindowLevel (INT32_MAX - kCGNumReservedWindowLevels)

#define kCGDesktopWindowLevel (kCGMinimumWindowLevel + 20)
#define kCGDesktopIconWindowLevel (kCGDesktopWindowLevel + 20)
#define kCGBackstopMenuLevel (-20)
#define kCGNormalWindowLevel (0)
#define kCGFloatingWindowLevel (3)
#define kCGTornOffMenuWindowLevel (3)
#define kCGModalPanelWindowLevel (8)
#define kCGUtilityWindowLevel (19)
#define kCGDockWindowLevel (20)
#define kCGMainMenuWindowLevel (24)
#define kCGStatusWindowLevel (25)
#define kCGPopUpMenuWindowLevel (101)
#define kCGOverlayWindowLevel (102)
#define kCGHelpWindowLevel (200)
#define kCGDraggingWindowLevel (500)
#define kCGScreenSaverWindowLevel (1000)
#define kCGAssistiveTechHighWindowLevel (1500)
#define kCGCursorWindowLevel (kCGMaximumWindowLevel - 1)

typedef CF_ENUM(int32_t, CGWindowLevelKey)
{
    kCGBaseWindowLevelKey,
    kCGMinimumWindowLevelKey,
    kCGDesktopWindowLevelKey,
    kCGBackstopMenuLevelKey,
    kCGNormalWindowLevelKey,
    kCGFloatingWindowLevelKey,
    kCGTornOffMenuWindowLevelKey,
    kCGDockWindowLevelKey,
    kCGMainMenuWindowLevelKey,
    kCGStatusWindowLevelKey,
    kCGModalPanelWindowLevelKey,
    kCGPopUpMenuWindowLevelKey,
    kCGDraggingWindowLevelKey,
    kCGScreenSaverWindowLevelKey,
    kCGMaximumWindowLevelKey,
    kCGOverlayWindowLevelKey,
    kCGHelpWindowLevelKey,
    kCGUtilityWindowLevelKey,
    kCGDesktopIconWindowLevelKey,
    kCGCursorWindowLevelKey,
    kCGAssistiveTechHighWindowLevelKey,
    kCGNumberOfWindowLevelKeys
};

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CGWindowLevel CGWindowLevelForKey(CGWindowLevelKey key);

CF_IMPLICIT_BRIDGING_DISABLED

#endif
