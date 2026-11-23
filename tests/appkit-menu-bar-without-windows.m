/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: with no desktop global menu, the application's main menu is shown
// in a menu bar window for as long as the application is active, whether or
// not it has any window; the bar goes away when the application hides the menu
// bar (NSApplicationPresentationHideMenuBar).
// Usage: appkit-menu-bar-without-windows x11|wayland. The backend actually in
// use is checked against the argument; a mismatch prints SKIP.
// Prints PASS, FAIL or SKIP. Needs a window server (Xvfb, or a Wayland
// compositor; a compositor with wlr-layer-shell gets the bar as a layer surface).
#import <AppKit/AppKit.h>
#import "test-argument-words.h"
#include <stdio.h>
#include <string.h>

@interface NSWindow (BackendCallbacks)
- (void) platformWindowActivated: (id) window displayIfNeeded: (BOOL) displayIfNeeded;
- (void) platformWindowDeactivated: (id) window checkForAppDeactivation: (BOOL) check;
@end

@interface NSObject (CurrentDisplay)
+ (id) currentDisplay;
@end

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

// The bar is a window of AppKit's own: -windows does not list it, and it has
// no window number until something asks for one. The display's menu object
// holds it (private, so reached by key).
static NSWindow *findBar(void) {
    id display = [NSClassFromString(@"NSDisplay") currentDisplay];
    id controller = [[display valueForKey: @"_appMenu"] valueForKey: @"_bar"];
    return [controller valueForKey: @"_bar"];
}

static BOOL barShown(void) {
    NSWindow *bar = findBar();
    return bar != nil && [bar isVisible];
}

// The program's own arguments (a mode, a number) are not documents. As on macOS, a word in the process arguments is
// offered to the application's delegate, and one that nobody takes is reported to the user by the document
// controller with an alert that would stop the program; a delegate that takes -application:openFiles: ends it.
@interface ArgumentSink : NSObject <NSApplicationDelegate>
@end
@implementation ArgumentSink
- (void) application: (NSApplication *) application openFiles: (NSArray *) files {
}
@end

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setDelegate: [[ArgumentSink alloc] init]];

        NSString *backend = NSStringFromClass([[NSClassFromString(@"NSDisplay") currentDisplay] class]);
        const char *expected = argc > 1 ? argv[1] : "x11";
        BOOL isWayland = [backend hasPrefix: @"Wayland"];
        if (isWayland != (strcmp(expected, "wayland") == 0)) {
            printf("SKIP: backend is %s, wanted %s\n", [backend UTF8String], expected);
            return 0;
        }

        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        NSMenuItem *top = [main addItemWithTitle: @"Test" action: nil keyEquivalent: @""];
        NSMenu *sub = [[NSMenu alloc] initWithTitle: @"Test"];
        [sub addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @""];
        [top setSubmenu: sub];
        [NSApp setMainMenu: main];
        TestIgnoreArgumentWords();
        [NSApp finishLaunching];
        spin(1.0);

        // 1. No window at all.
        CHECK(barShown(), "no menu bar with no window open");

        // 2. The last window goes away.
        NSWindow *a = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 200, 100)
                                                  styleMask: NSWindowStyleMaskTitled
                                                    backing: NSBackingStoreBuffered
                                                      defer: NO];
        [a setReleasedWhenClosed: NO];
        [a orderFront: nil];
        [a platformWindowActivated: nil displayIfNeeded: NO];
        spin(0.5);
        CHECK(barShown(), "no menu bar with a window open");
        [a close];
        [a platformWindowDeactivated: nil checkForAppDeactivation: NO];
        spin(1.0);
        CHECK([NSApp isActive], "application not active after its last window closed");
        CHECK(barShown(), "menu bar gone after the last window closed");

        // 3. Hiding the menu bar.
        [NSApp setPresentationOptions: NSApplicationPresentationHideMenuBar | NSApplicationPresentationHideDock];
        spin(1.0);
        CHECK(!barShown(), "menu bar shown with NSApplicationPresentationHideMenuBar");
        [NSApp setPresentationOptions: NSApplicationPresentationDefault];
        spin(1.0);
        CHECK(barShown(), "menu bar not back after the presentation options were reset");

    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
