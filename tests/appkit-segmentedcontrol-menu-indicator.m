// Copyright (C) 2026 Lubos Dolezel
//
// -[NSSegmentedControl setShowsMenuIndicator:forSegment:] and showsMenuIndicatorForSegment:
// (macOS 10.13). The documentation gives each a signature (a BOOL and a segment index) and
// nothing more: no description, default, effect on drawing or behavior for an index out of range.
// Everything marked GUESS pins this implementation's choice, not a documented or measured value:
// the default is NO, an index out of range raises NSRangeException like the other per-segment
// properties, and a segment's menu, tag, label, enabled and selected state are independent of it.
// Build: clang -fobjc-arc -framework AppKit appkit-segmentedcontrol-menu-indicator.m
// Not covered: any indicator being drawn (the value is only stored). On master the selectors do
// not exist: with ARC the test does not compile against master's header, without ARC the first
// call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>

// the methods are macOS 10.13 API; the guest has them whatever the build's deployment target is
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

static int failures;
#define CHECK(c) do { if (!(c)) { \
    fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

// An application subclass whose setter wraps the superclass one (the failing receiver in a real
// application was a subclass).
@interface MySegmentedControl : NSSegmentedControl
- (void)setShowsMenuIndicator:(BOOL)showsMenuIndicator forSegment:(NSInteger)segment;
@end
@implementation MySegmentedControl
- (void)setShowsMenuIndicator:(BOOL)showsMenuIndicator forSegment:(NSInteger)segment {
    (void)[self showsMenuIndicatorForSegment:segment];
    [super setShowsMenuIndicator:showsMenuIndicator forSegment:segment];
}
@end

static BOOL raisesRange(void (^body)(void)) {
    @try { body(); } @catch (NSException *e) { return [[e name] isEqualToString:NSRangeException]; }
    return NO;
}

static void checkControl(NSSegmentedControl *control) {
    [control setSegmentCount:3];
    for (NSInteger i = 0; i < 3; i++)
        CHECK(![control showsMenuIndicatorForSegment:i]);          // GUESS: the default

    [control setShowsMenuIndicator:YES forSegment:1];
    CHECK([control showsMenuIndicatorForSegment:1]);
    CHECK(![control showsMenuIndicatorForSegment:0]);              // per segment
    CHECK(![control showsMenuIndicatorForSegment:2]);
    [control setShowsMenuIndicator:YES forSegment:2];
    [control setShowsMenuIndicator:NO forSegment:1];
    CHECK(![control showsMenuIndicatorForSegment:1]);
    CHECK([control showsMenuIndicatorForSegment:2]);
    [control setShowsMenuIndicator:NO forSegment:2];
    CHECK(![control showsMenuIndicatorForSegment:2]);

    // independent of the segment's other properties (GUESS)
    [control setShowsMenuIndicator:YES forSegment:0];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"M"];
    [control setMenu:menu forSegment:0];
    [control setTag:7 forSegment:0];
    [control setLabel:@"Zero" forSegment:0];
    [control setEnabled:NO forSegment:0];
    [control setSelected:YES forSegment:0];
    CHECK([control showsMenuIndicatorForSegment:0]);
    CHECK([control menuForSegment:0] == menu && [control tagForSegment:0] == 7);
    CHECK([[control labelForSegment:0] isEqualToString:@"Zero"]);
    CHECK(![control isEnabledForSegment:0] && [control isSelectedForSegment:0]);
    [control setShowsMenuIndicator:NO forSegment:0];
    CHECK([control menuForSegment:0] == menu && [control tagForSegment:0] == 7);
    CHECK(![control isEnabledForSegment:0] && [control isSelectedForSegment:0]);
    [control setMenu:nil forSegment:1];
    [control setShowsMenuIndicator:YES forSegment:1];
    [control setMenu:menu forSegment:1];
    CHECK([control showsMenuIndicatorForSegment:1]);

    // a segment added later starts with the default
    [control setSegmentCount:4];
    CHECK([control showsMenuIndicatorForSegment:1]);
    CHECK(![control showsMenuIndicatorForSegment:3]);

    // GUESS: out of range raises, as the other per-segment properties do
    CHECK(raisesRange(^{ (void)[control showsMenuIndicatorForSegment:4]; }));
    CHECK(raisesRange(^{ [control setShowsMenuIndicator:YES forSegment:-1]; }));
}

int main(void) {
    @autoreleasepool {
        CHECK([NSSegmentedControl instancesRespondToSelector:@selector(showsMenuIndicatorForSegment:)]);
        CHECK([NSSegmentedControl instancesRespondToSelector:@selector(setShowsMenuIndicator:forSegment:)]);

        NSSegmentedControl *plain = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        checkControl(plain);
        MySegmentedControl *mine = [[MySegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        checkControl(mine);

        // controls do not share the value
        NSSegmentedControl *first = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
        NSSegmentedControl *second = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(0, 0, 100, 24)];
        [first setSegmentCount:2];
        [second setSegmentCount:2];
        [first setShowsMenuIndicator:YES forSegment:0];
        CHECK(![second showsMenuIndicatorForSegment:0]);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
