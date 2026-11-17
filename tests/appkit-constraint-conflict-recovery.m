// Copyright (C) 2026 Lubos Dolezel
// When required constraints cannot all be satisfied, Auto Layout breaks one of them and carries on
// laying out the rest of the views; the conflict does not stop the layout. Here one view is
// pinned by its frame (autoresizing mask) and a constraint demands a position for the view next to
// it that contradicts another required constraint.
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static BOOL near(CGFloat a, CGFloat b) { return fabs(a - b) < 0.01; }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSView *root = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)] autorelease];
        NSView *pinned = [[[NSView alloc] initWithFrame: NSMakeRect(50, 50, 100, 40)] autorelease];
        NSView *a = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        NSView *other = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
        [a setTranslatesAutoresizingMaskIntoConstraints: NO];
        [other setTranslatesAutoresizingMaskIntoConstraints: NO];
        [root addSubview: pinned];
        [root addSubview: a];
        [root addSubview: other];

        [NSLayoutConstraint activateConstraints: @[
            // a sits 10 points right of the pinned view: x = 160.
            [[a leftAnchor] constraintEqualToAnchor: [pinned rightAnchor] constant: 10],
            // Contradicts the one above: one of the two is broken (macOS keeps this one, x = 5).
            [[a leftAnchor] constraintEqualToAnchor: [root leftAnchor] constant: 5],
            [[a widthAnchor] constraintEqualToConstant: 60],
            [[a heightAnchor] constraintEqualToConstant: 20],
            [[a topAnchor] constraintEqualToAnchor: [root topAnchor] constant: 20],
            // A view that is laid out regardless of the conflict.
            [[other leftAnchor] constraintEqualToAnchor: [root leftAnchor] constant: 30],
            [[other topAnchor] constraintEqualToAnchor: [root topAnchor] constant: 100],
            [[other widthAnchor] constraintEqualToConstant: 70],
            [[other heightAnchor] constraintEqualToConstant: 25],
        ]];
        [root layoutSubtreeIfNeeded];

        NSRect fa = [a frame], fo = [other frame];
        CHECK(near(fa.origin.x, 160) || near(fa.origin.x, 5));    // which one is broken is the engine's choice
        CHECK(near(fa.size.width, 60) && near(fa.size.height, 20));
        CHECK(near(fa.origin.y, 260));    // 300 - 20 - 20, y grows upwards in an unflipped root
        CHECK(near(fo.origin.x, 30) && near(fo.size.width, 70) && near(fo.size.height, 25));
        CHECK(near(fo.origin.y, 175));    // 300 - 100 - 25
        CHECK(NSEqualRects([pinned frame], NSMakeRect(50, 50, 100, 40)));
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
