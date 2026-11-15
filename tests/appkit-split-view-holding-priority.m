// Copyright (C) 2026 Lubos Dolezel
//
// NSSplitView holding priority in a constraint-based layout: the subview with the higher
// holding priority keeps its width while the window, and with it the split view, is resized.
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

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];

        // Frame-based layout ignores holding priorities: the resize is proportional
        {
            NSSplitView *frames = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
            [frames setVertical:YES];
            [frames setDividerStyle:NSSplitViewDividerStyleThin];
            NSView *a = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 300)] autorelease];
            NSView *b = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 399, 300)] autorelease];
            [frames addArrangedSubview:a];
            [frames addArrangedSubview:b];
            [frames adjustSubviews];
            CGFloat before = NSWidth([a frame]);
            [frames setHoldingPriority:260 forSubviewAtIndex:0];
            [frames setFrameSize:NSMakeSize(700, 300)];
            expect(NSWidth([a frame]) > before + 20, @"frame-based layout: the held view still grows proportionally");
        }

        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 300)
                                                        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO] autorelease];
        NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
        [split setVertical:YES];
        [split setDividerStyle:NSSplitViewDividerStyleThin];
        NSView *left = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 300)] autorelease];
        NSView *right = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 399, 300)] autorelease];
        [left setTranslatesAutoresizingMaskIntoConstraints:NO];
        [right setTranslatesAutoresizingMaskIntoConstraints:NO];
        [split addArrangedSubview:left];
        [split addArrangedSubview:right];

        NSView *container = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)] autorelease];
        [split setTranslatesAutoresizingMaskIntoConstraints:NO];
        [container addSubview:split];
        [NSLayoutConstraint activateConstraints:@[
            [[split leadingAnchor] constraintEqualToAnchor:[container leadingAnchor]],
            [[split trailingAnchor] constraintEqualToAnchor:[container trailingAnchor]],
            [[split topAnchor] constraintEqualToAnchor:[container topAnchor]],
            [[split bottomAnchor] constraintEqualToAnchor:[container bottomAnchor]],
            [[left widthAnchor] constraintGreaterThanOrEqualToConstant:50],
            [[right widthAnchor] constraintGreaterThanOrEqualToConstant:50]
        ]];
        [window setContentView:container];
        [window layoutIfNeeded];
        CGFloat leftWidth = NSWidth([left frame]);

        [split setHoldingPriority:260 forSubviewAtIndex:0];
        [window setContentSize:NSMakeSize(700, 300)];
        [window layoutIfNeeded];
        expect(fabs(NSWidth([left frame]) - leftWidth) < 0.5, @"left holds its width while growing");
        expect(NSWidth([right frame]) > 500, @"right takes the extra width");

        [window setContentSize:NSMakeSize(400, 300)];
        [window layoutIfNeeded];
        expect(fabs(NSWidth([left frame]) - leftWidth) < 0.5, @"left holds its width while shrinking");
    }
    printf("PASS\n");
    return 0;
}
