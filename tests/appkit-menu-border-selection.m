// SPDX-License-Identifier: MIT
// Run with a window server (for example DARLING_APPKIT_BACKEND=x11 on Xvfb).
// Selecting the first submenu row must work after entering through its border,
// where the hit test finds no item. All input is posted to this test's windows.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

// Exercise the tracker directly so that selection and cancellation can be
// checked independently of NSMenu's action dispatch.
@interface NSView (MenuTrackingTest)
- (NSMenuItem *) trackForEvent: (NSEvent *) event;
@end

static NSView *menuView(NSView *view, NSMenu *menu) {
    if ([view menu] == menu)
        return view;
    for (NSView *child in [view subviews]) {
        NSView *found = menuView(child, menu);
        if (found != nil)
            return found;
    }
    return nil;
}

static NSEvent *mouseEvent(NSEventType type, NSWindow *window, NSPoint point) {
    return [NSEvent mouseEventWithType: type location: point modifierFlags: 0
                            timestamp: [NSDate timeIntervalSinceReferenceDate]
                         windowNumber: [window windowNumber] context: nil
                          eventNumber: 0 clickCount: 1 pressure: 0];
}

@interface MenuInput : NSObject {
@public
    NSWindow *window;
    NSView *barView;
    NSUInteger step;
    BOOL enterBorder, cancel, disabled;
}
- (void) tick: (NSTimer *) timer;
- (void) timeout: (NSTimer *) timer;
@end

@implementation MenuInput
- (void) timeout: (NSTimer *) timer {
    fprintf(stderr, "FAIL: menu tracking did not finish\n");
    exit(1);
}
- (void) tick: (NSTimer *) timer {
    if (step++ == 0) {
        NSPoint point = [barView convertPoint: NSMakePoint(15, NSMidY([barView bounds]))
                                      toView: nil];
        [NSApp postEvent: mouseEvent(NSLeftMouseUp, window, point) atStart: NO];
        return;
    }

    NSUInteger downStep = enterBorder ? 4 : 3;
    NSUInteger escapeStep = cancel ? downStep : downStep + 2;
    if ((cancel || disabled) && step >= escapeStep) {
        // One Escape closes the submenu; another cancels the bar's tracker.
        NSEvent *escape = [NSEvent keyEventWithType: NSKeyDown location: NSZeroPoint
                modifierFlags: 0 timestamp: [NSDate timeIntervalSinceReferenceDate]
                windowNumber: [window windowNumber] context: nil characters: @"\033"
                charactersIgnoringModifiers: @"\033" isARepeat: NO keyCode: 53];
        [NSApp postEvent: escape atStart: NO];
        if (step == escapeStep + 1)
            [timer invalidate];
        return;
    }

    NSWindow *popup = nil;
    for (NSWindow *candidate in [NSApp windows]) {
        if (candidate != window && [candidate isVisible] &&
            [candidate level] == NSSubmenuWindowLevel) {
            popup = candidate;
            break;
        }
    }
    if (popup == nil) {
        fprintf(stderr, "FAIL: submenu did not open\n");
        exit(1);
    }

    // The first point is inside the view's border, outside every item. The
    // next is in the first row, overlapping the bar item's old local rect.
    BOOL border = enterBorder && step == 2;
    NSView *content = [popup contentView];
    NSPoint point = [content convertPoint:
            NSMakePoint(10, NSHeight([content bounds]) - (border ? 1 : 10))
                                  toView: nil];
    NSEventType type = step < downStep ? NSMouseMoved :
                      step == downStep ? NSLeftMouseDown : NSLeftMouseUp;
    [NSApp postEvent: mouseEvent(type, popup, point) atStart: NO];
    if (step == downStep + 1 && !disabled)
        [timer invalidate];
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        MenuInput *input = [[MenuInput alloc] init];
        NSMenu *bar = [[NSMenu alloc] initWithTitle: @"Menu test"];
        NSMenuItem *top = [bar addItemWithTitle: @"Test" action: NULL keyEquivalent: @""];
        NSMenu *submenu = [[NSMenu alloc] initWithTitle: @"Test"];
        [submenu setAutoenablesItems: NO];
        NSMenuItem *leaf = [submenu addItemWithTitle: @"Select" action: @selector(description)
                                     keyEquivalent: @""];
        [top setSubmenu: submenu];
        [NSApp setMainMenu: bar];
        input->window = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 360, 200)
                styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
        [input->window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        input->barView = menuView([[input->window contentView] superview], bar);
        if (input->barView == nil) {
            fprintf(stderr, "FAIL: window menu bar is missing\n");
            return 1;
        }

        int failures = 0;
        for (NSUInteger test = 0; test < 4; test++) {
            input->step = 0;
            input->enterBorder = test != 0;
            input->cancel = test == 2;
            input->disabled = test == 3;
            [leaf setEnabled: test != 3];
            NSTimer *events = [NSTimer timerWithTimeInterval: 0.15 target: input
                    selector: @selector(tick:) userInfo: nil repeats: YES];
            NSTimer *deadline = [NSTimer timerWithTimeInterval: 5 target: input
                    selector: @selector(timeout:) userInfo: nil repeats: NO];
            [[NSRunLoop currentRunLoop] addTimer: events forMode: NSEventTrackingRunLoopMode];
            [[NSRunLoop currentRunLoop] addTimer: deadline forMode: NSEventTrackingRunLoopMode];
            NSPoint point = [input->barView convertPoint:
                    NSMakePoint(15, NSMidY([input->barView bounds])) toView: nil];
            NSMenuItem *selected = [input->barView trackForEvent:
                    mouseEvent(NSLeftMouseDown, input->window, point)];
            [events invalidate];
            [deadline invalidate];
            NSMenuItem *expected = test < 2 ? leaf : nil;
            // A disabled row must leave tracking open until both Escapes;
            // an unrelated early cancellation must not count as a pass.
            NSUInteger expectedSteps[] = {4, 5, 5, 7};
            BOOL passed = selected == expected && input->step == expectedSteps[test];
            printf("%s: %s\n", passed ? "PASS" : "FAIL",
                   test == 0 ? "direct first-row selection" :
                   test == 1 ? "border then first-row selection" :
                   test == 2 ? "Escape after border entry" : "disabled first row");
            if (!passed)
                failures++;
        }
        return failures ? 1 : 0;
    }
}
