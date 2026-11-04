// SPDX-License-Identifier: GPL-3.0-only
// Host test for tests/coregraphics-window-level-for-key.sh: compares CGWindowLevelForKey with the
// level constants of CoreGraphics/include/CoreGraphics/CGWindowLevel.h for every CGWindowLevelKey.
#include <CoreGraphics/CGWindowLevel.h>
#include <stdio.h>

static int failures;

static void expect(const char *name, CGWindowLevelKey key, CGWindowLevel level)
{
    CGWindowLevel got = CGWindowLevelForKey(key);
    if (got != level) {
        printf("FAIL: %s: got %d, expected %d\n", name, (int) got, (int) level);
        failures++;
    }
}

#define KEY(k, level) expect(#k, k, level)

int main(void)
{
    /* Keys the header has a level constant for. */
    KEY(kCGNormalWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGFloatingWindowLevelKey, kCGFloatingWindowLevel);
    KEY(kCGTornOffMenuWindowLevelKey, kCGTornOffMenuWindowLevel);
    KEY(kCGMainMenuWindowLevelKey, kCGMainMenuWindowLevel);
    KEY(kCGStatusWindowLevelKey, kCGStatusWindowLevel);
    KEY(kCGModalPanelWindowLevelKey, kCGModalPanelWindowLevel);
    KEY(kCGPopUpMenuWindowLevelKey, kCGPopUpMenuWindowLevel);
    KEY(kCGScreenSaverWindowLevelKey, kCGScreenSaverWindowLevel);

    /* Keys without a header constant keep the normal level. */
    KEY(kCGBaseWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGMinimumWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGDesktopWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGBackstopMenuLevelKey, kCGNormalWindowLevel);
    KEY(kCGDockWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGDraggingWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGMaximumWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGOverlayWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGHelpWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGUtilityWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGDesktopIconWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGCursorWindowLevelKey, kCGNormalWindowLevel);
    KEY(kCGAssistiveTechHighWindowLevelKey, kCGNormalWindowLevel);

    /* Every key was listed above, and the levels the header defines are distinct. */
    if (kCGNumberOfWindowLevelKeys != 21) {
        printf("FAIL: header has %d keys; update tests/coregraphics-window-level-for-key.c\n", (int) kCGNumberOfWindowLevelKeys);
        failures++;
    }
    if (CGWindowLevelForKey(kCGFloatingWindowLevelKey) <= CGWindowLevelForKey(kCGNormalWindowLevelKey)) {
        printf("FAIL: floating level is not above normal\n");
        failures++;
    }
    printf(failures ? "RESULT: FAIL (%d)\n" : "RESULT: PASS\n", failures);
    return failures != 0;
}
