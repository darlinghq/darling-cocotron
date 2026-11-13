// Copyright (C) 2026 Lubos Dolezel
// Visual format language parsing and the constraint update/layout passes.
// Needs Foundation's NSLayoutConstraint implementation.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL: %s (line %d)\n", #cond, __LINE__); failures++; } } while (0)

@interface PassView : NSView { @public NSMutableArray *log; NSString *name; } @end
@implementation PassView
- (void) updateConstraints { [log addObject: [name stringByAppendingString: @" update"]]; [super updateConstraints]; }
- (void) layout { [log addObject: [name stringByAppendingString: @" layout"]]; [super layout]; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *superview = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)] autorelease];
        NSView *a = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        NSView *b = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        [superview addSubview: a];
        [superview addSubview: b];
        NSDictionary *views = @{ @"a": a, @"b": b };

        NSArray *cs = [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-10-[a(50)]-8-[b]-12-|"
                                                              options: 0 metrics: nil views: views];
        CHECK([cs count] == 4);
        // QUIRK test (macOS 26.7.3): constraint order is a.leading, a.width, b.leading, super.trailing.
        NSLayoutConstraint *width = [cs objectAtIndex: 1];
        CHECK([width firstItem] == a && [width firstAttribute] == NSLayoutAttributeWidth);
        CHECK([width relation] == NSLayoutRelationEqual && [width secondItem] == nil && [width constant] == 50);
        NSLayoutConstraint *lead = [cs objectAtIndex: 0];
        CHECK([lead firstItem] == a && [lead firstAttribute] == NSLayoutAttributeLeading);
        CHECK([lead secondItem] == superview && [lead secondAttribute] == NSLayoutAttributeLeading && [lead constant] == 10);
        NSLayoutConstraint *gap = [cs objectAtIndex: 2];
        CHECK([gap firstItem] == b && [gap secondItem] == a && [gap constant] == 8);
        CHECK([gap firstAttribute] == NSLayoutAttributeLeading && [gap secondAttribute] == NSLayoutAttributeTrailing);
        NSLayoutConstraint *trail = [cs objectAtIndex: 3];
        CHECK([trail firstItem] == superview && [trail secondItem] == b && [trail constant] == 12);

        // Default spacing: 8 between views, 20 between a view and the superview.
        NSArray *ds = [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-[a]-[b]-|"
                                                              options: 0 metrics: nil views: views];
        CHECK([ds count] == 3);
        CHECK([[ds objectAtIndex: 0] constant] == 20 && [[ds objectAtIndex: 1] constant] == 8 && [[ds objectAtIndex: 2] constant] == 20);
        NSArray *dv = [NSLayoutConstraint constraintsWithVisualFormat: @"V:|-[a]-[b]-|"
                                                              options: 0 metrics: nil views: views];
        CHECK([dv count] == 3);
        CHECK([[dv objectAtIndex: 0] constant] == 20 && [[dv objectAtIndex: 1] constant] == 8 && [[dv objectAtIndex: 2] constant] == 20);

        // Metrics, relations, priorities, vertical orientation and alignment
        NSArray *vs = [NSLayoutConstraint constraintsWithVisualFormat: @"V:[a(>=h@750)]-[b]"
                                                              options: NSLayoutFormatAlignAllLeft
                                                              metrics: @{ @"h": @30 } views: views];
        NSLayoutConstraint *height = [vs objectAtIndex: 0];
        CHECK([height firstAttribute] == NSLayoutAttributeHeight);
        CHECK([height relation] == NSLayoutRelationGreaterThanOrEqual && [height constant] == 30 && [height priority] == 750);
        BOOL aligned = NO;
        for (NSLayoutConstraint *c in vs)
            if ([c firstAttribute] == NSLayoutAttributeLeft && [c secondAttribute] == NSLayoutAttributeLeft) aligned = YES;
        CHECK(aligned);

        // Malformed formats and unknown names raise
        BOOL raised = NO;
        @try { [NSLayoutConstraint constraintsWithVisualFormat: @"H:[nope]" options: 0 metrics: nil views: views]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString: NSInvalidArgumentException]; }
        CHECK(raised);
        raised = NO;
        @try { [NSLayoutConstraint constraintsWithVisualFormat: @"H:[a" options: 0 metrics: nil views: views]; }
        @catch (NSException *e) { raised = [[e name] isEqualToString: NSInvalidArgumentException]; }
        CHECK(raised);

        // Update and layout passes: constraint updates for the whole subtree, subviews first,
        // then layout from the superview down.
        NSMutableArray *log = [NSMutableArray array];
        PassView *parent = [[[PassView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
        PassView *child = [[[PassView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
        parent->log = child->log = log; parent->name = @"parent"; child->name = @"child";
        [parent addSubview: child];
        [parent setNeedsUpdateConstraints: YES];
        [child setNeedsUpdateConstraints: YES];
        [parent layoutSubtreeIfNeeded];
        NSArray *expected = @[@"child update", @"parent update", @"parent layout", @"child layout"];
        CHECK([log isEqualToArray: expected]);
        CHECK(![parent needsUpdateConstraints] && ![parent needsLayout] && ![child needsLayout]);
        [log removeAllObjects];
        [parent layoutSubtreeIfNeeded];
        CHECK([log count] == 0);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures ? 1 : 0;
}
