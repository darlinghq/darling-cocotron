// Copyright (C) 2026 Lubos Dolezel
//
// A window is sized to fit the Auto Layout constraints of its content view. The window resists
// resizing at NSLayoutPriorityWindowSizeStayPut (500): required constraints and constraints above 500
// resize it, also past -contentMinSize and -contentMaxSize; lower priorities leave it alone; inequality
// constraints only resize it when the current size violates them. The top left corner stays put, and
// the resize happens in -layoutIfNeeded or when the window is shown, not in the content view's own
// -layoutSubtreeIfNeeded. Expected values observed on Mac OS X 10.14.4 and macOS 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSWindow *makeWindow(NSSize s)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, s.width, s.height)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:NO];
    return w;
}

static NSView *addChild(NSWindow *w, CGFloat cw, CGFloat ch, NSLayoutRelation rel, float prio)
{
    NSView *c = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    NSView *cv = w.contentView;
    c.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:c];
    [cv addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[c]|" options:0 metrics:nil views:@{@"c":c}]];
    [cv addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[c]|" options:0 metrics:nil views:@{@"c":c}]];
    NSLayoutConstraint *k = [NSLayoutConstraint constraintWithItem:c attribute:NSLayoutAttributeWidth relatedBy:rel toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:cw];
    k.priority = prio; [c addConstraint:k];
    k = [NSLayoutConstraint constraintWithItem:c attribute:NSLayoutAttributeHeight relatedBy:rel toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:ch];
    k.priority = prio; [c addConstraint:k];
    return c;
}

static void spin(void)
{
    NSDate *d = [NSDate dateWithTimeIntervalSinceNow:0.3];
    while ([d timeIntervalSinceNow] > 0) {
        NSEvent *e = [NSApp nextEventMatchingMask:NSUIntegerMax untilDate:d inMode:NSDefaultRunLoopMode dequeue:YES];
        if (e) [NSApp sendEvent:e];
    }
}

static BOOL contentIs(NSWindow *w, CGFloat cw, CGFloat ch)
{
    NSSize s = [w contentRectForFrameRect:w.frame].size;
    if (s.width != cw || s.height != ch) fprintf(stderr, "  content is %gx%g, expected %gx%g\n", s.width, s.height, cw, ch);
    return s.width == cw && s.height == ch;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w;

        w = makeWindow(NSMakeSize(100, 100)); addChild(w, 300, 200, NSLayoutRelationEqual, 1000);
        CGFloat top = NSMaxY(w.frame);
        [w layoutIfNeeded];
        CHECK(contentIs(w, 300, 200));
        CHECK(NSMaxY(w.frame) == top && w.frame.origin.x == 100);
        [w setContentSize:NSMakeSize(500, 500)]; [w layoutIfNeeded];
        CHECK(contentIs(w, 300, 200));

        w = makeWindow(NSMakeSize(100, 100)); addChild(w, 300, 200, NSLayoutRelationEqual, 1000);
        [w.contentView layoutSubtreeIfNeeded];
        CHECK(contentIs(w, 100, 100)); // the content view alone does not resize its window

        w = makeWindow(NSMakeSize(600, 500)); addChild(w, 300, 200, NSLayoutRelationEqual, 1000);
        [w orderFront:nil]; spin();
        CHECK(contentIs(w, 300, 200));

        w = makeWindow(NSMakeSize(100, 100)); w.contentMinSize = NSMakeSize(400, 300);
        addChild(w, 300, 200, NSLayoutRelationEqual, 1000); [w orderFront:nil]; spin();
        CHECK(contentIs(w, 300, 200));
        w = makeWindow(NSMakeSize(100, 100)); w.contentMaxSize = NSMakeSize(250, 150);
        addChild(w, 300, 200, NSLayoutRelationEqual, 1000); [w orderFront:nil]; spin();
        CHECK(contentIs(w, 300, 200));

        float prios[] = {250, 499, 501, 600};
        for (int i = 0; i < 4; i++) {
            w = makeWindow(NSMakeSize(100, 100)); addChild(w, 300, 200, NSLayoutRelationEqual, prios[i]);
            [w orderFront:nil]; spin();
            if (prios[i] < 500) CHECK(contentIs(w, 100, 100)); else CHECK(contentIs(w, 300, 200));
        }

        w = makeWindow(NSMakeSize(100, 100)); addChild(w, 300, 200, NSLayoutRelationGreaterThanOrEqual, 1000);
        [w orderFront:nil]; spin(); CHECK(contentIs(w, 300, 200));
        w = makeWindow(NSMakeSize(600, 500)); addChild(w, 300, 200, NSLayoutRelationGreaterThanOrEqual, 1000);
        [w orderFront:nil]; spin(); CHECK(contentIs(w, 600, 500));
        w = makeWindow(NSMakeSize(600, 500)); addChild(w, 300, 200, NSLayoutRelationLessThanOrEqual, 1000);
        [w orderFront:nil]; spin(); CHECK(contentIs(w, 300, 200));

        // A constraint changed after the window is shown resizes it again.
        w = makeWindow(NSMakeSize(100, 100)); NSView *c = addChild(w, 300, 200, NSLayoutRelationEqual, 1000);
        [w orderFront:nil]; spin();
        for (NSLayoutConstraint *k in c.constraints) if (k.firstAttribute == NSLayoutAttributeWidth) k.constant = 450;
        spin(); CHECK(contentIs(w, 450, 200));

        // Constraints on the content view itself.
        w = makeWindow(NSMakeSize(100, 100)); NSView *cv = w.contentView;
        [cv addConstraint:[NSLayoutConstraint constraintWithItem:cv attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:320]];
        [cv addConstraint:[NSLayoutConstraint constraintWithItem:cv attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:220]];
        [w orderFront:nil]; spin(); CHECK(contentIs(w, 320, 220));
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
