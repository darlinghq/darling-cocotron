/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A menu opened from the application's own menu bar must stay open while the pointer crosses from
// the bar into the menu: the whole height of the bar belongs to the item under the pointer, so
// no row of pixels along the bottom of the bar (below the drawn highlight) selects nothing and
// pops the open menu. The bar is found through the display, which is not public API. Run it with
// no global menu on the session bus. Prints SKIP (exit 77) when there is no menu bar window.
#import <AppKit/AppKit.h>
#include <objc/message.h>
#include <stdio.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL ok, NSString *what) {
    printf("%s: %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSMenu *main = [[NSMenu alloc] initWithTitle: @"Main"];
        for (NSString *title in @[@"App", @"File", @"Edit"]) {
            NSMenuItem *item = [main addItemWithTitle: title action: NULL keyEquivalent: @""];
            NSMenu *sub = [[NSMenu alloc] initWithTitle: title];
            [sub addItemWithTitle: @"Entry" action: NULL keyEquivalent: @""];
            [item setSubmenu: sub];
        }
        [NSApp setMainMenu: main];
        [NSApp finishLaunching];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 2.0]];

        NSWindow *bar = nil;
        @try {
            id appMenu = [[NSDisplay currentDisplay] valueForKey: @"_appMenu"];
            bar = [[appMenu valueForKey: @"_bar"] valueForKey: @"_bar"];
        } @catch (id e) {
        }
        NSView *view = [[[bar contentView] subviews] firstObject];
        SEL hit = NSSelectorFromString(@"itemIndexAtPoint:rect:");
        if (view == nil || ![view respondsToSelector: hit]) {
            printf("SKIP: no menu bar window\n");
            return 77;
        }

        NSRect bounds = [view bounds];
        typedef NSUInteger (*HitFn)(id, SEL, NSPoint, NSRect *);
        HitFn hitFn = (HitFn) objc_msgSend;
        NSRect rect = NSZeroRect;
        NSUInteger found = 0, last = NSNotFound;
        NSMutableArray *columns = [NSMutableArray array];

        // One x inside each item, found along the middle of the bar
        for (CGFloat x = 0; x < bounds.size.width; x += 1) {
            NSUInteger index = hitFn(view, hit, NSMakePoint(x, NSMidY(bounds)), &rect);
            if (index != NSNotFound && index != last) {
                [columns addObject: [NSNumber numberWithDouble: NSMidX(rect)]];
                found++;
            }
            last = index;
        }
        expect(found == 3, [NSString stringWithFormat: @"the bar has three items (%lu)", (unsigned long) found]);

        // Every row of the bar, in sub-pixel steps, selects the same item as the middle of it
        for (NSUInteger i = 0; i < [columns count]; i++) {
            CGFloat x = [[columns objectAtIndex: i] doubleValue];
            NSUInteger expected = hitFn(view, hit, NSMakePoint(x, NSMidY(bounds)), &rect);
            NSUInteger misses = 0;
            for (CGFloat y = NSMinY(bounds); y < NSMaxY(bounds); y += 0.25)
                if (hitFn(view, hit, NSMakePoint(x, y), &rect) != expected)
                    misses++;
            expect(misses == 0, [NSString stringWithFormat: @"item %lu is selected over the whole height of the bar (%lu misses)",
                                                           (unsigned long) i, (unsigned long) misses]);
        }
        // Outside the bar, nothing is selected
        expect(hitFn(view, hit, NSMakePoint([[columns firstObject] doubleValue], NSMaxY(bounds) + 1), &rect) == NSNotFound ||
                       hitFn(view, hit, NSMakePoint([[columns firstObject] doubleValue], NSMinY(bounds) - 1), &rect) == NSNotFound,
               @"a point outside the bar selects nothing");
    }
    printf(failures == 0 ? "ALL PASSED\n" : "%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
