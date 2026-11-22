// Copyright (C) 2026 Lubos Dolezel
//
// A menu tells its delegate that it is about to highlight an item with -menu:willHighlightItem:, before the
// highlight changes, with nil when no item is about to be highlighted
// (https://developer.apple.com/documentation/appkit/nsmenudelegate/menu(_:willhighlight:)). The method is
// optional, so a delegate without it, or a menu without a delegate, is not an error. The view that shows the menu is
// Darling's NSSubmenuView (private), driven through -setSelectedItemIndex:, the way its tracking loop highlights an
// item; the index counts the items shown, not the hidden ones. Needs no window server. Build without ARC.
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

static NSView *viewFor(NSMenu *menu) {
    return [[[NSClassFromString(@"NSSubmenuView") alloc] performSelector: @selector(initWithMenu:)
                                                              withObject: menu] autorelease];
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
    }
    printf(failures ? "FAIL (%d)\n" : "PASS\n", failures);
    return failures != 0;
}
