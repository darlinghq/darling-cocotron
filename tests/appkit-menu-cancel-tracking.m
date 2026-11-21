/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract of -[NSMenu cancelTracking] and -cancelTrackingWithoutAnimation (checked on macOS 10.14.4 and
// 26.7.3 with a pop-up menu cancelled from a timer):
//  1. Cancelling the menu that is being tracked ends the tracking: popUpMenuPositioningItem:atLocation:inView:
//     returns NO, no item's action is sent, NSMenuDidEndTrackingNotification is posted once for the menu before
//     the call returns, and the delegate's menuDidClose: has been called by then. NSMenuDidBeginTrackingNotification
//     was posted once before.
//  2. The same for cancelTrackingWithoutAnimation.
//  3. Cancelling a menu that is not being tracked (before any tracking, or another menu while this one is
//     tracked) does nothing: no notification, and the tracking goes on.
//  4. Cancelling twice in a row is the same as cancelling once, and a later pop-up is not affected by it.
// (macOS finishes the first variant with a fade of a quarter of a second; the order of the events is the same.)
// Prints PASS or FAIL. Needs a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSMutableArray<NSString *> *events;

@interface Target : NSObject <NSMenuDelegate>
@end
@implementation Target
- (void) action: (id) sender { [events addObject: @"action"]; }
- (void) menuDidClose: (NSMenu *) menu { [events addObject: @"close"]; }
@end

static NSUInteger count(NSString *what) {
    NSUInteger n = 0;
    for (NSString *s in events)
        if ([s isEqualToString: what])
            n++;
    return n;
}

static NSUInteger lastIndex(NSString *what) {
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < [events count]; i++)
        if ([[events objectAtIndex: i] isEqualToString: what])
            index = i;
    return index;
}

static void later(NSTimeInterval seconds, void (^block)(void)) {
    NSTimer *timer = [NSTimer timerWithTimeInterval: seconds repeats: NO block: ^(NSTimer *t) { block(); }];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
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

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Menu"];
        [menu setDelegate: target];
        for (int i = 1; i <= 3; i++)
            [[menu addItemWithTitle: [NSString stringWithFormat: @"Item %d", i] action: @selector(action:) keyEquivalent: @""] setTarget: target];
        NSMenu *other = [[NSMenu alloc] initWithTitle: @"Other"];
        [other addItemWithTitle: @"Other item" action: NULL keyEquivalent: @""];

        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        id begin = [center addObserverForName: NSMenuDidBeginTrackingNotification object: menu queue: nil
                                   usingBlock: ^(NSNotification *n) { [events addObject: @"begin"]; }];
        id end = [center addObserverForName: NSMenuDidEndTrackingNotification object: menu queue: nil
                                 usingBlock: ^(NSNotification *n) { [events addObject: @"end"]; }];
        id otherEnd = [center addObserverForName: NSMenuDidEndTrackingNotification object: other queue: nil
                                      usingBlock: ^(NSNotification *n) { [events addObject: @"other end"]; }];

        // 3a. Nothing is tracked.
        [menu cancelTracking];
        [menu cancelTrackingWithoutAnimation];
        CHECK([events count] == 0, "cancelling a menu that is not tracked changed something: %s", [[events description] UTF8String]);

        for (int variant = 0; variant < 3; variant++) {
            [events removeAllObjects];
            // 1 (variant 0), 2 (variant 1) and 4 (variant 2: twice, after the cancellation of an unrelated menu)
            later(0.5, ^{
                [events addObject: @"cancelling"];
                if (variant == 1)
                    [menu cancelTrackingWithoutAnimation];
                else {
                    [other cancelTracking];
                    [menu cancelTracking];
                    if (variant == 2)
                        [menu cancelTracking];
                }
                [events addObject: @"cancel returned"];
            });
            // 3b. The unrelated menu's cancellation must not have ended the tracking before this check.
            __block BOOL stillTracking = NO;
            if (variant == 2)
                later(0.2, ^{
                    [other cancelTracking];
                    later(0.1, ^{ stillTracking = ![events containsObject: @"end"] && ![events containsObject: @"cancelling"]; });
                });
            BOOL chosen = [menu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
            [events addObject: @"returned"];
            NSString *state = [events description];
            CHECK(!chosen, "variant %d: the cancelled pop-up returned YES", variant);
            CHECK(count(@"action") == 0, "variant %d: an action was sent: %s", variant, [state UTF8String]);
            CHECK(count(@"begin") == 1, "variant %d: %lu begin notifications: %s", variant, (unsigned long) count(@"begin"), [state UTF8String]);
            CHECK(count(@"end") == 1, "variant %d: %lu end notifications: %s", variant, (unsigned long) count(@"end"), [state UTF8String]);
            CHECK(count(@"other end") == 0, "variant %d: the other menu got an end notification", variant);
            CHECK(count(@"close") >= 1 && lastIndex(@"close") != NSNotFound && [events indexOfObject: @"close"] < [events indexOfObject: @"end"],
                  "variant %d: menuDidClose: not before the end notification: %s", variant, [state UTF8String]);
            CHECK([events indexOfObject: @"cancelling"] < [events indexOfObject: @"end"], "variant %d: ended before the cancellation: %s", variant, [state UTF8String]);
            CHECK([events indexOfObject: @"end"] < [events indexOfObject: @"returned"], "variant %d: the end notification came after the return: %s", variant, [state UTF8String]);
            if (variant == 2)
                CHECK(stillTracking, "cancelling another menu ended the tracking");
        }

        // 4. A cancellation does not outlive the tracking it ended: a menu popped up afterwards is tracked until it is cancelled.
        [events removeAllObjects];
        __block BOOL survived = NO;
        later(0.3, ^{ survived = [events count] == 1 && [[events objectAtIndex: 0] isEqualToString: @"begin"]; [menu cancelTracking]; });
        [menu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
        CHECK(survived, "a pop-up after a cancelled one did not stay open: %s", [[events description] UTF8String]);

        [center removeObserver: begin];
        [center removeObserver: end];
        [center removeObserver: otherEnd];
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
