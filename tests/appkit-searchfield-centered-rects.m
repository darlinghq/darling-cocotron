// Copyright (C) 2026 Lubos Dolezel
//
// NSSearchField's layout methods (macOS 10.11): rectForSearchTextWhenCentered:,
// rectForSearchButtonWhenCentered:, rectForCancelButtonWhenCentered: and
// centersPlaceholder.
// - centersPlaceholder is NO on a new field, and setting it does not change
//   the layout;
// - each method returns, for both values of its argument, the rectangle that
//   the field's cell gives for the field's bounds (searchTextRectForBounds:,
//   searchButtonRectForBounds:, cancelButtonRectForBounds:), also with a
//   placeholder or text; the text widens with the field, the buttons keep
//   their size;
// - a subclass can call them on super, also on an instance that key-value
//   observing has subclassed, and the cell then puts the text and the search
//   button where the subclass says, the cancel button where it would anyway.
// The program passes unchanged on macOS 10.14.4 (i386) and 26.7.3 (x86_64).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

#define CHECK(cond) do { if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); failures++; } } while (0)

@interface TestSearchField : NSSearchField
@property (nonatomic, retain) NSString *observed;
@end

@implementation TestSearchField
- (NSRect) rectForSearchButtonWhenCentered: (BOOL) isCentered {
    NSRect r = [super rectForSearchButtonWhenCentered: isCentered];
    r.origin.x += 1;
    return r;
}
@end

static void checkField(NSSearchField *field, const char *what) {
    NSSearchFieldCell *cell = [field cell];
    NSRect bounds = [field bounds];
    NSRect text = [cell searchTextRectForBounds: bounds];
    NSRect button = [cell searchButtonRectForBounds: bounds];
    NSRect cancel = [cell cancelButtonRectForBounds: bounds];

    for (int centered = 0; centered < 2; centered++) {
        if (!NSEqualRects([field rectForSearchTextWhenCentered: centered], text)) {
            printf("FAIL: %s: text rect (centered %d) %s, cell %s\n", what, centered,
                   [NSStringFromRect([field rectForSearchTextWhenCentered: centered]) UTF8String], [NSStringFromRect(text) UTF8String]);
            failures++;
        }
        if (!NSEqualRects([field rectForSearchButtonWhenCentered: centered], button)) {
            printf("FAIL: %s: search button rect (centered %d) %s, cell %s\n", what, centered,
                   [NSStringFromRect([field rectForSearchButtonWhenCentered: centered]) UTF8String], [NSStringFromRect(button) UTF8String]);
            failures++;
        }
        if (!NSEqualRects([field rectForCancelButtonWhenCentered: centered], cancel)) {
            printf("FAIL: %s: cancel button rect (centered %d) %s, cell %s\n", what, centered,
                   [NSStringFromRect([field rectForCancelButtonWhenCentered: centered]) UTF8String], [NSStringFromRect(cancel) UTF8String]);
            failures++;
        }
    }
    // Inside the field, in order
    CHECK(NSContainsRect(bounds, button) && NSContainsRect(bounds, cancel));
    CHECK(NSMinX(button) < NSMinX(text) && NSMaxX(text) <= NSMaxX(cancel));
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSSearchField *field = [[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 200, 22)];
        CHECK([field respondsToSelector: @selector(rectForSearchTextWhenCentered:)]);
        CHECK([field respondsToSelector: @selector(rectForSearchButtonWhenCentered:)]);
        CHECK([field respondsToSelector: @selector(rectForCancelButtonWhenCentered:)]);
        CHECK(![field centersPlaceholder]);
        checkField(field, "200x22");

        NSRect plainText = [field rectForSearchTextWhenCentered: NO];
        NSRect plainButton = [field rectForSearchButtonWhenCentered: NO];
        NSRect plainCancel = [field rectForCancelButtonWhenCentered: NO];
        [field setCentersPlaceholder: YES];
        checkField(field, "centersPlaceholder");
        CHECK(NSEqualRects([field rectForSearchTextWhenCentered: YES], plainText));
        [field setPlaceholderString: @"Search"];
        checkField(field, "placeholder");
        [field setStringValue: @"abc"];
        checkField(field, "text");
        [field setCentersPlaceholder: NO];
        CHECK(![field centersPlaceholder]);

        {
            NSSearchField *wide = [[NSSearchField alloc] initWithFrame: NSMakeRect(0, 0, 300, 22)];
            CHECK(NSWidth([wide rectForSearchTextWhenCentered: NO]) == NSWidth(plainText) + 100);
            CHECK(NSEqualSizes([wide rectForSearchButtonWhenCentered: NO].size, plainButton.size));
            CHECK(NSEqualSizes([wide rectForCancelButtonWhenCentered: NO].size, plainCancel.size));
            CHECK(NSMinX([wide rectForCancelButtonWhenCentered: NO]) == NSMinX(plainCancel) + 100);
            [wide release];
        }

        NSSize sizes[] = { { 300, 22 }, { 120, 22 }, { 200, 30 } };
        for (int i = 0; i < 3; i++) {
            NSSearchField *f = [[NSSearchField alloc] initWithFrame: NSMakeRect(10, 10, sizes[i].width, sizes[i].height)];
            char what[32];
            snprintf(what, sizeof(what), "%gx%g", sizes[i].width, sizes[i].height);
            checkField(f, what);
            [f release];
        }

        // A subclass building on super, observed through key-value observing
        TestSearchField *sub = [[TestSearchField alloc] initWithFrame: NSMakeRect(0, 0, 200, 22)];
        NSObject *observer = [[NSObject alloc] init];
        [sub addObserver: observer forKeyPath: @"observed" options: 0 context: NULL];
        CHECK([sub class] == [TestSearchField class]);
        NSRect r = [sub rectForSearchButtonWhenCentered: YES];
        CHECK(NSMinX(r) == NSMinX(plainButton) + 1 && NSWidth(r) == NSWidth(plainButton));
        CHECK(NSEqualRects([[sub cell] searchButtonRectForBounds: [sub bounds]], r));
        CHECK(NSEqualRects([[sub cell] cancelButtonRectForBounds: [sub bounds]], plainCancel));
        CHECK(NSEqualRects([sub rectForSearchTextWhenCentered: NO], plainText));
        [sub removeObserver: observer forKeyPath: @"observed"];
        [observer release];
        [sub release];
        [field release];
    }

    if (failures)
        printf("FAIL: %d check(s) failed\n", failures);
    else
        printf("PASS\n");
    return failures ? 1 : 0;
}
