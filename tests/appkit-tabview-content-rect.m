// Copyright (C) 2026 Lubos Dolezel
//
// NSTabView geometry: the view is flipped, and -contentRect (which is also the frame given to the
// selected tab item's view, now and after a resize) depends on the tab view type and the control
// size. Expected values were observed on Mac OS X 10.14.4 and macOS 26.7.3 (identical on both)
// for a 560x371 tab view, then 400x300.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static const struct {
    int controlSize, type;
    NSRect content, resized;
} expected[] = {
    {0, 0, {10, 33, 540, 325}, {10, 33, 380, 254}},
    {0, 1, {32, 7, 518, 351}, {32, 7, 358, 280}},
    {0, 2, {10, 7, 540, 333}, {10, 7, 380, 262}},
    {0, 3, {10, 7, 519, 351}, {10, 7, 359, 280}},
    {0, 4, {10, 7, 540, 351}, {10, 7, 380, 280}},
    {0, 5, {1, 1, 558, 369}, {1, 1, 398, 298}},
    {0, 6, {0, 0, 560, 371}, {0, 0, 400, 300}},
    {1, 0, {10, 25, 540, 333}, {10, 25, 380, 262}},
    {1, 1, {30, 7, 520, 351}, {30, 7, 360, 280}},
    {1, 2, {10, 7, 540, 335}, {10, 7, 380, 264}},
    {1, 3, {10, 7, 521, 351}, {10, 7, 361, 280}},
    {1, 4, {10, 7, 540, 351}, {10, 7, 380, 280}},
    {1, 5, {1, 1, 558, 369}, {1, 1, 398, 298}},
    {1, 6, {0, 0, 560, 371}, {0, 0, 400, 300}},
    {2, 0, {10, 19, 540, 339}, {10, 19, 380, 268}},
    {2, 1, {28, 7, 522, 351}, {28, 7, 362, 280}},
    {2, 2, {10, 7, 540, 336}, {10, 7, 380, 265}},
    {2, 3, {10, 7, 522, 351}, {10, 7, 362, 280}},
    {2, 4, {10, 7, 540, 351}, {10, 7, 380, 280}},
    {2, 5, {1, 1, 558, 369}, {1, 1, 398, 298}},
    {2, 6, {0, 0, 560, 371}, {0, 0, 400, 300}},
};

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (unsigned i = 0; i < sizeof(expected) / sizeof(expected[0]); i++) {
            NSTabView *tv = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 20, 560, 371)];
            tv.tabViewType = (NSTabViewType) expected[i].type;
            tv.controlSize = (NSControlSize) expected[i].controlSize;
            NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:@"a"];
            item.label = @"A";
            item.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
            [tv addTabViewItem:item];
            [tv selectTabViewItemAtIndex:0];

            int ok = tv.isFlipped && NSEqualRects(tv.contentRect, expected[i].content) &&
                     NSEqualRects([(NSView *)item.view frame], expected[i].content);
            [tv setFrameSize:NSMakeSize(400, 300)];
            ok = ok && NSEqualRects([(NSView *)item.view frame], expected[i].resized);
            if (!ok) {
                NSRect c = tv.contentRect;
                fprintf(stderr, "FAIL size=%d type=%d content={%g,%g,%g,%g}\n", expected[i].controlSize,
                        expected[i].type, c.origin.x, c.origin.y, c.size.width, c.size.height);
                failures++;
            }
        }
        // Drawing must not fail for any type (tabs are drawn through a mirrored context).
        NSTabView *tv = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
        NSTabViewItem *a = [[NSTabViewItem alloc] initWithIdentifier:@"a"];
        a.label = @"One";
        [tv addTabViewItem:a];
        NSBitmapImageRep *rep = [tv bitmapImageRepForCachingDisplayInRect:tv.bounds];
        [tv cacheDisplayInRect:tv.bounds toBitmapImageRep:rep];
        CHECK(rep != nil);
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
