/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: with no desktop global menu, the application's main menu is shown
// in a menu bar window for as long as the application is active, whether or
// not it has any window; the bar goes away when the application hides the menu
// bar (NSApplicationPresentationHideMenuBar); and choosing Quit in the bar ends
// up in -terminate:.
// Usage: appkit-menu-bar-without-windows x11|wayland. The backend actually in
// use is checked against the argument; a mismatch prints SKIP.
// Prints PASS, FAIL or SKIP. Needs a window server (Xvfb, or a Wayland
// compositor; a compositor with wlr-layer-shell gets the bar as a layer surface).
#import <AppKit/AppKit.h>
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
static BOOL terminateAsked;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface Delegate : NSObject <NSApplicationDelegate>
@end
@implementation Delegate
- (NSApplicationTerminateReply) applicationShouldTerminate: (NSApplication *) sender {
    terminateAsked = YES;
    return NSTerminateCancel;
}
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSWindow *findBar(void) {
    Class barClass = NSClassFromString(@"NSMenuBarWindow");
    if (barClass == Nil)
        barClass = NSClassFromString(@"X11MenuBarWindow");
    for (NSWindow *window in [NSApp windows])
        if (barClass != Nil && [window isKindOfClass: barClass])
            return window;
    return nil;
}

static BOOL barShown(void) {
    NSWindow *bar = findBar();
    return bar != nil && [bar isVisible];
}

static NSWindow *findMenuWindow(void) {
    for (NSWindow *window in [NSApp windows])
        if ([window isKindOfClass: NSClassFromString(@"NSMenuWindow")] && [window isVisible])
            return window;
    return nil;
}

static NSEvent *mouseEvent(NSEventType type, NSWindow *window, NSPoint point) {
    return [NSEvent mouseEventWithType: type
                              location: point
                         modifierFlags: 0
                             timestamp: [[NSProcessInfo processInfo] systemUptime]
                          windowNumber: [window windowNumber]
                               context: nil
                             eventNumber: 0
                            clickCount: 1
                              pressure: 1];
}

// Runs inside the tracking loop that the click in the bar started: moves to
// the first item of the menu that opened and releases the button there.
@interface Clicker : NSObject
- (void) chooseFirstItem: (NSTimer *) timer;
@end
@implementation Clicker
- (void) chooseFirstItem: (NSTimer *) timer {
    NSWindow *menuWindow = findMenuWindow();
    if (menuWindow == nil)
        return;
    [timer invalidate];
    NSPoint point = NSMakePoint(20, NSHeight([menuWindow frame]) - 12);
    [NSApp postEvent: mouseEvent(NSLeftMouseDragged, menuWindow, point) atStart: NO];
    [NSApp postEvent: mouseEvent(NSLeftMouseUp, menuWindow, point) atStart: NO];
}
@end

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        [NSApplication sharedApplication];
        Delegate *delegate = [Delegate new];
        [NSApp setDelegate: delegate];

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
        [NSApp setPresentationOptions: NSApplicationPresentationHideMenuBar];
        spin(1.0);
        CHECK(!barShown(), "menu bar shown with NSApplicationPresentationHideMenuBar");
        [NSApp setPresentationOptions: NSApplicationPresentationDefault];
        spin(1.0);
        CHECK(barShown(), "menu bar not back after the presentation options were reset");

        // 4. Quit chosen in the bar.
        NSWindow *bar = findBar();
        if (bar != nil) {
            Clicker *clicker = [Clicker new];
            NSTimer *timer = [NSTimer timerWithTimeInterval: 0.3
                                                     target: clicker
                                                   selector: @selector(chooseFirstItem:)
                                                   userInfo: nil
                                                    repeats: YES];
            // The tracking loop that the click starts runs in the event tracking mode.
            [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
            // The first title sits at the left end of the bar; the click returns
            // when the menu tracking is over.
            [NSApp sendEvent: mouseEvent(NSLeftMouseDown, bar, NSMakePoint(15, NSHeight([bar frame]) / 2))];
            [timer invalidate];
            spin(0.5);
            CHECK(terminateAsked, "Quit chosen in the bar did not reach -terminate:");
        }
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
