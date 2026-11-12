// Copyright (C) 2026 Lubos Dolezel
// Checks the NSLayoutConstraint / NSLayoutAnchor models and how views hold
// constraints: anchors build constraints, keyed archives round-trip them,
// activation installs on the closest common ancestor and rejects items that
// share none, and -addConstraint:/-removeConstraint: activate/deactivate.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

static NSView *child(NSView *parent) {
    NSView *v = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
    [parent addSubview:v];
    return v;
}

int main(void) {
    @autoreleasepool {
        NSView *root = child(nil), *mid = child(root), *a = child(mid), *b = child(root);

        // Anchors carry item and attribute and build constraint objects.
        NSLayoutConstraint *c = [[a leftAnchor] constraintEqualToAnchor:[b leftAnchor] constant:12];
        CHECK([c firstItem] == a && [c secondItem] == b && [c constant] == 12);
        CHECK([c firstAttribute] == NSLayoutAttributeLeft && [c secondAttribute] == NSLayoutAttributeLeft);
        CHECK([c relation] == NSLayoutRelationEqual && [c multiplier] == 1);
        CHECK([c priority] == NSLayoutPriorityRequired);
        CHECK(![c isActive]);
        NSLayoutConstraint *w = [[a widthAnchor] constraintGreaterThanOrEqualToConstant:30];
        CHECK([w firstItem] == a && [w secondItem] == nil && [w relation] == NSLayoutRelationGreaterThanOrEqual && [w constant] == 30);
        NSLayoutConstraint *ratio = [[a heightAnchor] constraintEqualToAnchor:[mid heightAnchor] multiplier:2 constant:1];
        CHECK([ratio multiplier] == 2 && [ratio constant] == 1 && [ratio firstAttribute] == NSLayoutAttributeHeight);

        // Keyed archive round trip keeps the description.
        [c setIdentifier:@"left"];
        [c setPriority:750];
        NSMutableData *data = [NSMutableData data];
        NSKeyedArchiver *ar = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
        [ar encodeObject:c forKey:@"c"];
        [ar finishEncoding];
        [ar release];
        NSKeyedUnarchiver *un = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
        NSLayoutConstraint *d = [un decodeObjectForKey:@"c"];
        [un finishDecoding];
        [un release];
        CHECK(d != nil && [d constant] == 12 && [d firstAttribute] == NSLayoutAttributeLeft && [d relation] == NSLayoutRelationEqual);
        CHECK([d priority] == 750 && [[d identifier] isEqualToString:@"left"]);

        // Activation installs on the closest common ancestor.
        [c setActive:YES];
        CHECK([c isActive] && [[root constraints] count] == 1 && [[a constraints] count] == 0);
        CHECK([[root constraints] objectAtIndex:0] == c);
        [c setActive:YES];
        CHECK([[root constraints] count] == 1);
        [c setActive:NO];
        CHECK(![c isActive] && [[root constraints] count] == 0);

        // One item: installed on the item itself. An ancestor pair: on the ancestor.
        [w setActive:YES];
        CHECK([[a constraints] count] == 1);
        [w setActive:NO];
        NSLayoutConstraint *up = [NSLayoutConstraint constraintWithItem:a attribute:NSLayoutAttributeLeft
                                                              relatedBy:NSLayoutRelationEqual
                                                                 toItem:root attribute:NSLayoutAttributeLeft
                                                             multiplier:1 constant:0];
        [NSLayoutConstraint activateConstraints:[NSArray arrayWithObject:up]];
        CHECK([[root constraints] count] == 1);
        [NSLayoutConstraint deactivateConstraints:[NSArray arrayWithObject:up]];
        CHECK([[root constraints] count] == 0);

        // -addConstraint: activates with that view as owner; -removeConstraint: deactivates.
        [mid addConstraint:ratio];
        CHECK([ratio isActive] && [[mid constraints] containsObject:ratio]);
        [mid addConstraint:ratio];
        CHECK([[mid constraints] count] == 1);
        [mid removeConstraint:ratio];
        CHECK(![ratio isActive] && [[mid constraints] count] == 0);
        [mid removeConstraint:ratio];
        [mid addConstraints:[NSArray arrayWithObjects:ratio, w, nil]];
        CHECK([[mid constraints] count] == 2);
        [mid removeConstraints:[mid constraints]];
        CHECK([[mid constraints] count] == 0 && ![w isActive]);

        // Items with no common ancestor raise and leave the constraint inactive.
        NSView *other = child(nil);
        NSLayoutConstraint *bad = [[a leftAnchor] constraintEqualToAnchor:[other leftAnchor]];
        BOOL raised = NO;
        @try { [bad setActive:YES]; } @catch (NSException *e) { raised = [[e name] isEqualToString:NSInvalidArgumentException]; }
        CHECK(raised && ![bad isActive]);

        NSDictionary *bound = NSDictionaryOfVariableBindings(a, b);
        CHECK([bound count] == 2 && [bound objectForKey:@"a"] == a && [bound objectForKey:@"b"] == b);
    }
    printf(failures ? "FAILED\n" : "PASS\n");
    return failures != 0;
}
