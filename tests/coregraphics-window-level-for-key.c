// SPDX-License-Identifier: GPL-3.0-only
// Host test for tests/coregraphics-window-level-for-key.sh: compares CGWindowLevelForKey with the
// level values the macOS CGWindowLevel.h documents for every CGWindowLevelKey.
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
    /* The levels the public macOS CGWindowLevel.h documents for each key. */
    KEY(kCGBaseWindowLevelKey, INT32_MIN);
    KEY(kCGMinimumWindowLevelKey, INT32_MIN + 5);
    KEY(kCGDesktopWindowLevelKey, INT32_MIN + 25);
    KEY(kCGBackstopMenuLevelKey, -20);
    KEY(kCGNormalWindowLevelKey, 0);
    KEY(kCGFloatingWindowLevelKey, 3);
    KEY(kCGTornOffMenuWindowLevelKey, 3);
    KEY(kCGDockWindowLevelKey, 20);
    KEY(kCGMainMenuWindowLevelKey, 24);
    KEY(kCGStatusWindowLevelKey, 25);
    KEY(kCGModalPanelWindowLevelKey, 8);
    KEY(kCGPopUpMenuWindowLevelKey, 101);
    KEY(kCGDraggingWindowLevelKey, 500);
    KEY(kCGScreenSaverWindowLevelKey, 1000);
    KEY(kCGMaximumWindowLevelKey, INT32_MAX - 16);
    KEY(kCGOverlayWindowLevelKey, 102);
    KEY(kCGHelpWindowLevelKey, 200);
    KEY(kCGUtilityWindowLevelKey, 19);
    KEY(kCGDesktopIconWindowLevelKey, INT32_MIN + 45);
    KEY(kCGCursorWindowLevelKey, INT32_MAX - 17);
    KEY(kCGAssistiveTechHighWindowLevelKey, 1500);

    /* The header constants AppKit builds its window levels from agree. */
    KEY(kCGFloatingWindowLevelKey, kCGFloatingWindowLevel);
    KEY(kCGModalPanelWindowLevelKey, kCGModalPanelWindowLevel);

    /* Every key was listed above. */
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
