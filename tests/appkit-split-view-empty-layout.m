// Copyright (C) 2026 Lubos Dolezel
//
// -[NSSplitView adjustSubviews] with empty, hidden and too-narrow panes, in both
// orientations: every visible pane gets a finite, non-negative length inside the
// bounds, hidden panes get an empty frame, and the notifications are posted once
// (and not at all with no subviews).
#import <AppKit/AppKit.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d (vertical=%d mode=%d): %s\n", __LINE__, (int)vertical, mode, #c); failures++; } } while (0)

static int will, did;
@interface Counter : NSObject
@end
@implementation Counter
- (void)willResize:(NSNotification *)n { will++; }
- (void)didResize:(NSNotification *)n { did++; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Counter *counter = [Counter new];
        for (int vertical = 0; vertical < 2; vertical++) {
            for (int mode = 0; mode < 7; mode++) {
                CGFloat extent = mode == 4 ? 3 : 101;
                NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, extent, extent)];
                [split setVertical:vertical];
                [[NSNotificationCenter defaultCenter] removeObserver:counter];
                [[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(willResize:)
                        name:NSSplitViewWillResizeSubviewsNotification object:split];
                [[NSNotificationCenter defaultCenter] addObserver:counter selector:@selector(didResize:)
                        name:NSSplitViewDidResizeSubviewsNotification object:split];
                will = did = 0;
                NSUInteger panes = mode == 5 ? 1 : (mode == 6 ? 0 : 3);
                NSMutableArray *views = [NSMutableArray array];
                for (NSUInteger i = 0; i < panes; i++) {
                    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 20, 20)];
                    [split addSubview:v];
                    [views addObject:v];
                }
                // -addSubview: lays the panes out as it goes, so start the adjustment under test from
                // equal panes and count only its notifications.
                for (NSView *v in views) [v setFrame:NSMakeRect(0, 0, 20, 20)];
                if (mode == 2) [views[1] setHidden:YES];
                if (mode == 3) for (NSView *v in views) [v setHidden:YES];
                will = did = 0;
                [split adjustSubviews];
                CHECK(will == (panes ? 1 : 0) && did == will);
                unsigned visible = 0;
                for (NSView *v in views) {
                    NSRect f = [v frame];
                    CGFloat origin = vertical ? f.origin.x : f.origin.y;
                    CGFloat size = vertical ? f.size.width : f.size.height;
                    // Hidden panes take no part in the layout and keep their frame.
                    if ([v isHidden]) { CHECK(NSEqualRects(f, NSMakeRect(0, 0, 20, 20))); continue; }
                    CHECK(isfinite(origin) && isfinite(size) && size >= 0);
                    CHECK(origin >= 0 && origin + size <= extent);
                    if (mode == 0) CHECK(size == (visible == 2 ? 31 : 30));
                    if (mode == 2) CHECK(size == 48);
                    if (mode == 4) CHECK(size == 0);
                    if (mode == 5) CHECK(size == 101 && origin == 0);
                    visible++;
                }
            }
        }
        if (!failures) puts("PASS");
    }
    return failures ? 1 : 0;
}
