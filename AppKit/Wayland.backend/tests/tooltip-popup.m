// Tool tips on the Wayland backend: an ungrabbed xdg_popup of the window under the pointer,
// next to the pointer. A toplevel cannot be positioned by a client, so the compositor would
// centre it on screen. Needs DARLING_APPKIT_BACKEND=wayland and a compositor with two windows
// side by side; a runner moves the pointer and clicks (see tooltip-popup-check.py for the wire
// checks of the same run). Prints CHECK PASS/FAIL lines and RESULT.
//
//   1. no window yet: the tool tip stays unmapped (a toplevel would be centred)
//   2. the runner clicks in window A; the tool tip is ordered front from inside that press
//   3. the pointer moves to window B (no click); the tool tip belongs to B, not to the clicked A
//   4. repeated show and hide
//   5. the parent window closes while the tool tip is shown
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#import <objc/runtime.h>

@interface NSWindow (TooltipPopupFixture)
- (id) platformWindow;
@end
@interface NSObject (TooltipWindowFixture)
+ (id) sharedToolTipWindow;
- (void) setToolTip: (NSString *) toolTip;
@end
@interface NSObject (TooltipPopupFixture)
- (BOOL) isMapped;
- (BOOL) isPopup;
- (BOOL) isTooltip;
- (id) popupParent;
- (uint32_t) popupGrabSerial;
@end
@interface NSObject (TooltipDisplayFixture)
+ (id) currentDisplay;
@end

static unsigned checks, failures;
static void expect(BOOL ok, const char *label) {
    ++checks;
    if (!ok) ++failures;
    printf("CHECK %s %s\n", ok ? "PASS" : "FAIL", label);
    fflush(stdout);
}
static id displayIvar(const char *name) {
    id display = [NSClassFromString(@"NSDisplay") currentDisplay];
    Ivar ivar = class_getInstanceVariable(object_getClass(display), name);
    return ivar ? object_getIvar(display, ivar) : nil;
}
static id gDriver;
@interface ClickView : NSView
@end

@interface Driver : NSObject {
@public
    NSWindow *a, *b, *tip;
    BOOL clicked;
}
- (void) step: (NSTimer *) timer;
@end

@implementation ClickView
// Scenario 2: ordered front from inside the press, so a popup that asked for a grab would hold
// a valid serial.
- (void) mouseDown: (NSEvent *) event {
    Driver *d = gDriver;
    if ([self window] != d->a || d->clicked) return;
    d->clicked = YES;
    [d->tip orderFrontRegardless];
}
@end

@implementation Driver
- (void) checkShownOver: (NSWindow *) parent label: (const char *) label {
    id tipPlatform = [tip platformWindow];
    char text[160];
    snprintf(text, sizeof text, "%s: tool tip is a mapped popup", label);
    expect([tipPlatform isMapped] && [tipPlatform isPopup] && [tipPlatform isTooltip], text);
    snprintf(text, sizeof text, "%s: its parent is the window under the pointer", label);
    expect([tipPlatform popupParent] == [parent platformWindow], text);
    snprintf(text, sizeof text, "%s: no grab serial", label);
    expect([tipPlatform popupGrabSerial] == 0, text);
}

- (void) step: (NSTimer *) timer {
    static int stage;
    static NSTimeInterval until, since;
    static int cycle;
    static BOOL checkedA;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < until) return;
    id tipPlatform = [tip platformWindow];
    switch (stage) {
    case 0:
        [tip orderFrontRegardless];
        expect(![tipPlatform isMapped], "no parent window: the tool tip stays unmapped");
        [tip orderOut: nil];
        [a makeKeyAndOrderFront: nil];
        [b orderFront: nil];
        stage = 1; until = now + 1;
        break;
    case 1:  // wait for the runner: windows up, click in A
        if (!clicked) {
            if (!since) since = now;
            if (now - since > 60) { expect(NO, "the runner clicked in window A"); stage = 99; }
            return;
        }
        since = 0;
        stage = 2; until = now + 1.5;
        break;
    case 2:
        if (!checkedA) { checkedA = YES; [self checkShownOver: a label: "ordered front in a click in A"]; }
        // Held for a screenshot while this file exists.
        if (getenv("TOOLTIP_HOLD_FILE") && access(getenv("TOOLTIP_HOLD_FILE"), F_OK) == 0) return;
        [tip orderOut: nil];
        printf("SC2-DONE\n"); fflush(stdout);
        stage = 3; until = now + 0.5;
        break;
    case 3:  // the runner moves the pointer into B without a click
        if (displayIvar("_pointerWindow") != [b platformWindow]) {
            if (!since) since = now;
            if (now - since > 60) { expect(NO, "the pointer moved into window B"); stage = 99; }
            return;
        }
        [tip orderFrontRegardless];
        stage = 4; until = now + 1.5;
        break;
    case 4:
        [self checkShownOver: b label: "pointer in B after a click in A"];
        [tip orderOut: nil];
        stage = 5; until = now + 0.5;
        break;
    case 5:
        [tip orderFrontRegardless];
        stage = 6; until = now + 0.7;
        break;
    case 6:
        expect([tipPlatform isMapped] && [tipPlatform isPopup], "repeated show: mapped as a popup");
        [tip orderOut: nil];
        stage = 7; until = now + 0.7;
        break;
    case 7:
        expect(![tipPlatform isMapped], "repeated hide: unmapped");
        stage = ++cycle < 3 ? 5 : 8;
        break;
    case 8:
        [tip orderFrontRegardless];
        stage = 9; until = now + 1;
        break;
    case 9:
        [self checkShownOver: b label: "after repeated show and hide"];
        [b close];  // the parent closes while the tool tip is shown
        stage = 13; until = now + 1;
        break;
    case 13:
        expect(![tipPlatform isMapped], "the tool tip is gone with its parent");
        // Still dispatching: a protocol error would have ended the process.
        stage = 14; until = now + 0.5;
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
        gDriver = driver;
        NSWindow *w[2];
        for (int i = 0; i < 2; i++) {
            w[i] = [[NSWindow alloc] initWithContentRect: NSMakeRect(100 + 320 * i, 100, 300, 350)
                                               styleMask: NSTitledWindowMask
                                                 backing: NSBackingStoreBuffered
                                                   defer: NO];
            [w[i] setReleasedWhenClosed: NO];
            [w[i] setContentView: [[[ClickView alloc] initWithFrame: NSMakeRect(0, 0, 300, 350)] autorelease]];
            [w[i] setTitle: i ? @"Tool tip popup fixture B" : @"Tool tip popup fixture A"];
        }
        driver->a = w[0];
        driver->b = w[1];
        driver->tip = [NSClassFromString(@"NSToolTipWindow") sharedToolTipWindow];
        [driver->tip setToolTip: @"Tool tip"];
        [NSTimer scheduledTimerWithTimeInterval: .1 target: driver selector: @selector(step:)
                                       userInfo: nil repeats: YES];
        puts("READY");
        fflush(stdout);
        [NSApp run];
    }
}
