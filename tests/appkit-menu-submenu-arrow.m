/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: a menu item with a submenu shows an arrow at the right of its row,
// and the menu is wide enough for it.
//  1. -[NSMenu size] of a menu with a submenu item is wider than that of the
//     same menu without one (macOS 10.14.4: +39, 26.7.3: +31 points, with the
//     title "Recent Documents"; at least 25 is required here).
//  2. (Darling only: macOS draws its menus in private windows that cannot be
//     rendered through public API, so the step is skipped there.) While the
//     menu is open, the rows of the submenu items have a mark more than two
//     pixels wide in the right 30 pixels, and the rows of the items without
//     a submenu have none.
// Prints PASS or FAIL. Needs a window server.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static NSMenu *menuWith(NSString *title, BOOL submenu) {
    NSMenu *m = [[NSMenu alloc] initWithTitle: @"t"];
    NSMenuItem *item = [m addItemWithTitle: title action: NULL keyEquivalent: @""];
    if (submenu) {
        NSMenu *s = [[NSMenu alloc] initWithTitle: @"s"];
        [s addItemWithTitle: @"x" action: NULL keyEquivalent: @""];
        [item setSubmenu: s];
    }
    return m;
}

static NSMenu *openMenu;
static NSWindow *hostWindow;
static BOOL analysed;

// Whether a pixel is dark text/arrow ink.
static BOOL isInk(NSBitmapImageRep *rep, NSInteger x, NSInteger y) {
    NSUInteger px[4] = {255, 255, 255, 255};
    [rep getPixel: px atX: x y: y];
    return px[0] < 140 && px[1] < 140 && px[2] < 140;
}

// Checks one group of adjacent rows (one menu item) that has ink in the right 30 pixels: the ink must end in a mark
// 3 to 12 pixels wide, detached from the title (a gap of clear columns before it). Returns the mark's width.
static NSInteger arrowWidth(NSBitmapImageRep *rep, NSInteger y0, NSInteger y1) {
    NSInteger w = [rep pixelsWide], right = -1, width = 0;
    BOOL cols[w];
    for (NSInteger x = 0; x < w; x++) {
        cols[x] = NO;
        for (NSInteger y = y0; y <= y1 && !cols[x]; y++)
            if (x >= 2 && x < w - 2 && isInk(rep, x, y)) cols[x] = YES;
        if (cols[x]) right = x;
    }
    for (NSInteger x = right; x >= 0 && cols[x]; x--) width++;
    return width;
}

// Ends the menu tracking loop the way a user would: Escape (kept for the 8 s guard, which also
// covers a hung -cancelTracking); the examination ends it with -[NSMenu cancelTracking].
static void pressEscape(void) {
    NSEvent *escape = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0
                                   windowNumber: [hostWindow windowNumber] context: nil
                                     characters: @"\x1b" charactersIgnoringModifiers: @"\x1b" isARepeat: NO keyCode: 53];
    [NSApp postEvent: escape atStart: YES];
}

static void analyse(void) {
    analysed = YES;
    NSWindow *menuWindow = nil;
    for (NSWindow *w in [NSApp windows])
        if (w != hostWindow && [w isVisible] && [NSStringFromClass([w class]) rangeOfString: @"Menu"].location != NSNotFound)
            menuWindow = w;
    CHECK(menuWindow != nil, "no menu window while the menu is open");
    if (menuWindow != nil) {
        NSView *content = [menuWindow contentView];
        NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect: [content bounds]];
        [content cacheDisplayInRect: [content bounds] toBitmapImageRep: rep];
        NSInteger h = [rep pixelsHigh], w = [rep pixelsWide];
        // Groups of adjacent rows with ink in the right 30 pixels: the submenu items (title text of a long title
        // can reach there too, hence the width check on the mark itself).
        int groups = 0;
        NSInteger start = -1;
        for (NSInteger y = 0; y <= h; y++) {
            BOOL any = NO;
            for (NSInteger x = w - 30; y < h && x < w - 2 && !any; x++)
                any = isInk(rep, x, y);
            if (any && start < 0) start = y;
            if (!any && start >= 0) {
                NSInteger width = arrowWidth(rep, start, y - 1);
                groups++;
                CHECK(width >= 3 && width <= 12, "rows %ld-%ld: the mark at the right is %ld pixels wide, expected 3 to 12 "
                      "(1 means the arrow is clipped, more means it touches the title)", (long) start, (long) (y - 1), (long) width);
                start = -1;
            }
        }
        CHECK(groups == 2, "%d rows groups with ink in the right 30 pixels, expected 2 (one per submenu item)", groups);
    }
    [openMenu cancelTracking];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

        NSString *title = @"Recent Documents";
        CGFloat plain = [menuWith(title, NO) size].width;
        CGFloat withSubmenu = [menuWith(title, YES) size].width;
        CHECK(withSubmenu - plain >= 25, "submenu column: menu is %.1f wider with a submenu item, expected at least 25", withSubmenu - plain);

        openMenu = [[NSMenu alloc] initWithTitle: @"menu"];
        [openMenu addItemWithTitle: @"Plain item" action: NULL keyEquivalent: @""];
        for (NSString *t in @[ @"Recent Documents", @"Share" ]) {
            NSMenuItem *i = [openMenu addItemWithTitle: t action: NULL keyEquivalent: @""];
            NSMenu *s = [[NSMenu alloc] initWithTitle: t];
            [s addItemWithTitle: @"x" action: NULL keyEquivalent: @""];
            [i setSubmenu: s];
        }
        [openMenu addItemWithTitle: @"Other plain item" action: NULL keyEquivalent: @""];

        if (NSClassFromString(@"NSSubmenuView") == nil) {
            printf(failures ? "FAIL (%d)\n" : "PASS (rendering step skipped: not Darling)\n", failures);
            return failures != 0;
        }
        hostWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                                 styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: NO];
        [hostWindow makeKeyAndOrderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];

        NSTimer *timer = [NSTimer timerWithTimeInterval: 1.0 repeats: NO block: ^(NSTimer *t) { analyse(); }];
        [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
        NSTimer *guard = [NSTimer timerWithTimeInterval: 8.0 repeats: NO block: ^(NSTimer *t) { pressEscape(); }];
        [[NSRunLoop currentRunLoop] addTimer: guard forMode: NSRunLoopCommonModes];
        [openMenu popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 250) inView: [hostWindow contentView]];
        CHECK(analysed, "the menu closed before it was examined");
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
