// Copyright (C) 2026 Lubos Dolezel
//
// A menu tells its delegate that it is about to highlight an item with -menu:willHighlightItem:, before the
// highlight changes, with nil when no item is about to be highlighted
// (https://developer.apple.com/documentation/appkit/nsmenudelegate/menu(_:willhighlight:)). The method is
// optional, so a delegate without it, or a menu without a delegate, is not an error. The view that shows the menu is
// Darling's NSSubmenuView (private), driven through -setSelectedItemIndex:, the way its tracking loop highlights an
// item; the index counts the items shown, not the hidden ones. A pop-up menu that is cancelled while an item is
// highlighted ends with nil before -menuDidClose: (a QUIRK observed on macOS 26.7.3; the test is
// test_quirk_highlight_cleared_before_did_close). That part needs a window server. Build without ARC.
#import <AppKit/AppKit.h>
#import <objc/message.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    printf("%s %s\n", condition ? "PASS" : "FAIL", what);
    if (!condition)
        failures++;
}

static NSView *menuView;

static NSUInteger selectedIndexOf(NSView *view) {
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(view, @selector(selectedItemIndex));
}

static void highlight(NSView *view, NSUInteger index) {
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(view, @selector(setSelectedItemIndex:), index);
}

// Records each call: the item's title (@"(nil)" for nil) and the view's highlighted index at the time of the call.
@interface Recorder : NSObject <NSMenuDelegate> {
@public
    NSMutableArray *titles;
    NSMutableArray *indexesSeenInCall;
    NSMenu *lastMenu;
}
@end

@implementation Recorder
- (id) init {
    self = [super init];
    titles = [[NSMutableArray alloc] init];
    indexesSeenInCall = [[NSMutableArray alloc] init];
    return self;
}
- (void) dealloc {
    [titles release];
    [indexesSeenInCall release];
    [super dealloc];
}
- (void) menu: (NSMenu *) menu willHighlightItem: (NSMenuItem *) item {
    lastMenu = menu;
    [titles addObject: item != nil ? [item title] : @"(nil)"];
    [indexesSeenInCall addObject: [NSNumber numberWithUnsignedInteger: selectedIndexOf(menuView)]];
}
@end

// A delegate that implements none of the optional methods.
@interface PlainDelegate : NSObject <NSMenuDelegate>
@end
@implementation PlainDelegate
@end

// Records the delegate calls of a pop-up menu that is shown and cancelled.
static NSMutableArray *trackingEvents;

@interface TrackingRecorder : NSObject <NSMenuDelegate>
@end
@implementation TrackingRecorder
- (void) menu: (NSMenu *) menu willHighlightItem: (NSMenuItem *) item {
    [trackingEvents addObject: item != nil ? [@"highlight " stringByAppendingString: [item title]] : @"highlight nil"];
}
- (void) menuDidClose: (NSMenu *) menu {
    [trackingEvents addObject: @"didClose"];
}
@end

static NSView *viewFor(NSMenu *menu) {
    return [[[NSClassFromString(@"NSSubmenuView") alloc] performSelector: @selector(initWithMenu:)
                                                              withObject: menu] autorelease];
}

// QUIRK test: with an item highlighted, tracking that ends sends nil before -menuDidClose:.
static void test_quirk_highlight_cleared_before_did_close(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(300, 300, 400, 300)
                                                   styleMask: NSWindowStyleMaskTitled
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];
    [window makeKeyAndOrderFront: nil];
    NSMenu *popup = [[NSMenu alloc] initWithTitle: @"Popup"];
    [popup addItemWithTitle: @"One" action: NULL keyEquivalent: @""];
    [popup addItemWithTitle: @"Two" action: NULL keyEquivalent: @""];
    TrackingRecorder *recorder = [[TrackingRecorder alloc] init];
    [popup setDelegate: recorder];
    trackingEvents = [[NSMutableArray alloc] init];

    NSTimer *timer = [NSTimer timerWithTimeInterval: 0.5 repeats: NO block: ^(NSTimer *t) {
        // Highlight the way the tracking loop does, then cancel.
        for (NSWindow *candidate in [NSApp windows]) {
            if (![candidate respondsToSelector: @selector(menuView)])
                continue;
            NSView *view = [candidate performSelector: @selector(menuView)];
            if ([[view performSelector: @selector(menu)] isEqual: popup])
                highlight(view, 1);
        }
        [popup cancelTracking];
    }];
    [[NSRunLoop currentRunLoop] addTimer: timer forMode: NSRunLoopCommonModes];
    [popup popUpMenuPositioningItem: nil atLocation: NSMakePoint(40, 200) inView: [window contentView]];
    NSArray *want = @[ @"highlight Two", @"highlight nil", @"didClose" ];
    expect([trackingEvents isEqualToArray: want], "tracking that ends with an item highlighted sends nil before didClose");
    if (![trackingEvents isEqualToArray: want])
        fprintf(stderr, "  got %s\n", [[trackingEvents description] UTF8String]);
    [popup setDelegate: nil];
    [recorder release];
    [popup release];
    [window close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSMenu *menu = [[NSMenu alloc] initWithTitle: @"Test"];
        [menu setAutoenablesItems: NO];
        NSMenuItem *hidden = [menu addItemWithTitle: @"Hidden" action: NULL keyEquivalent: @""];
        [menu addItemWithTitle: @"First" action: NULL keyEquivalent: @""];
        [menu addItemWithTitle: @"Second" action: NULL keyEquivalent: @""];
        [hidden setHidden: YES];

        Recorder *recorder = [[Recorder alloc] init];
        [menu setDelegate: recorder];
        menuView = viewFor(menu);
        NSUInteger none = selectedIndexOf(menuView);

        highlight(menuView, 1);
        expect([recorder->titles isEqualToArray: @[ @"Second" ]], "highlighting shown item 1 names the second shown item");
        expect(recorder->lastMenu == menu, "the delegate is given the menu");
        expect([[recorder->indexesSeenInCall lastObject] unsignedIntegerValue] == none,
               "the call comes before the highlight changes");
        expect(selectedIndexOf(menuView) == 1, "the highlight is applied after the call");

        highlight(menuView, 1);
        expect([recorder->titles count] == 1, "highlighting the item that is already highlighted sends nothing");

        highlight(menuView, 0);
        expect([[recorder->titles lastObject] isEqualToString: @"First"], "hidden items take no index");

        highlight(menuView, NSNotFound);
        expect([[recorder->titles lastObject] isEqualToString: @"(nil)"], "highlighting nothing sends nil");
        expect([recorder->titles count] == 3, "one call per change");

        // The optional method: a delegate without it, and a menu without a delegate.
        [menu setDelegate: [[[PlainDelegate alloc] init] autorelease]];
        highlight(menuView, 0);
        expect(selectedIndexOf(menuView) == 0, "a delegate without the method does not stop the highlight");
        [menu setDelegate: nil];
        highlight(menuView, NSNotFound);
        expect(selectedIndexOf(menuView) == NSNotFound, "a menu without a delegate still highlights");

        [menu release];
        [recorder release];

        test_quirk_highlight_cleared_before_did_close();
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
