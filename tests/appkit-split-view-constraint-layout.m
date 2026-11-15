// Copyright (C) 2026 Lubos Dolezel
//
// An NSSplitView whose arranged subviews carry their own constraints lays them out with constraints:
// the subviews stop translating their autoresizing masks, fill the split view and keep the
// constraints they were given. Subviews without constraints stay frame-based.
// (Mac: macOS 26.7.3, checked with a probe of translatesAutoresizingMaskIntoConstraints before and after layout.)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok) {
        NSLog(@"FAIL: %@", what);
        failures++;
    }
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                        styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO] autorelease];

        // Horizontal stack (divider is horizontal): the second subview has a minimum height
        NSSplitView *split = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)] autorelease];
        [split setVertical:NO];
        [split setDividerStyle:NSSplitViewDividerStyleThin];
        NSScrollView *top = [[[NSScrollView alloc] init] autorelease];
        NSScrollView *bottom = [[[NSScrollView alloc] init] autorelease];
        [[bottom heightAnchor] constraintGreaterThanOrEqualToConstant:70].active = YES;
        [split addArrangedSubview:top];
        [split addArrangedSubview:bottom];
        [split setHoldingPriority:260 forSubviewAtIndex:1];
        [window setContentView:split];
        [window layoutIfNeeded];

        expect(![top translatesAutoresizingMaskIntoConstraints] && ![bottom translatesAutoresizingMaskIntoConstraints],
               @"arranged subviews switch to constraint-based layout");
        expect(fabs(NSWidth([top frame]) - 600) < 0.5 && fabs(NSWidth([bottom frame]) - 600) < 0.5, @"subviews fill the width");
        expect(NSHeight([bottom frame]) >= 70 - 0.5, @"the subview's own constraint holds");
        expect(fabs(NSHeight([top frame]) + NSHeight([bottom frame]) + [split dividerThickness] - 400) < 0.5,
               @"the subviews and the divider fill the height");

        NSView *a = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        NSView *b = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)] autorelease];
        NSSplitView *plain = [[[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 300, 100)] autorelease];
        [plain setVertical:YES];
        [plain addArrangedSubview:a];
        [plain addArrangedSubview:b];
        NSWindow *second = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100)
                                                         styleMask:NSWindowStyleMaskTitled
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO] autorelease];
        [second setContentView:plain];
        [second layoutIfNeeded];
        expect([a translatesAutoresizingMaskIntoConstraints] && [b translatesAutoresizingMaskIntoConstraints],
               @"subviews without constraints stay frame-based");
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
