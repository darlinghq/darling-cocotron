/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */
#import <AppKit/AppKit.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSRaise.h>
#import "NSStringDrawer.h"

@implementation NSTableHeaderCell

// QUIRK: a new header cell draws its title in the 11 point system font, in headerTextColor, truncated at the tail.
// The documentation only says the cell draws the column title. Evidence: black-box reads on macOS 10.14.4 (tier 2)
// of -font (.SFNSText 11 at every control size), -textColor (headerTextColor) and -lineBreakMode (4) of the header
// cell of a new NSTableColumn. Test: appkit-table-header-aqua.m (test_quirk_header_cell_defaults)
- (instancetype) initTextCell: (NSString *) string {
    self = [super initTextCell: string];
    if (self != nil) {
        [self setFont: [NSFont systemFontOfSize: [NSFont systemFontSizeForControlSize: NSControlSizeSmall]]];
        [self setTextColor: [NSColor headerTextColor]];
        [self setLineBreakMode: NSLineBreakByTruncatingTail];
    }
    return self;
}

// QUIRK: the 9 x 9 point indicator area ends 4 points before the right edge and is centred vertically, rounding
// half a point down in a flipped view. Evidence: black-box -sortIndicatorRectForBounds: on macOS 10.14.4 (tier 2):
// {90,4,9,9} for {0,0,103,17}, {90,8,9,9} for a 25 point high and {90,11,9,9} for a 30 point high header.
// Test: appkit-table-header-aqua.m (test_quirk_sort_indicator)
- (NSRect) sortIndicatorRectForBounds: (NSRect) bounds {
    return NSMakeRect(NSMaxX(bounds) - 13.0, NSMinY(bounds) + floor((NSHeight(bounds) - 9.0) / 2.0 + 0.5), 9.0, 9.0);
}

// QUIRK: the indicator of the primary sort (priority 0) is the NSAscendingSortIndicator or
// NSDescendingSortIndicator image at full opacity, one point right of -sortIndicatorRectForBounds:; other
// priorities draw nothing. Evidence: black-box renders on macOS 10.14.4 (tier 2) of this method called on a
// header cell in a flipped context: an upward chevron for ascending, a downward one for descending, at x 91..99
// of a 103 point cell; nothing for priority 1. Test: appkit-table-header-aqua.m (test_quirk_sort_indicator)
- (void) drawSortIndicatorWithFrame: (NSRect) frame
                             inView: (NSView *) controlView
                          ascending: (BOOL) ascending
                           priority: (NSInteger) priority
{
    if (priority != 0)
        return;

    NSImage *image = [NSImage imageNamed: ascending ? @"NSAscendingSortIndicator" : @"NSDescendingSortIndicator"];
    NSRect rect = NSOffsetRect([self sortIndicatorRectForBounds: frame], 1.0, 0.0);

    [image drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0
       respectFlipped: YES
                hints: nil];
}

// The title and the drawing area are the whole cell (macOS 10.14.4 returns the bounds for both); the insets of the
// title are applied when it is drawn.
- (NSRect) titleRectForBounds: (NSRect) rect {
    return rect;
}

- (NSRect) drawingRectForBounds: (NSRect) rect {
    return rect;
}

// QUIRK: the title is inset 2 points from the left and 4 from the right edge of the cell, 14 from the right edge
// when it is right aligned, and centred vertically. Evidence: black-box renders on macOS 10.14.4 (tier 2): titles
// of 103 point cells start at x 2 (left aligned), are centred on x 153.5 in the cell from 103 to 206 (centred), and
// end at x 295 in the cell from 206 to 309 (right aligned); the 11 point title has its baseline 12 points below the
// top of the 17 point header. Test: appkit-table-header-aqua.m (test_quirk_title_position)
- (NSRect) _titleTextRectForBounds: (NSRect) bounds {
    NSAttributedString *title = [self attributedStringValue];
    CGFloat height = [title length] ? [title size].height : 0;
    NSRect rect = bounds;
    CGFloat right = [self alignment] == NSTextAlignmentRight ? 14.0 : 4.0;

    rect.origin.x += 2.0;
    rect.size.width = MAX(0, rect.size.width - 2.0 - right);
    rect.origin.y = floor(NSMidY(bounds) - height / 2.0 + 0.5);
    rect.size.height = height;
    return rect;
}

- (void) drawInteriorWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    [[self attributedStringValue] _clipAndDrawInRect: [self _titleTextRectForBounds: cellFrame]
                                       lineBreakMode: [self lineBreakMode]];
}

- (void) drawWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    _controlView = controlView;
    [[controlView graphicsStyle] drawTableViewHeaderInRect: cellFrame highlighted: [self isHighlighted]];
    [self drawInteriorWithFrame: cellFrame inView: controlView];
}

@end
