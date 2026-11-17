// Copyright (C) 2026 Lubos Dolezel
//
// test_quirk_button_cell_title_centered: -[NSButtonCell drawTitle:withFrame:inView:] centers the title
// vertically in the frame it is given, which may be taller than the text, and returns the rectangle it
// drew in: as high as the text and in the middle of the frame. Observed in a flipped view on macOS 10.14.4
// and 26.7.3 (a 40 point frame, a 13 point title: the rectangle is 16 or 17 points high at y 12, the ink
// lies in the middle rows). The cell used to draw at the bottom of the frame, or at the top in a flipped
// view. 10.14.4 puts the title at the edge in a view that is not flipped; only a flipped view is tested.
//
// Build: clang -fobjc-arc -framework AppKit appkit-button-cell-draw-title-centered.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface TitleView : NSView {
@public
    NSRect result;
    NSButtonCell *cell;
}
@end
@implementation TitleView
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r {
    [[NSColor whiteColor] setFill];
    NSRectFill(self.bounds);
    NSAttributedString *t = [[NSAttributedString alloc] initWithString:@"Accept"
            attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: NSColor.blackColor}];
    result = [cell drawTitle:t withFrame:NSMakeRect(0, 0, 88, 40) inView:self];
}
@end

static void test_quirk_button_cell_title_centered(void) {
    TitleView *view = [[TitleView alloc] initWithFrame:NSMakeRect(0, 0, 88, 40)];
    view->cell = [[NSButtonCell alloc] init];
    [view->cell setBordered:NO];
    [view->cell setTitle:@"Accept"];
    NSBitmapImageRep *rep = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:rep];
    CHECK(view->result.size.height > 8 && view->result.size.height < 24);
    CHECK(fabs(NSMidY(view->result) - 20) <= 1);
    int top = -1, bottom = -1;
    for (NSInteger y = 0; y < rep.pixelsHigh; y++)
        for (NSInteger x = 0; x < rep.pixelsWide; x++)
            if ([[rep colorAtX:x y:y] redComponent] < 0.5) {
                if (top < 0) top = (int)y;
                bottom = (int)y;
            }
    CHECK(top >= 0);
    CHECK(fabs((top + bottom) / 2.0 - 20) <= 3);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        test_quirk_button_cell_title_centered();
    }
    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
