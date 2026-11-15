// Copyright (C) 2026 Lubos Dolezel
//
// NSSplitView arranged subviews, holding priorities and the possible divider range.
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

static NSView *box(CGFloat width, CGFloat height)
{
    return [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)] autorelease];
}

int main(void)
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        // Kept alive on purpose: macOS raises when a split view that had arranged subviews
        // removed is deallocated
        NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 500, 300)];
        [split setVertical:YES];
        [split setDividerStyle:NSSplitViewDividerStyleThin];
        NSView *a = box(100, 300), *b = box(100, 300), *c = box(100, 300);

        expect([split arrangesAllSubviews], @"all subviews are arranged by default");
        [split addSubview:a];
        expect([[split arrangedSubviews] count] == 1 && [[split arrangedSubviews] objectAtIndex:0] == a,
               @"a plain subview is arranged");
        [split addArrangedSubview:b];
        expect([[split subviews] count] == 2 && [[split arrangedSubviews] count] == 2, @"addArrangedSubview: adds a subview");
        [split insertArrangedSubview:c atIndex:0];
        expect([[split arrangedSubviews] objectAtIndex:0] == c && [[split subviews] objectAtIndex:0] == c,
               @"insertArrangedSubview:atIndex: orders both lists");
        expect([[split arrangedSubviews] count] == 3, @"three arranged");

        [split removeArrangedSubview:c];
        expect([c superview] == nil && [[split arrangedSubviews] count] == 2,
               @"with all subviews arranged, removing an arranged subview removes it from the split view");

        // Only some subviews arranged
        [split setArrangesAllSubviews:NO];
        expect(![split arrangesAllSubviews] && [[split arrangedSubviews] count] == 2, @"existing subviews stay arranged");
        [split addSubview:c];
        expect([[split subviews] count] == 3 && [[split arrangedSubviews] count] == 2, @"a new plain subview is not arranged");
        [split removeArrangedSubview:b];
        expect([b superview] == split && [[split arrangedSubviews] count] == 1,
               @"removing from the arrangement keeps the subview");
        [split setArrangesAllSubviews:YES];
        expect([[split arrangedSubviews] count] == 3, @"arranging all makes every subview arranged again");

        // Holding priorities
        expect([split holdingPriorityForSubviewAtIndex:0] == 250 && [split holdingPriorityForSubviewAtIndex:1] == 250,
               @"default holding priority is 250");
        [split setHoldingPriority:260 forSubviewAtIndex:1];
        expect([split holdingPriorityForSubviewAtIndex:1] == 260 && [split holdingPriorityForSubviewAtIndex:0] == 250,
               @"holding priority is per subview");
        expect([split holdingPriorityForSubviewAtIndex:3] == 250 && [split holdingPriorityForSubviewAtIndex:-1] == 250,
               @"an index beyond the arranged subviews reads as the default");
        [split setHoldingPriority:300 forSubviewAtIndex:3];
        expect([split holdingPriorityForSubviewAtIndex:3] == 250, @"and setting it is ignored");
        BOOL raised = NO;
        @try { [split insertArrangedSubview:box(10, 10) atIndex:9]; } @catch (NSException *e) { raised = [[e name] isEqualToString:NSRangeException]; }
        expect(raised, @"inserting beyond the arranged subviews raises NSRangeException");
        [split removeArrangedSubview:box(10, 10)];

        // Divider range
        NSSplitView *two = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
        [two setVertical:YES];
        [two setDividerStyle:NSSplitViewDividerStyleThin];
        [two addArrangedSubview:box(100, 300)];
        [two addArrangedSubview:box(100, 300)];
        [two adjustSubviews];
        expect([two minPossiblePositionOfDividerAtIndex:0] == 0, @"minimum divider position");
        expect([two maxPossiblePositionOfDividerAtIndex:0] == 600 - [two dividerThickness], @"maximum divider position");
    }
    printf("PASS\n");
    return 0;
}
