// Copyright (C) 2026 Lubos Dolezel
//
// NSLayoutGuide takes part in Auto Layout as a rectangle: constraints solve it and its frame is set,
// relative to the view that owns it (a non-zero bounds origin does not shift it). Expected values observed on macOS 26.7.3.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL) isFlipped { return YES; }
@end

static int failures;

static void expectRect(NSRect r, double x, double y, double w, double h, const char *what) {
    if (fabs(r.origin.x - x) > .01 || fabs(r.origin.y - y) > .01 ||
        fabs(r.size.width - w) > .01 || fabs(r.size.height - h) > .01) {
        fprintf(stderr, "FAIL: %s: got (%g,%g,%g,%g), expected (%g,%g,%g,%g)\n", what,
                r.origin.x, r.origin.y, r.size.width, r.size.height, x, y, w, h);
        failures++;
    }
}

static NSView *fixedView(NSView *parent) {
    NSView *view = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
    [view setTranslatesAutoresizingMaskIntoConstraints: NO];
    [parent addSubview: view];
    return view;
}

static void pinGuide(NSLayoutGuide *guide, NSView *owner, double x, double y, double w, double h) {
    [NSLayoutConstraint activateConstraints: @[
        [[guide leadingAnchor] constraintEqualToAnchor: [owner leadingAnchor] constant: x],
        [[guide topAnchor] constraintEqualToAnchor: [owner topAnchor] constant: y],
        [[guide widthAnchor] constraintEqualToConstant: w],
        [[guide heightAnchor] constraintEqualToConstant: h] ]];
}

static void rootCase(NSView *root, double guideY, double childY, const char *label) {
    NSLayoutGuide *guide = [[[NSLayoutGuide alloc] init] autorelease];
    [root addLayoutGuide: guide];
    NSView *child = fixedView(root);
    pinGuide(guide, root, 20, 30, 100, 50);
    [NSLayoutConstraint activateConstraints: @[
        [[child leadingAnchor] constraintEqualToAnchor: [guide leadingAnchor]],
        [[child topAnchor] constraintEqualToAnchor: [guide bottomAnchor] constant: 5],
        [[child widthAnchor] constraintEqualToConstant: 10],
        [[child heightAnchor] constraintEqualToConstant: 10] ]];
    expectRect([guide frame], 0, 0, 0, 0, "a guide's frame is empty before layout");
    [root layoutSubtreeIfNeeded];
    char what[80];
    snprintf(what, sizeof what, "%s: the guide's frame is solved", label);
    expectRect([guide frame], 20, guideY, 100, 50, what);
    snprintf(what, sizeof what, "%s: a view constrained to the guide", label);
    expectRect([child frame], 20, childY, 10, 10, what);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *root = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)] autorelease];
        rootCase(root, 220, 205, "unflipped root");

        NSView *flipped = [[[FlippedView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)] autorelease];
        rootCase(flipped, 30, 85, "flipped root");

        // A guide owned by a subview whose bounds have an origin.
        NSView *outer = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)] autorelease];
        NSView *inner = fixedView(outer);
        [inner setBoundsOrigin: NSMakePoint(7, 9)];
        [NSLayoutConstraint activateConstraints: @[
            [[inner leadingAnchor] constraintEqualToAnchor: [outer leadingAnchor] constant: 50],
            [[inner topAnchor] constraintEqualToAnchor: [outer topAnchor] constant: 40],
            [[inner widthAnchor] constraintEqualToConstant: 200],
            [[inner heightAnchor] constraintEqualToConstant: 100] ]];
        NSLayoutGuide *innerGuide = [[[NSLayoutGuide alloc] init] autorelease];
        [inner addLayoutGuide: innerGuide];
        [NSLayoutConstraint activateConstraints: @[
            [[innerGuide centerXAnchor] constraintEqualToAnchor: [inner centerXAnchor]],
            [[innerGuide centerYAnchor] constraintEqualToAnchor: [inner centerYAnchor]],
            [[innerGuide widthAnchor] constraintEqualToConstant: 40],
            [[innerGuide heightAnchor] constraintEqualToConstant: 20] ]];
        [outer layoutSubtreeIfNeeded];
        expectRect([inner frame], 50, 160, 200, 100, "the owning view is placed");
        expectRect([innerGuide frame], 80, 40, 40, 20, "a guide's frame is measured from its owner's size, not its bounds origin");

        // A guide with no constraints on it is still given an (empty) rectangle.
        NSView *plain = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
        NSView *member = fixedView(plain);
        NSLayoutGuide *loose = [[[NSLayoutGuide alloc] init] autorelease];
        [plain addLayoutGuide: loose];
        [NSLayoutConstraint activateConstraints: @[
            [[member widthAnchor] constraintEqualToConstant: 10],
            [[member heightAnchor] constraintEqualToConstant: 10],
            [[member leadingAnchor] constraintEqualToAnchor: [plain leadingAnchor]],
            [[member topAnchor] constraintEqualToAnchor: [plain topAnchor]] ]];
        [plain layoutSubtreeIfNeeded];
        expectRect([member frame], 0, 90, 10, 10, "views lay out beside a guide with no constraints");
    }
    if (failures == 0) puts("PASS");
    return failures ? 1 : 0;
}
