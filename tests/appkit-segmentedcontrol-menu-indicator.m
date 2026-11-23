// Copyright (C) 2026 Lubos Dolezel
//
// -[NSSegmentedControl setShowsMenuIndicator:forSegment:] and showsMenuIndicatorForSegment:
// (macOS 10.13). The documentation gives each a signature (a BOOL and a segment index) and
// nothing more: no description, default, effect on drawing or behavior for an index out of range.
// Observed on macOS 26.7.3 and 10.14.4 (x86_64 and i386; mac-probes/cristim/batch12a/p769.m): the default
// is NO, an index out of range raises NSRangeException (also for a control with no segment), a segment's menu
// (set or removed), tag, label, enabled and selected state are independent of it, segments added later start
// from NO (also after the count was lowered and raised again), and an archive carries it in the segment item
// under the key NSSegmentItemShowMenuIndicator.
// Build: clang -fobjc-arc -framework AppKit appkit-segmentedcontrol-menu-indicator.m
// Not covered: any indicator being drawn (the value is only stored). On master the selectors do
// not exist: with ARC the test does not compile against master's header, without ARC the first
// call raises an unrecognized selector.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <objc/message.h>

// Stands in for the object in a keyed archive: it writes only the one key (as an archive of a program that
// does not know the property would not have it, and as macOS writes it), and is decoded as the class under test.
static NSString *standInKey;
static BOOL standInValue;
@interface ArchivedStandIn : NSObject <NSCoding>
@end
@implementation ArchivedStandIn
- (void)encodeWithCoder:(NSCoder *)coder {
    if (standInKey != nil)
        [coder encodeBool:standInValue forKey:standInKey];
}
- (id)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static id decodedAs(Class cls, NSString *key, BOOL value) {
    standInKey = key;
    standInValue = value;
    NSMutableData *data = [NSMutableData data];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver encodeObject:[ArchivedStandIn new] forKey:@"root"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setClass:cls forClassName:@"ArchivedStandIn"];
    return [unarchiver decodeObjectForKey:@"root"];
}

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
        CHECK(![control showsMenuIndicatorForSegment:i]);          // the default

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

    // independent of the segment's other properties
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

    // out of range raises
    CHECK(raisesRange(^{ (void)[control showsMenuIndicatorForSegment:4]; }));
    CHECK(raisesRange(^{ [control setShowsMenuIndicator:YES forSegment:-1]; }));
}

int main(void) {
    @autoreleasepool {
        // the archive key of a segment item (NSSegmentItem is the class macOS archives a segment as)
        Class itemClass = NSClassFromString(@"NSSegmentItem");
        BOOL (*indicator)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
        CHECK(!indicator(decodedAs(itemClass, nil, NO), @selector(showsMenuIndicator)));
        CHECK(indicator(decodedAs(itemClass, @"NSSegmentItemShowMenuIndicator", YES), @selector(showsMenuIndicator)));

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
