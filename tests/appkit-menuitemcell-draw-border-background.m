// Copyright (C) 2026 Lubos Dolezel
//
// -[NSMenuItemCell drawBorderAndBackgroundWithFrame:inView:]. The documentation (macOS) lists it
// on NSMenuItemCell, not on NSButtonCell, as the step that covers whatever frames or backs a menu
// item; the page says it runs ahead of the cell's other drawing steps, and the page for
// -drawWithFrame:inView: describes whole-cell drawing as the border first and then the interior.
// The docs also say NSMenuItemCell no longer draws menus, and NSPopUpButtonCell inherits from it.
// What the Macs do (macOS 26.7.3 and 10.14.4, x86_64 and i386; mac-probes/cristim/batch12a/p767.m): the
// method is found on NSMenuItemCell and on NSPopUpButtonCell, not on NSButtonCell, NSCell or NSActionCell;
// a pop-up button cell draws the border and background and then the interior, and its border and background
// is its bezel (a subclass sees border, bezel, interior, and the step draws the pixels of the bezel); a
// plain menu item cell draws nothing in the step and does not go through the bezel (a subclass sees border,
// interior), whether or not the cell is bordered and has a menu item.
// Build: clang -fobjc-arc -framework AppKit appkit-menuitemcell-draw-border-background.m
// Needs the Darling guest with a display (the cells are drawn into bitmaps through a window).
// On master the selector does not exist: with ARC the test does not compile against master's
// header, without ARC the first super call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static int borderCalls, bezelCalls;

// An application subclass of the pop-up cell whose overrides forward to the superclass (the
// failing receiver in a real application was such a subclass).
@interface MyPopUpCell : NSPopUpButtonCell
@end
@implementation MyPopUpCell
- (void)drawBorderAndBackgroundWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    borderCalls++;
    [super drawBorderAndBackgroundWithFrame:cellFrame inView:controlView];
}
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView {
    bezelCalls++;
    [super drawBezelWithFrame:frame inView:controlView];
}
@end

@interface MyMenuItemCell : NSMenuItemCell
@end
@implementation MyMenuItemCell
- (void)drawBorderAndBackgroundWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    borderCalls++;
    [super drawBorderAndBackgroundWithFrame:cellFrame inView:controlView];
}
- (void)drawBezelWithFrame:(NSRect)frame inView:(NSView *)controlView {
    bezelCalls++;
    [super drawBezelWithFrame:frame inView:controlView];
}
@end

typedef NS_ENUM(int, DrawMode) {
    DrawNothing, DrawWhole, DrawBezelThenInterior, DrawBezel, DrawBorderAndBackground
};

static NSCell *gCell;
static DrawMode gMode;

// Draws the cell the way the mode says, in its bounds.
@interface CellView : NSView
@end
@implementation CellView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirty {
    NSRect frame = [self bounds];
    switch (gMode) {
    case DrawNothing: break;
    case DrawWhole: [gCell drawWithFrame:frame inView:self]; break;
    case DrawBezelThenInterior:
        [(NSButtonCell *)gCell drawBezelWithFrame:frame inView:self];
        [gCell drawInteriorWithFrame:frame inView:self];
        break;
    case DrawBezel: [(NSButtonCell *)gCell drawBezelWithFrame:frame inView:self]; break;
    case DrawBorderAndBackground:
        [(NSMenuItemCell *)gCell drawBorderAndBackgroundWithFrame:frame inView:self];
        break;
    }
}
@end

static NSWindow *window;
static CellView *view;

static NSData *render(NSCell *cell, DrawMode mode) {
    gCell = cell;
    gMode = mode;
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:[view bounds]];
    [view cacheDisplayInRect:[view bounds] toBitmapImageRep:rep];
    return [NSData dataWithBytes:[rep bitmapData] length:[rep bytesPerRow] * [rep pixelsHigh]];
}

