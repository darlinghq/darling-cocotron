// Copyright (C) 2026 Lubos Dolezel
//
// Hiding or showing a view invalidates the area the view occupies in its
// superview, not the whole superview, so siblings elsewhere are not redrawn.
// (macOS does this without going through the public invalidation methods, so
// this test pins Cocotron's own invalidation path.)
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

@interface RecordingView : NSView {
    NSRect _dirty;
    BOOL _dirtyAll;
}
- (void)reset;
@property (readonly) NSRect dirty;
@property (readonly) BOOL dirtyAll;
@end

@implementation RecordingView
@synthesize dirty = _dirty, dirtyAll = _dirtyAll;
- (void)reset { _dirty = NSZeroRect; _dirtyAll = NO; }
- (void)setNeedsDisplay:(BOOL)flag { if (flag) _dirtyAll = YES; [super setNeedsDisplay:flag]; }
- (void)setNeedsDisplayInRect:(NSRect)rect { _dirty = NSUnionRect(_dirty, rect); [super setNeedsDisplayInRect:rect]; }
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        RecordingView *parent = [[RecordingView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSView *child = [[NSView alloc] initWithFrame:NSMakeRect(20, 30, 40, 50)];
        [parent addSubview:child];
        [parent reset];

        [child setHidden:YES];
        expect([child isHidden], @"hidden");
        expect(!parent.dirtyAll, @"hiding does not invalidate the whole superview");
        expect(NSEqualRects(parent.dirty, [child frame]), @"hiding invalidates the view's frame in the superview");

        [parent reset];
        [child setHidden:YES];
        expect(NSIsEmptyRect(parent.dirty) && !parent.dirtyAll, @"hiding an already hidden view invalidates nothing");

        [child setHidden:NO];
        expect(!parent.dirtyAll, @"showing does not invalidate the whole superview");
        expect(NSEqualRects(parent.dirty, [child frame]), @"showing invalidates the view's frame in the superview");
        NSLog(@"PASS");
    }
    return 0;
}
