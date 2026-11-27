// Copyright (C) 2026 Lubos Dolezel
//
// -[NSView convertSize:fromView:] and -[NSView convertSize:toView:] between views whose coordinate systems differ
// in isFlipped. The documentation of convertSize:fromView:
// (https://developer.apple.com/documentation/appkit/nsview/convertsize(_:from:)) converts a size between
// coordinate systems; a size is a magnitude, so flipping the y axis must not change the sign of the height.
// Observed on macOS 26.7.3 (x86_64): a size converted between a flipped and an unflipped view, to or from the
// window (nil), or between two flipped views keeps its positive width and height; scaling by the bounds (the
// bounds of a view half the size of its frame makes sizes twice as large in the superview) applies to the
// magnitude only; a view without a window converts to or from nil unchanged.
// Build: clang -framework AppKit appkit-view-convert-size-flipped.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECK_SIZE(s, w, h) do { NSSize s_ = (s); if (fabs(s_.width - (w)) > 0.001 || fabs(s_.height - (h)) > 0.001) { \
    fprintf(stderr, "FAIL line %d: %g x %g, expected %g x %g\n", __LINE__, s_.width, s_.height, (double) (w), (double) (h)); failures++; } } while (0)

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL) isFlipped { return YES; }
@end

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];

    NSWindow *window = [[[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                                    styleMask: NSBorderlessWindowMask
                                                      backing: NSBackingStoreBuffered
                                                        defer: NO] autorelease];
    NSView *parent = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSView *flipped = [[[FlippedView alloc] initWithFrame: NSMakeRect(10, 10, 50, 50)] autorelease];
    NSView *innerFlipped = [[[FlippedView alloc] initWithFrame: NSMakeRect(0, 0, 20, 20)] autorelease];
    NSView *scaled = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 40, 40)] autorelease];
    [[window contentView] addSubview: parent];
    [parent addSubview: flipped];
    [flipped addSubview: innerFlipped];
    [parent addSubview: scaled];

    NSSize size = NSMakeSize(10, 20);
    CHECK_SIZE([flipped convertSize: size fromView: parent], 10, 20);
    CHECK_SIZE([flipped convertSize: size toView: parent], 10, 20);
    CHECK_SIZE([innerFlipped convertSize: size fromView: flipped], 10, 20);
    CHECK_SIZE([flipped convertSize: size toView: nil], 10, 20);
    CHECK_SIZE([flipped convertSize: size fromView: nil], 10, 20);
    CHECK_SIZE([parent convertSize: size toView: nil], 10, 20);

    [scaled setBounds: NSMakeRect(0, 0, 20, 20)];
    CHECK_SIZE([scaled convertSize: size toView: parent], 20, 40);
    CHECK_SIZE([scaled convertSize: size fromView: parent], 5, 10);
    [flipped setBounds: NSMakeRect(0, 0, 25, 25)];
    CHECK_SIZE([flipped convertSize: size toView: parent], 20, 40);
    CHECK_SIZE([flipped convertSize: size fromView: parent], 5, 10);

    NSView *loose = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 30, 30)] autorelease];
    NSView *looseFlipped = [[[FlippedView alloc] initWithFrame: NSMakeRect(0, 0, 30, 30)] autorelease];
    CHECK_SIZE([loose convertSize: size toView: nil], 10, 20);
    CHECK_SIZE([loose convertSize: size fromView: nil], 10, 20);
    CHECK_SIZE([looseFlipped convertSize: size toView: nil], 10, 20);
    CHECK_SIZE([looseFlipped convertSize: size toView: loose], 10, 20);
    CHECK_SIZE([loose convertSize: size toView: looseFlipped], 10, 20);

    // The documented use: scaleUnitSquareToSize: converts the size of the view's bounds, so the bounds stay
    // a positive size in a flipped view.
    [innerFlipped scaleUnitSquareToSize: NSMakeSize(2, 2)];
    CHECK_SIZE([innerFlipped bounds].size, 10, 10);
    CHECK([innerFlipped bounds].origin.y >= 0);

    [pool release];
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
