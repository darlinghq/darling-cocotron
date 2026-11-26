// Copyright (C) 2026 Lubos Dolezel
//
// "Click in the scroll bar to" of System Preferences, the AppleScrollerPagingBehavior default: with 0 (or not
// set) a click in the page area of a scroller scrolls by a page toward the click, with 1 it jumps to the
// clicked spot. The click is a mouse down whose button release is already in the event queue.
// Build: clang -framework AppKit appkit-scroller-paging-behavior.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// Clicks the page area of the scroll view's vertical scroller at the fraction of the slot
static void click_slot(NSWindow *window, NSScroller *scroller, double fraction) {
    NSRect slot = [scroller rectForPart: NSScrollerKnobSlot];
    NSPoint inScroller = NSMakePoint(NSMidX(slot), slot.origin.y + ([scroller isFlipped] ? fraction : 1 - fraction) * slot.size.height);
    NSPoint inWindow = [scroller convertPoint: inScroller toView: nil];
    NSEvent *down = [NSEvent mouseEventWithType: NSLeftMouseDown location: inWindow modifierFlags: 0 timestamp: 0
                                   windowNumber: [window windowNumber] context: nil eventNumber: 1 clickCount: 1 pressure: 1];
    NSEvent *up = [NSEvent mouseEventWithType: NSLeftMouseUp location: inWindow modifierFlags: 0 timestamp: 0
                                 windowNumber: [window windowNumber] context: nil eventNumber: 2 clickCount: 1 pressure: 0];
    [NSApp postEvent: up atStart: NO];
    [scroller mouseDown: down];
}

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL) isFlipped { return YES; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 215, 200)
                                                       styleMask: NSTitledWindowMask backing: NSBackingStoreBuffered defer: NO];
        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 215, 200)];
        [scrollView setHasVerticalScroller: YES];
        [scrollView setScrollerStyle: NSScrollerStyleLegacy];
        NSView *document = [[FlippedView alloc] initWithFrame: NSMakeRect(0, 0, 200, 1000)];
        [scrollView setDocumentView: document];
        [window setContentView: scrollView];
        [window makeKeyAndOrderFront: nil];
        NSScroller *scroller = [scrollView verticalScroller];
        CGFloat clip = [[scrollView contentView] bounds].size.height;
        [scroller setEnabled: YES];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey: @"AppleScrollerPagingBehavior"];

        // not set: the click pages
        CGFloat before = [[scrollView contentView] bounds].origin.y;
        click_slot(window, scroller, 0.9);
        CGFloat moved = fabs([[scrollView contentView] bounds].origin.y - before);
        CHECK(moved > clip * 0.4 && moved <= clip);

        // 0 is the same
        [defaults setInteger: 0 forKey: @"AppleScrollerPagingBehavior"];
        [[scrollView contentView] scrollToPoint: NSMakePoint(0, 0)];
        [scrollView reflectScrolledClipView: [scrollView contentView]];
        click_slot(window, scroller, 0.9);
        moved = fabs([[scrollView contentView] bounds].origin.y);
        CHECK(moved > clip * 0.4 && moved <= clip);

        // 1: the knob goes to the clicked spot
        [defaults setInteger: 1 forKey: @"AppleScrollerPagingBehavior"];
        [[scrollView contentView] scrollToPoint: NSMakePoint(0, 0)];
        [scrollView reflectScrolledClipView: [scrollView contentView]];
        click_slot(window, scroller, 0.9);
        CHECK([scroller doubleValue] > 0.8);
        CHECK(fabs([[scrollView contentView] bounds].origin.y) > clip * 2);

        [defaults removeObjectForKey: @"AppleScrollerPagingBehavior"];
    }
    puts(failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
