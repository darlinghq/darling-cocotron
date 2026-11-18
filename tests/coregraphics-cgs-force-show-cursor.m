/*
 * Copyright (C) 2026 Lubos Dolezel
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <stdio.h>

// CGSForceShowCursor() keeps the cursor visible while counted hides are pending.
// The window system's own calls are counted by replacing -hideCursor and -unhideCursor on the
// display class (a Darling detail), so on macOS only the call itself is exercised.

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
