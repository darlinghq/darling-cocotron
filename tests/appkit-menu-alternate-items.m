/*
 * Copyright (C) 2026 Lubos Dolezel
 *
 * Alternate menu items (-[NSMenuItem setAlternate:]). An alternate that has
 * the key equivalent of the item right before it (letter case aside) is
 * folded into that item: the open menu shows one row for the two. An
 * alternate with another key equivalent, or after a hidden item with another
 * one, is shown as an item of its own.
 *
 * The rows are counted from the height of the open menu's window, as on
 * macOS 26.7.3. Where pop-up menus are not NSWindows (macOS 10.14.4) the
 * test uses -[NSMenu size] instead, which there gives the rows shown too
 * (macOS 26.7.3 counts every item in it). The program builds and runs on
 * macOS; both versions pass.
 */
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static NSMenuItem *item(NSString *title, NSString *key, NSUInteger mask, BOOL alternate)
{
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:title action:@selector(choose:) keyEquivalent:key];
    [i setKeyEquivalentModifierMask:mask];
    [i setAlternate:alternate];
    return i;
}

static NSMenu *menuWith(NSArray *items)
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
    [menu setAutoenablesItems:NO];
    for (NSMenuItem *i in items)
        [menu addItem:i];
    return menu;
}

// The height of the window the menu opens in, measured while it is tracked.
static CGFloat openMenuHeight(NSMenu *menu, NSView *view)
{
    __block CGFloat height = -1;
    NSArray *before = [[NSApp windows] copy];
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *t) {
        NSWindow *menuWindow = nil;
        for (NSWindow *w in [NSApp windows])
            if (![before containsObject:w] && [w isVisible])
                menuWindow = w;
        height = menuWindow ? NSHeight([menuWindow frame]) : -1;
        if ([menu respondsToSelector:@selector(cancelTracking)])
            [menu cancelTracking];
        else
            [NSApp postEvent:[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                              timestamp:0 windowNumber:[menuWindow windowNumber] context:nil
                                             characters:@"\e" charactersIgnoringModifiers:@"\e"
                                              isARepeat:NO keyCode:53]
                     atStart:NO];
    }];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(20, 250) inView:view];
    [timer invalidate];
    return height;
}

static BOOL useWindows = YES;

static CGFloat measure(NSArray *items, NSView *view)
{
    NSMenu *menu = menuWith(items);
    return useWindows ? openMenuHeight(menu, view) : [menu size].height;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 300)
                                                       styleMask:NSWindowStyleMaskTitled
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window orderFront:nil];
        // Let the window reach the screen before menus open over it: a window
        // system can place a menu as a pop-up of a window only once it is shown.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        NSView *view = [window contentView];
        NSUInteger cmd = NSEventModifierFlagCommand, opt = NSEventModifierFlagOption;

        if (openMenuHeight(menuWith(@[item(@"Close Window", @"w", cmd, NO)]), view) < 0) {
            useWindows = NO;
            printf("  pop-up menus are not windows here: rows are counted with -[NSMenu size]\n");
        }

        CGFloat one = measure(@[item(@"Close Window", @"w", cmd, NO)], view);
        CGFloat two = measure(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"w", cmd | opt, NO)], view);
        CGFloat alternate = measure(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"w", cmd | opt, YES)], view);
        CGFloat upperCase = measure(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"W", cmd | opt, YES)], view);
        CGFloat sameMask = measure(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"w", cmd, YES)], view);
        CGFloat noKeys = measure(@[item(@"Close Window", @"", 0, NO), item(@"Close All", @"", opt, YES)], view);
        CGFloat otherKey = measure(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"x", cmd | opt, YES)], view);
        printf("  heights: one item %.0f, two items %.0f, alternate %.0f, upper-case key %.0f, same mask %.0f, "
               "no keys %.0f, another key %.0f\n", one, two, alternate, upperCase, sameMask, noKeys, otherKey);

        expect(one > 0 && two > one, "the open menus were measured");
        expect(alternate == one, "an alternate is folded into the item before it");
        expect(upperCase == one, "an alternate whose key equivalent differs in case only is folded");
        expect(sameMask == one, "an alternate with the same modifier mask is folded");
        expect(noKeys == one, "an alternate without a key equivalent is folded into an item without one");
        expect(otherKey == two, "an alternate with another key equivalent is shown as an item");

        if (useWindows) {
            NSMenuItem *hidden = item(@"Hidden", @"q", cmd, NO);
            [hidden setHidden:YES];
            CGFloat afterHidden = measure(@[item(@"Close Window", @"w", cmd, NO), hidden,
                                            item(@"Close All", @"w", cmd | opt, YES)], view);
            expect(afterHidden == two, "an alternate after a hidden item with another key is shown as an item");
        }

        NSMenu *menu = menuWith(@[item(@"Close Window", @"w", cmd, NO), item(@"Close All", @"w", cmd | opt, YES)]);
        expect(![[menu itemAtIndex:1] isHidden] && [menu numberOfItems] == 2,
               "the alternate stays in the menu and is not hidden");
        [window orderOut:nil];
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures ? 1 : 0;
}
