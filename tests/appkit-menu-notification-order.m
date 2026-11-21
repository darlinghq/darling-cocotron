/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Order of the notifications and delegate calls of a pop-up menu (observed on macOS 10.14.4 and 26.7.3 with a
// pop-up menu cancelled by -cancelTracking from a timer):
//   NSMenuDidBeginTrackingNotification, menuNeedsUpdate:, menuWillOpen:, (the user dismisses the menu),
//   menuDidClose:, NSMenuDidEndTrackingNotification, then popUpMenuPositioningItem:atLocation:inView: returns.
// Each of them once (not twice), and a submenu that has not been opened gets no delegate call. A delegate that adds
// items in menuNeedsUpdate: gets them shown (the update comes before the empty check and before the menu is sized).
// Cancelling from menuWillOpen: ends the tracking without menuDidClose: (macOS 10.14.4: the end notification
// comes after cancelTracking returned, 26.7.3: inside it).
// Prints PASS or FAIL. Needs a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSMutableArray<NSString *> *events;
static NSMenu *cancelInWillOpen;

@interface Target : NSObject <NSMenuDelegate>
@end
@implementation Target
- (void) action: (id) sender { [events addObject: @"action"]; }
- (void) menuNeedsUpdate: (NSMenu *) menu {
    [events addObject: [@"needsUpdate " stringByAppendingString: [menu title]]];
    if ([[menu title] isEqualToString: @"Empty"] && [menu numberOfItems] == 0)
        [[menu addItemWithTitle: @"Added" action: @selector(action:) keyEquivalent: @""] setTarget: self];
}
- (void) menuWillOpen: (NSMenu *) menu {
    [events addObject: [@"willOpen " stringByAppendingString: [menu title]]];
    if (menu == cancelInWillOpen) {
        [menu cancelTracking];
        [events addObject: @"cancel returned"];
    }
}
- (void) menuDidClose: (NSMenu *) menu { [events addObject: [@"didClose " stringByAppendingString: [menu title]]]; }
@end

static void later(NSTimeInterval seconds, void (^block)(void)) {
    NSTimer *timer = [NSTimer timerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) { block(); }];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
}

static void expect(const char *what, NSArray<NSString *> *want) {
    if (![events isEqualToArray: want])
        CHECK(NO, "%s:\n  got  %s\n  want %s", what, [[events description] UTF8String], [[want description] UTF8String]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        events = [NSMutableArray array];
        Target *target = [[Target alloc] init];

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                                       styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
        [window makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Top"];
        NSMenu *sub = [[NSMenu alloc] initWithTitle: @"Sub"];
        NSMenu *empty = [[NSMenu alloc] initWithTitle: @"Empty"];
        [menu setDelegate: target];
        [sub setDelegate: target];
        [empty setDelegate: target];
        for (int i = 1; i <= 3; i++)
            [[menu addItemWithTitle: [NSString stringWithFormat: @"Item %d", i] action: @selector(action:) keyEquivalent: @""] setTarget: target];
        NSMenuItem *subItem = [menu addItemWithTitle: @"Submenu" action: NULL keyEquivalent: @""];
        [menu setSubmenu: sub forItem: subItem];
        [[sub addItemWithTitle: @"Sub item" action: @selector(action:) keyEquivalent: @""] setTarget: target];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        id begin = [center addObserverForName: NSMenuDidBeginTrackingNotification object: nil queue: nil
                                   usingBlock: ^(NSNotification *n) { [events addObject: @"begin"]; }];
        id end = [center addObserverForName: NSMenuDidEndTrackingNotification object: nil queue: nil
                                 usingBlock: ^(NSNotification *n) { [events addObject: @"end"]; }];

        // 1. Pop up and cancel.
        later(0.5, ^{ [events addObject: @"cancelling"]; [menu cancelTracking]; });
        BOOL chosen = [menu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
        [events addObject: @"returned"];
        CHECK(!chosen, "the cancelled pop-up returned YES");
        expect("pop up and cancel", @[ @"begin", @"needsUpdate Top", @"willOpen Top", @"cancelling", @"didClose Top", @"end", @"returned" ]);

        // 2. The delegate fills an empty menu while the menu is updated.
        [events removeAllObjects];
        later(0.5, ^{ [events addObject: @"cancelling"]; [empty cancelTracking]; });
        chosen = [empty popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
        [events addObject: @"returned"];
        CHECK(!chosen, "the cancelled pop-up of the filled menu returned YES");
        CHECK([empty numberOfItems] == 1, "the item added in menuNeedsUpdate: is missing");
        expect("empty menu filled by the delegate", @[ @"begin", @"needsUpdate Empty", @"willOpen Empty", @"cancelling", @"didClose Empty", @"end", @"returned" ]);

        // 3. Cancelled from menuWillOpen:.
        [events removeAllObjects];
        cancelInWillOpen = menu;
        chosen = [menu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
        [events addObject: @"returned"];
        cancelInWillOpen = nil;
        CHECK(!chosen, "the pop-up cancelled in menuWillOpen: returned YES");
        // macOS 26.7.3 posts the end notification from inside cancelTracking (and a second one without a menu), macOS
        // 10.14.4 once after it returned; only what both agree on is checked.
        NSArray *start = @[ @"begin", @"needsUpdate Top", @"willOpen Top" ];
        CHECK([events count] >= 5 && [[events subarrayWithRange: NSMakeRange(0, 3)] isEqualToArray: start],
              "cancelled in menuWillOpen: wrong start: %s", [[events description] UTF8String]);
        CHECK([events containsObject: @"end"] && ![events containsObject: @"didClose Top"] && [[events lastObject] isEqualToString: @"returned"],
              "cancelled in menuWillOpen: %s", [[events description] UTF8String]);

        [center removeObserver: begin];
        [center removeObserver: end];
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
