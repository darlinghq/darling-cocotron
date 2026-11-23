/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: +[NSMenu menuBarVisible] and +[NSMenu setMenuBarVisible:] exist.
// The visibility is carried by the application's presentation options: NO
// replaces them with a hidden Dock and menu bar, YES replaces them with the
// default options, and the getter is NO while the options hide or auto-hide
// the menu bar. Same results on macOS 10.14.4 and 26.7.3 (black box).
// Prints PASS or FAIL. Needs no window server connection beyond NSApplication.
#import <AppKit/AppKit.h>
#include <stdio.h>

// Declared in the SDK headers on macOS; declared here so that the test also
// compiles where the header lacks them.
@interface NSMenu (VisibleTest)
+ (BOOL) menuBarVisible;
+ (void) setMenuBarVisible: (BOOL) visible;
@end

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        const NSApplicationPresentationOptions hidden =
                NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;

        CHECK([NSMenu respondsToSelector: @selector(menuBarVisible)], "no +menuBarVisible");
        CHECK([NSMenu respondsToSelector: @selector(setMenuBarVisible:)], "no +setMenuBarVisible:");
        CHECK([NSMenu menuBarVisible], "visible by default");

        [NSMenu setMenuBarVisible: NO];
        CHECK(![NSMenu menuBarVisible], "set NO: still visible");
        CHECK([app presentationOptions] == hidden, "set NO: options %lu", (unsigned long) [app presentationOptions]);

        [NSMenu setMenuBarVisible: NO];
        CHECK(![NSMenu menuBarVisible], "set NO twice");

        [NSMenu setMenuBarVisible: YES];
        CHECK([NSMenu menuBarVisible], "set YES: not visible");
        CHECK([app presentationOptions] == NSApplicationPresentationDefault, "set YES: options %lu",
              (unsigned long) [app presentationOptions]);

        // The other options are replaced, not kept.
        [app setPresentationOptions: NSApplicationPresentationAutoHideDock];
        CHECK([NSMenu menuBarVisible], "auto-hide Dock keeps the bar");
        [NSMenu setMenuBarVisible: NO];
        CHECK([app presentationOptions] == hidden, "NO over auto-hide Dock: options %lu",
              (unsigned long) [app presentationOptions]);
        [NSMenu setMenuBarVisible: YES];
        CHECK([app presentationOptions] == NSApplicationPresentationDefault, "YES over hidden: options %lu",
              (unsigned long) [app presentationOptions]);

        // Options set by the application are read back by the getter.
        [app setPresentationOptions: hidden];
        CHECK(![NSMenu menuBarVisible], "options hide the bar: visible");
        [app setPresentationOptions: NSApplicationPresentationAutoHideDock | NSApplicationPresentationAutoHideMenuBar];
        CHECK(![NSMenu menuBarVisible], "options auto-hide the bar: visible");
        [app setPresentationOptions: NSApplicationPresentationDefault];
        CHECK([NSMenu menuBarVisible], "default options: not visible");
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
