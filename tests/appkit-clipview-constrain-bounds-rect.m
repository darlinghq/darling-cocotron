// Copyright (C) 2026 Lubos Dolezel
//
// -[NSClipView constrainBoundsRect:] keeps a proposed bounds rect inside the document: its origin is
// what -constrainScrollPoint: returns and its size is unchanged. Expected values from macOS 26.7.3: a clip
// view of 100 x 100 over a 300 x 300 document constrains (-50, 500, 100, 100) to (0, 200, 100, 100), the
// same origin -constrainScrollPoint: gives.
// Build: clang -framework AppKit appkit-clipview-constrain-bounds-rect.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

// Declared here: older SDK headers do not have it.
@interface NSClipView (ConstrainBoundsRect)
- (NSRect) constrainBoundsRect: (NSRect) proposedBounds;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSClipView *clip = [[[NSClipView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)] autorelease];
    NSView *doc = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 300)] autorelease];
    [clip setDocumentView: doc];
    CHECK([clip respondsToSelector: @selector(constrainBoundsRect:)]);
    NSRect r = [clip constrainBoundsRect: NSMakeRect(-50, 500, 100, 100)];
    NSPoint p = [clip constrainScrollPoint: NSMakePoint(-50, 500)];
    CHECK(NSEqualPoints(r.origin, p));
    CHECK(r.size.width == 100 && r.size.height == 100);
    CHECK(r.origin.x == 0 && r.origin.y == 200);
    r = [clip constrainBoundsRect: NSMakeRect(20, 30, 100, 100)];
    CHECK(r.origin.x == 20 && r.origin.y == 30 && r.size.width == 100 && r.size.height == 100);
    if (failures == 0)
        printf("PASS appkit-clipview-constrain-bounds-rect\n");
    [pool release];
    return failures != 0;
}
