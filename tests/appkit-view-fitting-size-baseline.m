// Copyright (C) 2026 Lubos Dolezel
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

// -[NSView fittingSize], baseline anchors and alignment rectangles in Auto Layout.
//
// Observed on macOS 26.7.3 and Mojave 10.14.4 (both agree): fittingSize of a view
// without constraints or intrinsic size is 0x0, whatever its frame; it is the
// smallest size the view's constraints allow and leaves the frame alone; a control
// is as wide and tall as its intrinsic size plus its alignment insets; constraints
// between a view and its subview refer to the alignment rectangles, so a subview's
// intrinsic size plus the constants gives the superview's fitting size; the first and
// last baseline offsets of a text control add up to its intrinsic height; two views
// whose first baseline anchors are constrained equal have the same baseline.

static int failures;

static void expectTrue(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }

static NSView *pinned(NSView *parent, NSView *child, CGFloat inset) {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [parent addSubview: child];
    [child.leadingAnchor constraintEqualToAnchor: parent.leadingAnchor constant: inset].active = YES;
    [child.trailingAnchor constraintEqualToAnchor: parent.trailingAnchor constant: -inset].active = YES;
    [child.topAnchor constraintEqualToAnchor: parent.topAnchor constant: inset].active = YES;
    [child.bottomAnchor constraintEqualToAnchor: parent.bottomAnchor constant: -inset].active = YES;
    return parent;
}

