// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: NSView SPI that WebKit calls (-_setDrawsOwnDescendants:,
// -_drawnByAncestor, -_subviewsIvar, -_setSubviewsIvar: and
// -_findLastViewInKeyViewLoop). Observed on macOS 26.7.3 (x86_64) with the
// same calls.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSView (WebKitSPI)
- (void)_setDrawsOwnDescendants:(BOOL)drawsOwnDescendants;
- (BOOL)_drawsOwnDescendants;
- (BOOL)_drawnByAncestor;
- (NSMutableArray *)_subviewsIvar;
- (void)_setSubviewsIvar:(NSMutableArray *)subviews;
- (NSView *)_findLastViewInKeyViewLoop;
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static NSView *view(NSView *parent)
{
    NSView *v = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
    [parent addSubview: v];
    return v;
}

int main(void)
{
    @autoreleasepool {
        NSView *parent = view(nil);
        NSView *child = view(parent);
        NSView *grandchild = view(child);
        report("nothing drawn by an ancestor by default",
               ![parent _drawsOwnDescendants] && ![child _drawnByAncestor] && ![grandchild _drawnByAncestor]);
        [parent _setDrawsOwnDescendants: YES];
        report("draws own descendants", [parent _drawsOwnDescendants]);
        report("descendants are drawn by an ancestor", [child _drawnByAncestor] && [grandchild _drawnByAncestor]);
        report("the view itself isn't", ![parent _drawnByAncestor]);
        [parent _setDrawsOwnDescendants: NO];
        report("cleared", ![child _drawnByAncestor]);

        NSMutableArray *storage = [parent _subviewsIvar];
        report("storage holds the subviews", [storage count] == 1 && [storage objectAtIndex: 0] == child);
        NSMutableArray *replacement = [[NSMutableArray alloc] init];
        NSUInteger retainCount = [replacement retainCount];
        [parent _setSubviewsIvar: replacement];
        report("setter doesn't retain", [replacement retainCount] == retainCount);
        report("subviews come from the new storage", [[parent subviews] count] == 0 && [parent _subviewsIvar] == replacement);
        report("child keeps its superview", [child superview] == parent);
        [parent _setSubviewsIvar: nil];
        report("no storage gives empty subviews", [parent subviews] != nil && [[parent subviews] count] == 0);
        [parent _setSubviewsIvar: storage];
        report("storage restored", [[parent subviews] count] == 1 && [[parent subviews] objectAtIndex: 0] == child);
        [replacement release];

        NSView *box = view(nil);
        NSView *c1 = view(box), *c2 = view(box), *c3 = view(box);
        NSView *outside = view(nil);
        report("no key view links: the view itself", [box _findLastViewInKeyViewLoop] == box);
        [box setNextKeyView: c1];
        [c1 setNextKeyView: c2];
        [c2 setNextKeyView: c3];
        report("follows descendants", [box _findLastViewInKeyViewLoop] == c3);
        [c3 setNextKeyView: outside];
        report("stops before a view outside", [box _findLastViewInKeyViewLoop] == c3);
        [c3 setNextKeyView: c1];
        report("stops at a loop", [box _findLastViewInKeyViewLoop] == c3);
        [c2 setNextKeyView: outside];
        [outside setNextKeyView: c3];
        report("doesn't come back from outside", [box _findLastViewInKeyViewLoop] == c2);

        NSView *b = view(nil);
        NSView *d1 = view(b), *d2 = view(b);
        NSView *g = view(d1);
        [b setNextKeyView: d1];
        [d1 setNextKeyView: g];
        [g setNextKeyView: d2];
        report("deeper descendants count", [b _findLastViewInKeyViewLoop] == d2);
        report("a view without subviews: itself", [g _findLastViewInKeyViewLoop] == g);
    }
    return failures != 0;
}
