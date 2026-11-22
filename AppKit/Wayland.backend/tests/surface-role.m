// A window that is shown as a toplevel at one time and as a popup at another (a pop-up window
// is a popup of the window it belongs to when there is one on screen, an ordinary window when
// there is none) must get a new wl_surface for the second role: the core protocol makes the
// role of a wl_surface permanent for its lifetime. Needs DARLING_APPKIT_BACKEND=wayland and a
// compositor; run it with WAYLAND_DEBUG=client and give the log (stderr) to surface-role-check.py,
// which checks on the wire that no wl_surface got two roles. Prints CHECK PASS/FAIL lines and RESULT.
//
//   1. the pop-up window is ordered in while no other window is on screen: a toplevel
//   2. it is ordered out, a titled window is shown, the pop-up window is ordered in again: a popup of it
//   3. both go away and the pop-up window is ordered in once more: a toplevel again
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSWindow (SurfaceRoleFixture)
- (id) platformWindow;
@end
@interface NSObject (SurfaceRolePlatformFixture)
- (BOOL) isMapped;
- (BOOL) isPopup;
- (id) popupParent;
@end

static unsigned checks, failures;
static void expect(BOOL ok, const char *label) {
    ++checks;
    if (!ok) ++failures;
    printf("CHECK %s %s\n", ok ? "PASS" : "FAIL", label);
    fflush(stdout);
}

@interface Driver : NSObject {
@public
    NSWindow *main, *popup;
}
- (void) step: (NSTimer *) timer;
@end

@implementation Driver
- (void) step: (NSTimer *) timer {
    static int stage;
    static NSTimeInterval since;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    id popupPlatform = [popup platformWindow];
    id mainPlatform = [main platformWindow];
    if (!since) since = now;
    BOOL timedOut = now - since > 15;
    switch (stage) {
    case 0:
        [popup orderFront: nil];
        stage = 1; since = 0;
        break;
    case 1:
        if (![popupPlatform isMapped] && !timedOut) return;
        expect([popupPlatform isMapped] && ![popupPlatform isPopup], "alone on screen: a toplevel");
        [popup orderOut: nil];
        [main makeKeyAndOrderFront: nil];
        stage = 2; since = 0;
        break;
    case 2:
        if (![mainPlatform isMapped] && !timedOut) return;
        expect([mainPlatform isMapped], "the titled window is shown");
        [popup orderFront: nil];
        stage = 3; since = 0;
        break;
    case 3:
        if (![popupPlatform isMapped] && !timedOut) return;
        expect([popupPlatform isMapped] && [popupPlatform isPopup] && [popupPlatform popupParent] == mainPlatform,
               "over the titled window: a popup of it");
        [popup orderOut: nil];
        [main orderOut: nil];
        stage = 4; since = 0;
        break;
    case 4:
        if (now - since < 1) return;
        // An application that is not active does not map a plain window on Wayland (it would take the
        // focus from the application that has it), and nothing of this one is on screen any more.
        [NSApp activateIgnoringOtherApps: YES];
        [popup orderFront: nil];
        stage = 5; since = 0;
        break;
    case 5:
        if (![popupPlatform isMapped] && !timedOut) return;
        expect([popupPlatform isMapped] && ![popupPlatform isPopup], "alone again: a toplevel");
        // Still dispatching: a strict compositor would have ended the connection with a protocol error.
        stage = 6; since = 0;
        break;
    default:
        printf("RESULT checks=%u failures=%u\n", checks, failures);
        fflush(stdout);
        exit(failures ? 1 : 0);
    }
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Driver *driver = [Driver new];
        driver->main = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 300, 300)
                                                   styleMask: NSTitledWindowMask
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
        [driver->main setReleasedWhenClosed: NO];
        [driver->main setTitle: @"Surface role fixture"];
        // Borderless, cannot be main, ignores the mouse: a pop-up window (DarlingWindowPresentation.h).
        driver->popup = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 120, 60)
                                                    styleMask: NSBorderlessWindowMask
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO];
        [driver->popup setReleasedWhenClosed: NO];
        [driver->popup setIgnoresMouseEvents: YES];
        [NSTimer scheduledTimerWithTimeInterval: .1 target: driver selector: @selector(step:)
                                       userInfo: nil repeats: YES];
        puts("READY");
        fflush(stdout);
        [NSApp run];
    }
}