@interface InsetView : NSView
@end
@implementation InsetView
- (NSEdgeInsets) alignmentRectInsets {
    return NSEdgeInsetsMake(3, 5, 7, 9);
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *empty = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 50)];
        NSSize size = [empty fittingSize];
        expectTrue(near(size.width, 0) && near(size.height, 0), "a view without constraints fits 0x0 whatever its frame");
        expectTrue(near(NSWidth(empty.frame), 100) && near(NSHeight(empty.frame), 50), "fittingSize leaves the frame alone");

        NSView *parent = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 500, 500)];
        parent.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *child = [NSView new];
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [parent addSubview: child];
        [child.widthAnchor constraintEqualToConstant: 80].active = YES;
        [child.heightAnchor constraintEqualToConstant: 30].active = YES;
        [child.leadingAnchor constraintEqualToAnchor: parent.leadingAnchor constant: 10].active = YES;
        [child.trailingAnchor constraintEqualToAnchor: parent.trailingAnchor constant: -12].active = YES;
        [child.topAnchor constraintEqualToAnchor: parent.topAnchor constant: 7].active = YES;
        [child.bottomAnchor constraintEqualToAnchor: parent.bottomAnchor constant: -9].active = YES;
        size = [parent fittingSize];
        expectTrue(near(size.width, 102) && near(size.height, 46), "fitting size of a superview of a pinned 80x30 subview");
        expectTrue(near(NSWidth(parent.frame), 500) && near(NSHeight(parent.frame), 500), "the superview keeps its 500x500 frame");

        NSView *atLeast = [NSView new];
        atLeast.translatesAutoresizingMaskIntoConstraints = NO;
        NSView *sub = [NSView new];
        sub.translatesAutoresizingMaskIntoConstraints = NO;
        [atLeast addSubview: sub];
        [sub.widthAnchor constraintGreaterThanOrEqualToConstant: 50].active = YES;
        [sub.leadingAnchor constraintEqualToAnchor: atLeast.leadingAnchor].active = YES;
        [sub.trailingAnchor constraintEqualToAnchor: atLeast.trailingAnchor].active = YES;
        [sub.topAnchor constraintEqualToAnchor: atLeast.topAnchor].active = YES;
        [sub.bottomAnchor constraintEqualToAnchor: atLeast.bottomAnchor].active = YES;
        size = [atLeast fittingSize];
        expectTrue(near(size.width, 50) && near(size.height, 0), "a width >= 50 constraint gives 50, an unconstrained height 0");

        // A control is its intrinsic size plus its alignment insets.
        NSTextField *label = [NSTextField labelWithString: @"Hello"];
        NSSize intrinsic = [label intrinsicContentSize];
        NSEdgeInsets insets = [label alignmentRectInsets];
        size = [label fittingSize];
        expectTrue(near(size.width, intrinsic.width + insets.left + insets.right) &&
                           near(size.height, intrinsic.height + insets.top + insets.bottom),
                   "a label fits its intrinsic size plus its alignment insets");

        // Constraints between a view and its subview use alignment rectangles.
        NSButton *button = [NSButton buttonWithTitle: @"Button" target: nil action: nil];
        NSView *container = [NSView new];
        container.translatesAutoresizingMaskIntoConstraints = NO;
        pinned(container, button, 8);
        intrinsic = [button intrinsicContentSize];
        size = [container fittingSize];
        expectTrue(near(size.width, intrinsic.width + 16) && near(size.height, intrinsic.height + 16),
                   "a container fits the subview's intrinsic (alignment rect) size plus the constants");

        // Baseline offsets of text controls add up to the intrinsic height.
        NSTextField *small = [NSTextField labelWithString: @"Small"];
        small.font = [NSFont systemFontOfSize: 11];
        NSTextField *large = [NSTextField labelWithString: @"Large"];
        large.font = [NSFont systemFontOfSize: 24];
        NSTextField *field = [NSTextField textFieldWithString: @"edit"];
        NSButton *check = [NSButton checkboxWithTitle: @"Check" target: nil action: nil];
        NSView *texts[] = {small, large, label, field, check, button};
        const char *names[] = {"small label", "large label", "label", "text field", "checkbox", "push button"};
        for (int i = 0; i < 6; i++) {
            CGFloat top = [texts[i] firstBaselineOffsetFromTop];
            CGFloat bottom = [texts[i] lastBaselineOffsetFromBottom];
            char what[96];
            snprintf(what, sizeof what, "%s: baseline offsets add up to the intrinsic height", names[i]);
            expectTrue(top > 0 && bottom > 0 && near(top + bottom, [texts[i] intrinsicContentSize].height), what);
        }
        expectTrue([large firstBaselineOffsetFromTop] > [small firstBaselineOffsetFromTop], "a larger font has its baseline lower");
        expectTrue(near([[NSView new] firstBaselineOffsetFromTop], 0) && near([[NSView new] lastBaselineOffsetFromBottom], 0),
                   "a view without text has baseline offsets of 0");
        expectTrue(near([small baselineOffsetFromBottom], [small lastBaselineOffsetFromBottom]),
                   "baselineOffsetFromBottom is the last baseline offset");

        // Two labels aligned on their first baselines.
        NSView *row = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        small.translatesAutoresizingMaskIntoConstraints = NO;
        large.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview: small];
        [row addSubview: large];
        [small.leadingAnchor constraintEqualToAnchor: row.leadingAnchor].active = YES;
        [large.leadingAnchor constraintEqualToAnchor: small.trailingAnchor constant: 10].active = YES;
        [large.topAnchor constraintEqualToAnchor: row.topAnchor constant: 20].active = YES;
        [small.firstBaselineAnchor constraintEqualToAnchor: large.firstBaselineAnchor].active = YES;
        [row layoutSubtreeIfNeeded];
        // The baseline's y in the row (not flipped): the top of the alignment rect less the offset.
        CGFloat smallBase = NSMaxY(small.frame) - small.alignmentRectInsets.top - [small firstBaselineOffsetFromTop];
        CGFloat largeBase = NSMaxY(large.frame) - large.alignmentRectInsets.top - [large firstBaselineOffsetFromTop];
        expectTrue(near(smallBase, largeBase), "first baseline anchors align the baselines of two labels");
        expectTrue(near(NSMaxY(large.frame) - large.alignmentRectInsets.top, 100 - 20), "the large label's top is 20 below the row's top");

        NSView *lastRow = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 100)];
        NSTextField *a = [NSTextField labelWithString: @"A"];
        a.font = [NSFont systemFontOfSize: 11];
        NSTextField *b = [NSTextField labelWithString: @"B"];
        b.font = [NSFont systemFontOfSize: 24];
        a.translatesAutoresizingMaskIntoConstraints = NO;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [lastRow addSubview: a];
        [lastRow addSubview: b];
        [a.leadingAnchor constraintEqualToAnchor: lastRow.leadingAnchor].active = YES;
        [b.leadingAnchor constraintEqualToAnchor: a.trailingAnchor].active = YES;
        [b.bottomAnchor constraintEqualToAnchor: lastRow.bottomAnchor constant: -10].active = YES;
        [a.lastBaselineAnchor constraintEqualToAnchor: b.lastBaselineAnchor].active = YES;
        [lastRow layoutSubtreeIfNeeded];
        CGFloat aLast = a.frame.origin.y + a.alignmentRectInsets.bottom + [a lastBaselineOffsetFromBottom];
        CGFloat bLast = b.frame.origin.y + b.alignmentRectInsets.bottom + [b lastBaselineOffsetFromBottom];
        expectTrue(near(aLast, bLast), "last baseline anchors align the last baselines of two labels");

        // Constraints refer to the alignment rectangle, not the frame.
        NSView *host = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 200, 100)];
        InsetView *inset = [InsetView new];
        inset.translatesAutoresizingMaskIntoConstraints = NO;
        [host addSubview: inset];
        [inset.leadingAnchor constraintEqualToAnchor: host.leadingAnchor].active = YES;
        [inset.topAnchor constraintEqualToAnchor: host.topAnchor].active = YES;
        [inset.widthAnchor constraintEqualToConstant: 50].active = YES;
        [inset.heightAnchor constraintEqualToConstant: 20].active = YES;
        [host layoutSubtreeIfNeeded];
        NSRect frame = inset.frame;
        expectTrue(near(frame.origin.x, -5) && near(frame.size.width, 64), "the frame extends the alignment rect by the left and right insets");
        expectTrue(near(frame.size.height, 30) && near(NSMaxY(frame), 103), "the frame extends the alignment rect by the top and bottom insets");
        NSRect aligned = [inset alignmentRectForFrame: frame];
        expectTrue(near(aligned.origin.x, 0) && near(aligned.size.width, 50) && near(NSMaxY(aligned), 100) && near(aligned.size.height, 20),
                   "the alignment rect is where the constraints put it");
        size = [inset fittingSize];
        expectTrue(near(size.width, 50 + 14) && near(size.height, 20 + 10), "fitting size of a view with alignment insets is its frame size");
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
