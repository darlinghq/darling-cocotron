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

@interface InsetView : NSView
@property BOOL flippedView;
@end

@implementation InsetView
- (BOOL)isFlipped { return self.flippedView; }
- (NSEdgeInsets)alignmentRectInsets { return NSEdgeInsetsMake(1, 2, 3, 4); }
@end

@interface CountingView : NSView
@property BOOL updates;
@property NSInteger draws, layerUpdates;
@end

@implementation CountingView
- (BOOL)wantsUpdateLayer { return self.updates; }
- (void)updateLayer { self.layerUpdates++; }
- (void)drawRect:(NSRect)rect { self.draws++; }
@end

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSView *plain = [[NSView alloc] initWithFrame:NSMakeRect(10, 20, 30, 40)];
        expect(plain.alphaValue == 1.0, @"views start opaque");
        NSEdgeInsets zero = plain.alignmentRectInsets;
        expect(zero.top == 0 && zero.left == 0 && zero.bottom == 0 && zero.right == 0 &&
                   NSEqualRects([plain frameForAlignmentRect:plain.frame], plain.frame),
               @"a plain view's alignment rect is its frame");

        InsetView *view = [[InsetView alloc] initWithFrame:NSZeroRect];
        NSRect alignment = NSMakeRect(10, 20, 30, 40);
        expect(NSEqualRects([view frameForAlignmentRect:alignment], NSMakeRect(8, 17, 36, 44)),
               @"unflipped: the bottom inset lies at the origin");
        view.flippedView = YES;
        expect(NSEqualRects([view frameForAlignmentRect:alignment], NSMakeRect(8, 19, 36, 44)),
               @"flipped: the top inset lies at the origin");
        expect(NSEqualRects([view alignmentRectForFrame:[view frameForAlignmentRect:alignment]], alignment),
               @"the two conversions are inverses");

        plain.alphaValue = 0.25;
        [plain setHidden: YES];
        [plain prepareForReuse];
        expect(plain.alphaValue == 1.0 && ![plain isHidden], @"prepareForReuse makes the view visible and opaque");

        expect(!plain.wantsUpdateLayer, @"views draw with drawRect: by default");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100)
                                                       styleMask:NSTitledWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        CountingView *counting = [[CountingView alloc] initWithFrame:NSMakeRect(0, 0, 50, 50)];
        [window.contentView addSubview:counting];
        counting.wantsLayer = YES;
        expect(counting.layer != nil, @"the view is layer-backed");
        counting.alphaValue = 0.5;
        expect(counting.alphaValue == 0.5 && counting.layer.opacity == 0.5, @"alphaValue sets the layer's opacity");
        [counting display];
        expect(counting.draws == 1 && counting.layerUpdates == 0, @"a view that doesn't want updateLayer draws");
        counting.updates = YES;
        [counting display];
        expect(counting.draws == 1 && counting.layerUpdates == 1,
               @"a layer-backed view that wants updateLayer gets it instead of drawRect:");
        counting.wantsLayer = NO;
        [counting display];
        expect(counting.draws == 2 && counting.layerUpdates == 1, @"without a layer the view draws");
        NSLog(@"PASS: NSView alignment rects, prepareForReuse and updateLayer");
    }
    return 0;
}
