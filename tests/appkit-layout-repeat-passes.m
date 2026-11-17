// Copyright (C) 2026 Lubos Dolezel
// Constraint-based layout passes: a view whose -layout changes what its intrinsic size depends on (a wrapping
// label setting its preferredMaxLayoutWidth from its new width) must get the resulting size from
// -layoutSubtreeIfNeeded, and a frame size change must mark a view as needing layout.
// QUIRK pinned here: frame size change sets needsLayout (observed on macOS 10.14.4).
#import <Cocoa/Cocoa.h>
#include <stdio.h>

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); return 20; \
} } while (0)

@interface CountingView : NSView {
    int _layoutCalls;
}
@property int layoutCalls;
@end
@implementation CountingView
@synthesize layoutCalls = _layoutCalls;
- (void)layout { self.layoutCalls++; [super layout]; }
@end

@interface WrapLabel : NSTextField {
    int _layoutCalls;
}
@property int layoutCalls;
@end
@implementation WrapLabel
@synthesize layoutCalls = _layoutCalls;
- (void)layout {
    self.layoutCalls++;
    [super layout];
    if ([self preferredMaxLayoutWidth] != NSWidth([self frame]))
        [self setPreferredMaxLayoutWidth:NSWidth([self frame])];
}
@end

static NSString *const kText = @"The quick brown fox jumps over the lazy dog and keeps running through the long meadow until the sun goes down behind the hills.\nA second paragraph also wraps over several lines because it is longer than the width the label is given by its constraints.";

static NSTextField *makeLabel(Class cls, NSView *host, NSView **below)
{
    NSTextField *label = [[cls alloc] initWithFrame:NSMakeRect(10, 10, 100, 17)];
    [label setTranslatesAutoresizingMaskIntoConstraints:NO];
    [label setEditable:NO]; [label setSelectable:NO]; [label setBezeled:NO]; [label setDrawsBackground:NO];
    [label setFont:[NSFont systemFontOfSize:13]];
    [label setStringValue:kText];
    [[label cell] setWraps:YES];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    *below = [[NSView alloc] initWithFrame:NSZeroRect];
    [*below setTranslatesAutoresizingMaskIntoConstraints:NO];
    [host addSubview:label]; [host addSubview:*below];
    NSDictionary *views = @{ @"l": label, @"b": *below };
    [host addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[l(360)]" options:0 metrics:nil views:views]];
    [host addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-10-[l]-8-[b(10)]" options:0 metrics:nil views:views]];
    [host addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[b(10)]" options:0 metrics:nil views:views]];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200) styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:YES];
    [window setContentView:host];
    return label;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        // 1. The wrapping pattern: the label's height follows its laid out width.
        NSView *host = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)], *below = nil;
        WrapLabel *label = (WrapLabel *)makeLabel([WrapLabel class], host, &below);
        [host layoutSubtreeIfNeeded];
        CGFloat width = NSWidth([label frame]);
        CHECK(width >= 360);
        CHECK([label preferredMaxLayoutWidth] == width);
        NSSize wrapped = [[label cell] cellSizeForBounds:NSMakeRect(0, 0, width, 1e7)];
        NSSize oneLine = [[label cell] cellSizeForBounds:NSMakeRect(0, 0, 1e7, 1e7)];
        CHECK(wrapped.height > 2 * oneLine.height);
        CHECK(NSHeight([label frame]) == [label intrinsicContentSize].height);
        CHECK(NSHeight([label frame]) == wrapped.height);
        // the view below sits 8 points under the label's final frame (the host is not flipped)
        CHECK(NSMaxY([below frame]) + 8 == NSMinY([label frame]));
        // laid out once for the first frame and once for the frame that the new width produced
        CHECK([label layoutCalls] == 2);
        [host layoutSubtreeIfNeeded];
        CHECK([label layoutCalls] == 2);

        // 2. Without a layout override the label is not given a maximum width.
        NSView *host2 = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)], *below2 = nil;
        NSTextField *plain = makeLabel([NSTextField class], host2, &below2);
        [host2 layoutSubtreeIfNeeded];
        CHECK([plain preferredMaxLayoutWidth] == 0);
        CHECK(NSHeight([plain frame]) == [plain intrinsicContentSize].height);
        CHECK(NSHeight([plain frame]) < wrapped.height);

        // 3. A maximum width change invalidates the intrinsic size, the same value does not.
        [plain setPreferredMaxLayoutWidth:150];
        CHECK([plain needsUpdateConstraints]);
        [host2 layoutSubtreeIfNeeded];
        CHECK(![plain needsUpdateConstraints]);
        [plain setPreferredMaxLayoutWidth:150];
        CHECK(![plain needsUpdateConstraints]);
        CHECK(NSHeight([plain frame]) == [plain intrinsicContentSize].height);
        CHECK(NSHeight([plain frame]) > NSHeight([label frame]));

        // 4. QUIRK: a frame size change marks the view as needing layout, and layout reaches a view that
        // constraints sized.
        CountingView *view = [[CountingView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        [view layoutSubtreeIfNeeded];
        CHECK(![view needsLayout]);
        [view setFrameSize:NSMakeSize(120, 100)];
        CHECK([view needsLayout]);
        int calls = [view layoutCalls];
        [view layoutSubtreeIfNeeded];
        CHECK([view layoutCalls] == calls + 1 && ![view needsLayout]);
        [view setFrameSize:NSMakeSize(120, 100)];
        CHECK(![view needsLayout]);

        CountingView *child = [[CountingView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
        [child setTranslatesAutoresizingMaskIntoConstraints:NO];
        [view addSubview:child];
        [view addConstraint:[NSLayoutConstraint constraintWithItem:child attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual
                                                            toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:50]];
        [view addConstraint:[NSLayoutConstraint constraintWithItem:child attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual
                                                            toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:20]];
        [view layoutSubtreeIfNeeded];
        CHECK(NSEqualSizes([child frame].size, NSMakeSize(50, 20)));
        CHECK([child layoutCalls] >= 1);
        printf("PASS\n");
    }
    return 0;
}
