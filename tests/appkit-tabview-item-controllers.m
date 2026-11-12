// Copyright (C) 2026 Lubos Dolezel
//
// NSTabViewItem identifier replacement, tab ownership during automatic selection,
// and view controller support:
//  - setIdentifier: retains the new identifier
//  - the tab view is set on an item before the delegate hears about its selection
//  - +tabViewItemWithViewController: loads the view lazily, once
//  - replacing or clearing the controller drops the loaded view and an initial
//    first responder that is that view or inside it
//  - a controller that replaces itself while its view loads: the replacement's
//    view is used
//  - a controller whose view asks the item for its view again gets nil, not
//    unbounded recursion; an exception while loading leaves the item usable
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface LoadController : NSViewController {
    NSView *_content;
    NSTabViewItem *_item;
    NSViewController *_replacement;
    BOOL _replaceDuringLoad;
    BOOL _reenter;
    BOOL _throwOnce;
    int _loads;
    BOOL _reentrantViewWasNil;
}
@property(assign) NSView *content;
@property(assign) NSTabViewItem *item;
@property(assign) NSViewController *replacement;
@property(assign) BOOL replaceDuringLoad, reenter, throwOnce;
@property(assign) int loads;
@property(assign) BOOL reentrantViewWasNil;
@end
@implementation LoadController
@synthesize content = _content, item = _item, replacement = _replacement, replaceDuringLoad = _replaceDuringLoad, reenter = _reenter, throwOnce = _throwOnce, loads = _loads, reentrantViewWasNil = _reentrantViewWasNil;
- (NSView *)view {
    self.loads++;
    if (self.reenter) {
        self.reenter = NO;
        self.reentrantViewWasNil = [self.item view] == nil;
    }
    if (self.throwOnce) {
        self.throwOnce = NO;
        [NSException raise:@"LoadFailed" format:@"expected"];
    }
    if (self.replaceDuringLoad) {
        self.replaceDuringLoad = NO;
        [self.item setViewController:self.replacement];
    }
    return self.content;
}
@end

@interface OwnershipDelegate : NSObject <NSTabViewDelegate> {
    BOOL _sawTabViewOnSelect;
}
@property(assign) BOOL sawTabViewOnSelect;
@end
@implementation OwnershipDelegate
@synthesize sawTabViewOnSelect = _sawTabViewOnSelect;
- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)item {
    self.sawTabViewOnSelect = [item tabView] == tabView;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // Identifier replacement.
        NSTabViewItem *plain = [[NSTabViewItem alloc] initWithIdentifier:@"one"];
        NSString *two = [NSString stringWithFormat:@"two-%d", 2];
        [plain setIdentifier:two];
        CHECK([[plain identifier] isEqual:@"two-2"]);
        [plain setIdentifier:nil];
        CHECK([plain identifier] == nil);

        // Ownership before automatic selection callbacks.
        NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        OwnershipDelegate *delegate = [OwnershipDelegate new];
        [tabView setDelegate:delegate];
        NSTabViewItem *first = [[NSTabViewItem alloc] initWithIdentifier:@"first"];
        [tabView addTabViewItem:first];
        CHECK(delegate.sawTabViewOnSelect);
        delegate.sawTabViewOnSelect = NO;
        NSTabViewItem *inserted = [[NSTabViewItem alloc] initWithIdentifier:@"inserted"];
        [tabView removeTabViewItem:first];
        [tabView insertTabViewItem:inserted atIndex:0];
        CHECK(delegate.sawTabViewOnSelect);

        // Lazy loading from a view controller.
        NSView *a = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        NSView *b = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
        LoadController *ca = [LoadController new], *cb = [LoadController new];
        ca.content = a; cb.content = b;
        NSTabViewItem *item = [NSTabViewItem tabViewItemWithViewController:ca];
        ca.item = item; cb.item = item;
        CHECK([item viewController] == ca);
        CHECK(ca.loads == 0);
        CHECK([item view] == a && ca.loads == 1);
        CHECK([item view] == a && ca.loads == 1);
        CHECK([item initialFirstResponder] == a);
        [item setViewController:ca];
        CHECK(ca.loads == 1);

        // Replacing the controller drops the loaded view.
        NSView *inner = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 5, 5)];
        [a addSubview:inner];
        [item setInitialFirstResponder:inner];
        [item setViewController:cb];
        CHECK([item initialFirstResponder] == nil || [item initialFirstResponder] == b);
        CHECK([item view] == b && cb.loads == 1);
        [item setViewController:nil];
        CHECK([item view] == nil && [item initialFirstResponder] == nil);

        // The controller replaces itself while its view loads.
        LoadController *swapper = [LoadController new];
        swapper.item = item; swapper.content = a;
        swapper.replacement = cb; swapper.replaceDuringLoad = YES;
        [item setViewController:swapper];
        CHECK([item view] == b);
        CHECK([item viewController] == cb);

        // Reentry and exceptions while loading.
        LoadController *odd = [LoadController new];
        odd.item = item; odd.content = a; odd.reenter = YES; odd.throwOnce = YES;
        [item setViewController:odd];
        BOOL raised = NO;
        @try { [item view]; } @catch (NSException *e) { raised = [[e name] isEqual:@"LoadFailed"]; }
        CHECK(raised);
        CHECK(odd.reentrantViewWasNil);
        CHECK([item view] == a);

        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
