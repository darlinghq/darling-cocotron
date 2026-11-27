// Copyright (C) 2026 Lubos Dolezel
//
// Laying out a subtree uses the constraints installed on its views. A constraint owned by a view outside the
// subtree (here the common ancestor of a subtree view and a view beside it) does not take part when the subtree
// is laid out on its own, and takes part when the layout starts at the ancestor. A constraint installed on a
// subtree view that refers to a view outside the subtree is illegal: macOS 26.7.3 raises while laying out (an
// NSGenericException, "Unable to install constraint on view"), so this test expects an exception for it and does
// not require the name.
// Build: clang -framework AppKit appkit-layout-foreign-constraint.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSView *top = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease];
    NSView *sub = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSView *inside = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    NSView *outside = [[[NSView alloc] initWithFrame: NSMakeRect(150, 0, 40, 40)] autorelease];
    [top addSubview: sub];
    [sub addSubview: inside];
    [top addSubview: outside];
    for (NSView *v in [NSArray arrayWithObjects: sub, inside, outside, nil])
        [v setTranslatesAutoresizingMaskIntoConstraints: NO];
    // inside is 30 wide; its left edge follows outside's left edge, which is not in sub's subtree.
    [[inside widthAnchor] constraintEqualToConstant: 30].active = YES;
    [[inside heightAnchor] constraintEqualToConstant: 10].active = YES;
    [[inside topAnchor] constraintEqualToAnchor: [sub topAnchor]].active = YES;
    [[inside leadingAnchor] constraintEqualToAnchor: [outside leadingAnchor]].active = YES;
    [[sub widthAnchor] constraintEqualToConstant: 100].active = YES;
    [[sub heightAnchor] constraintEqualToConstant: 100].active = YES;
    [[sub topAnchor] constraintEqualToAnchor: [top topAnchor]].active = YES;
    [[sub leadingAnchor] constraintEqualToAnchor: [top leadingAnchor]].active = YES;
    [[outside widthAnchor] constraintEqualToConstant: 40].active = YES;
    [[outside heightAnchor] constraintEqualToConstant: 40].active = YES;
    [[outside leadingAnchor] constraintEqualToAnchor: [top leadingAnchor] constant: 150].active = YES;
    [[outside topAnchor] constraintEqualToAnchor: [top topAnchor]].active = YES;

    @try {
        [sub layoutSubtreeIfNeeded];
        CHECK([inside frame].size.width == 30);
        [top layoutSubtreeIfNeeded];
        CHECK([inside frame].size.width == 30);
        CHECK([sub frame].size.width == 100 && [outside frame].size.width == 40);
    } @catch (NSException *e) {
        fprintf(stderr, "FAIL exception %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
        failures++;
    }
    // A constraint owned by sub that refers to outside is illegal; laying out raises.
    NSLayoutConstraint *illegal = [NSLayoutConstraint constraintWithItem: inside attribute: NSLayoutAttributeTrailing
            relatedBy: NSLayoutRelationEqual toItem: outside attribute: NSLayoutAttributeTrailing multiplier: 1 constant: 0];
    [sub addConstraint: illegal];
    BOOL raised = NO;
    @try {
        [sub layoutSubtreeIfNeeded];
    } @catch (NSException *e) {
        raised = YES;
    }
    CHECK(raised);
    if (failures == 0)
        printf("PASS appkit-layout-foreign-constraint\n");
    [pool release];
    return failures != 0;
}
