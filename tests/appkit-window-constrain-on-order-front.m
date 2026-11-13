// Copyright (C) 2026 Lubos Dolezel
//
// Contract (-[NSWindow constrainFrameRect:toScreen:]): when a titled window
// is ordered onto the screen it is moved so that it lies inside the visible
// frame of the screen, through -constrainFrameRect:toScreen:, which a
// subclass may override. Borderless windows are not moved. A window that is
// already on screen is not moved when ordered front again. Child windows are
// constrained when they are ordered in like any other window. Prints PASS
// or FAIL. Behaviour checked against macOS 26.7.3 (see impl notes).
#import <AppKit/AppKit.h>

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

@interface Probe : NSWindow { @public int calls; BOOL keep; }
@end
@implementation Probe
- (NSRect)constrainFrameRect:(NSRect)r toScreen:(NSScreen *)s {
    calls++;
    return keep ? r : [super constrainFrameRect:r toScreen:s];
}
@end

static Probe *make(NSRect r, NSWindowStyleMask m) {
    return [[Probe alloc] initWithContentRect:r styleMask:m backing:NSBackingStoreBuffered defer:NO];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect vis = [[NSScreen mainScreen] visibleFrame];
        NSWindowStyleMask titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable;
        CGFloat low = vis.origin.y - 120;

        // Moved below the bottom edge after creation, before it is shown.
        Probe *w = make(NSMakeRect(100, 300, 300, 200), titled);
        [w setFrameOrigin:NSMakePoint(100, low)];
        w->calls = 0;
        [w orderFront:nil];
        CHECK(NSMinY([w frame]) >= NSMinY(vis) - 0.5, "titled window left below the visible area: y=%g", [w frame].origin.y);
        CHECK(w->calls >= 1, "constrainFrameRect:toScreen: not sent when ordering in");

        // Already visible: moving it off and ordering front again leaves it.
        [w setFrameOrigin:NSMakePoint(100, low)];
        [w orderFront:nil];
        CHECK(NSMinY([w frame]) < NSMinY(vis), "visible window was moved by a second orderFront");

        // Ordering out and in again constrains it again.
        [w orderOut:nil];
        [w orderFront:nil];
        CHECK(NSMinY([w frame]) >= NSMinY(vis) - 0.5, "window not constrained after orderOut and orderFront");

        // An override that returns the rectangle unchanged wins.
        Probe *k = make(NSMakeRect(100, 300, 300, 200), titled);
        k->keep = YES;
        [k setFrameOrigin:NSMakePoint(100, low)];
        [k makeKeyAndOrderFront:nil];
        CHECK(NSMinY([k frame]) < NSMinY(vis), "override result ignored");
        CHECK(k->calls >= 1, "override not consulted by makeKeyAndOrderFront:");

        // Right and left edges.
        Probe *r = make(NSMakeRect(100, 300, 300, 200), titled);
        [r setFrameOrigin:NSMakePoint(NSMaxX(vis) - 100, 300)];
        [r orderFront:nil];
        CHECK(NSMaxX([r frame]) <= NSMaxX(vis) + 0.5, "right edge not constrained");
        Probe *l = make(NSMakeRect(100, 300, 300, 200), titled);
        [l setFrameOrigin:NSMakePoint(-150, 300)];
        [l orderFront:nil];
        CHECK(NSMinX([l frame]) >= NSMinX(vis) - 0.5, "left edge not constrained");

        // Taller than the visible frame: the top edge (title bar) stays on screen.
        Probe *t = make(NSMakeRect(100, 0, 300, vis.size.height + 400), titled);
        [t orderFront:nil];
        CHECK(fabs(NSMaxY([t frame]) - NSMaxY(vis)) < 0.5, "tall window top not at the top of the visible area: maxY=%g", NSMaxY([t frame]));
        CHECK(fabs([t frame].size.height - (vis.size.height + 400)) < 40, "tall window was resized");

        // Child windows are constrained when ordered in.
        Probe *parent = make(NSMakeRect(100, 300, 300, 200), titled);
        [parent orderFront:nil];
        Probe *child = make(NSMakeRect(100, 300, 200, 100), titled);
        [child setFrameOrigin:NSMakePoint(100, low)];
        [parent addChildWindow:child ordered:NSWindowAbove];
        [child orderFront:nil];
        CHECK(NSMinY([child frame]) >= NSMinY(vis) - 0.5, "titled child window left off screen: y=%g", [child frame].origin.y);

        // Borderless windows are not moved.
        Probe *b = make(NSMakeRect(100, 300, 300, 200), NSWindowStyleMaskBorderless);
        [b setFrameOrigin:NSMakePoint(100, low)];
        [b orderFront:nil];
        CHECK(NSMinY([b frame]) < NSMinY(vis), "borderless window was constrained");

        [w close]; [k close]; [r close]; [l close]; [t close]; [child close]; [parent close]; [b close];
    }
    printf(failures ? "FAIL\n" : "PASS\n");
    return failures != 0;
}
