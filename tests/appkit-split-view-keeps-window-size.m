/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A window whose content view is a split view of two stacked panes keeps the size it was created
// with when the panes take part in Auto Layout: the pane with a required height (a control bar)
// keeps it and the other pane takes up the rest. The split view's own constraints must not ask
// the window for a size: macOS 26.7.3 (black-box observation) keeps a 674x447 content size and
// gives 375 points to the pane without a height constraint and 71 to the bar, whatever the frames
// the panes were added with (including empty ones).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(cond, ...) do { if (cond) printf("PASS "); else { printf("FAIL "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

static void spin(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event != nil)
            [NSApp sendEvent: event];
    }
}

static void addConstraint(NSView *bar, NSView *inner, NSLayoutAttribute attribute, NSLayoutAttribute other, CGFloat constant) {
    [bar addConstraint: [NSLayoutConstraint constraintWithItem: inner
                                                     attribute: attribute
                                                     relatedBy: NSLayoutRelationEqual
                                                        toItem: other == NSLayoutAttributeNotAnAttribute ? nil : bar
                                                     attribute: other
                                                    multiplier: 1
                                                      constant: constant]];
}

static void run(const char *name, NSRect topFrame, NSRect barFrame) {
    NSWindow *w = [[NSWindow alloc] initWithContentRect: NSMakeRect(200, 200, 674, 447)
                                              styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
    [w setReleasedWhenClosed: NO];
    NSSplitView *split = [[NSSplitView alloc] initWithFrame: NSMakeRect(0, 0, 674, 447)];
    [split setVertical: NO];
    [split setDividerStyle: NSSplitViewDividerStyleThin];
    NSView *top = [[NSView alloc] initWithFrame: topFrame];
    NSView *bar = [[NSView alloc] initWithFrame: barFrame];
    NSView *inner = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)];
    [inner setTranslatesAutoresizingMaskIntoConstraints: NO];
    [bar addSubview: inner];
    addConstraint(bar, inner, NSLayoutAttributeHeight, NSLayoutAttributeNotAnAttribute, 55);
    addConstraint(bar, inner, NSLayoutAttributeWidth, NSLayoutAttributeNotAnAttribute, 20);
    addConstraint(bar, inner, NSLayoutAttributeTop, NSLayoutAttributeTop, 8);
    addConstraint(bar, inner, NSLayoutAttributeBottom, NSLayoutAttributeBottom, -8);
    addConstraint(bar, inner, NSLayoutAttributeLeading, NSLayoutAttributeLeading, 0);
    [top setTranslatesAutoresizingMaskIntoConstraints: NO];
    [bar setTranslatesAutoresizingMaskIntoConstraints: NO];
    [split addSubview: top];
    [split addSubview: bar];
    [w setContentView: split];
    [w orderFrontRegardless];
    spin(0.8);

    NSSize content = [w contentRectForFrameRect: [w frame]].size;
    CHECK(content.width == 674 && content.height == 447, "%s: content size stays 674x447 (got %gx%g)", name, content.width, content.height);
    CHECK([top frame].size.height == 375, "%s: the pane without a height constraint takes the rest (got %g)", name, [top frame].size.height);
    CHECK([bar frame].size.height == 71, "%s: the bar keeps its required height (got %g)", name, [bar frame].size.height);
    [w close];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp finishLaunching];
        run("frames 376/71", NSMakeRect(0, 0, 674, 376), NSMakeRect(0, 377, 674, 71));
        run("empty frames", NSZeroRect, NSZeroRect);
        run("equal frames 71/71", NSMakeRect(0, 0, 674, 71), NSMakeRect(0, 72, 674, 71));
        run("frames 100/71", NSMakeRect(0, 0, 674, 100), NSMakeRect(0, 101, 674, 71));
    }
    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures != 0;
}
