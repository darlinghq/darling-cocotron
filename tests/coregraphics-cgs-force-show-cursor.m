/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>

// CGSForceShowCursor() keeps the cursor visible while counted hides are pending.
// On macOS only the call itself is exercised.

@interface NSDisplay : NSObject
+ (NSDisplay *) currentDisplay;
@end

static int hides, unhides;
static void countHide(id self, SEL _cmd) { hides++; }
static void countUnhide(id self, SEL _cmd) { unhides++; }

static int failures;
#define CHECK(cond, what)                                                      \
    do {                                                                       \
        if (!(cond)) {                                                         \
            printf("FAIL: %s (hides %d, unhides %d)\n", what, hides, unhides);  \
            failures++;                                                        \
        }                                                                      \
    } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        void (*forceShow)(int) = dlsym(RTLD_DEFAULT, "CGSForceShowCursor");
        if (!forceShow) {
            printf("FAIL: CGSForceShowCursor missing\n");
            return 1;
        }

        Class displayClass = NSClassFromString(@"NSDisplay");
        if (displayClass == Nil) {
            forceShow(1);
            forceShow(1);
            printf("PASS (call only)\n");
            return 0;
        }

        Class cls = [[displayClass currentDisplay] class];
        // The X11 and Wayland connections of CoreGraphics keep the hide count themselves (the display is not asked
        // to hide anything): the visibility CGCursorIsVisible() reports is what is checked.
        if ([NSStringFromClass(cls) isEqualToString: @"WaylandDisplay"] || [NSStringFromClass(cls) hasPrefix: @"X11"]) {
            CGDisplayHideCursor(CGMainDisplayID());
            CGDisplayHideCursor(CGMainDisplayID());
            CHECK(!CGCursorIsVisible(), "two hides hide the cursor");
            forceShow(1);
            CHECK(CGCursorIsVisible(), "forcing shows the cursor");
            CGDisplayShowCursor(CGMainDisplayID());
            CHECK(CGCursorIsVisible(), "the forgotten hides leave nothing to undo");
            CGDisplayHideCursor(CGMainDisplayID());
            CHECK(!CGCursorIsVisible(), "a later hide hides again");
            CGDisplayShowCursor(CGMainDisplayID());
            CHECK(CGCursorIsVisible(), "and one show shows it");
            forceShow(1);
            CHECK(CGCursorIsVisible(), "forcing with nothing hidden changes nothing");
            printf(failures ? "FAILED\n" : "PASS\n");
            return failures ? 1 : 0;
        }
        class_replaceMethod(cls, @selector(hideCursor), (IMP) countHide, "v@:");
        class_replaceMethod(cls, @selector(unhideCursor), (IMP) countUnhide, "v@:");

        int (*mainConnection)(void) = dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
        int cid = mainConnection();
        [NSCursor hide];
        [NSCursor hide];
        CHECK(hides == 1 && unhides == 0, "hides are counted, the backend hides once");
        forceShow(cid);
        CHECK(hides == 1 && unhides == 1, "forcing shows the cursor");
        [NSCursor unhide];
        CHECK(hides == 1 && unhides == 1, "the forgotten hides leave nothing to undo");
        [NSCursor hide];
        CHECK(hides == 2 && unhides == 1, "a later hide hides again");
        [NSCursor unhide];
        CHECK(hides == 2 && unhides == 2, "and one unhide shows it");
        forceShow(cid);
        CHECK(hides == 2 && unhides == 2, "forcing with nothing hidden changes nothing");
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures ? 1 : 0;
}