static void checkCell(NSButtonCell *cell) {
    // the cell first draws whole once, which gives it its control view
    NSData *blank = render(cell, DrawNothing);
    NSData *whole = render(cell, DrawWhole);

    // what -drawWithFrame:inView: draws is unchanged: the bezel, then the interior
    CHECK([whole isEqualToData:render(cell, DrawBezelThenInterior)]);

    // the method draws the same pixels as the bezel
    NSData *bezel = render(cell, DrawBezel);
    CHECK([render(cell, DrawBorderAndBackground) isEqualToData:bezel]);

    // a transparent cell draws nothing
    [cell setTransparent:YES];
    CHECK([render(cell, DrawWhole) isEqualToData:blank]);
    [cell setTransparent:NO];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 160, 60)
                                             styleMask:NSWindowStyleMaskTitled
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
        view = [[CellView alloc] initWithFrame:NSMakeRect(0, 0, 120, 28)];
        [[window contentView] addSubview:view];

        CHECK([NSMenuItemCell instancesRespondToSelector:
                  @selector(drawBorderAndBackgroundWithFrame:inView:)]);
        CHECK([NSPopUpButtonCell instancesRespondToSelector:
                  @selector(drawBorderAndBackgroundWithFrame:inView:)]);

        NSPopUpButtonCell *popUp = [[NSPopUpButtonCell alloc] initTextCell:@"Title" pullsDown:NO];
        [popUp addItemWithTitle:@"Title"];
        [popUp setBordered:YES];
        [popUp setBezelStyle:NSRoundedBezelStyle];
        checkCell(popUp);
        // a bordered pop-up cell draws a bezel, and the arrows are part of it
        CHECK(![render(popUp, DrawBorderAndBackground) isEqualToData:render(popUp, DrawNothing)]);

        // test_quirk_menu_item_cell_border_is_empty: the step of a menu item cell draws nothing, bordered or not
        NSMenuItemCell *itemCell = [[NSMenuItemCell alloc] initTextCell:@"Item"];
        [itemCell setBordered:YES];
        NSData *blank = render(itemCell, DrawNothing);
        (void)render(itemCell, DrawWhole);
        CHECK([render(itemCell, DrawBorderAndBackground) isEqualToData:blank]);
        [itemCell setTransparent:YES];
        CHECK([render(itemCell, DrawWhole) isEqualToData:blank]);
        [itemCell setTransparent:NO];

        // an override that calls super reaches the bezel once; whole drawing goes through it once
        MyPopUpCell *mine = [[MyPopUpCell alloc] initTextCell:@"Title" pullsDown:NO];
        [mine addItemWithTitle:@"Title"];
        [mine setBordered:YES];
        [mine setBezelStyle:NSRoundedBezelStyle];
        NSData *plainWhole = render(popUp, DrawWhole);

        borderCalls = bezelCalls = 0;
        @try {
            [mine drawBorderAndBackgroundWithFrame:NSMakeRect(0, 0, 120, 28) inView:nil];
        } @catch (NSException *e) {
            // drawing with no view may raise; what matters is that the selector was found
            CHECK(![[e name] isEqualToString:NSInvalidArgumentException]);
        }
        CHECK(borderCalls == 1);

        borderCalls = bezelCalls = 0;
        NSData *mineWhole = render(mine, DrawWhole);
        CHECK(borderCalls == 1 && bezelCalls == 1);
        CHECK([mineWhole isEqualToData:plainWhole]);

        borderCalls = bezelCalls = 0;
        (void)render(mine, DrawBorderAndBackground);
        CHECK(borderCalls == 1 && bezelCalls == 1);

        MyMenuItemCell *mineItem = [[MyMenuItemCell alloc] initTextCell:@"Item"];
        [mineItem setBordered:YES];
        borderCalls = bezelCalls = 0;
        (void)render(mineItem, DrawWhole);
        CHECK(borderCalls == 1 && bezelCalls == 0);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
