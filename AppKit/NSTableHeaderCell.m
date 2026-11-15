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

// The indicator sits at the right end of the header cell
- (NSRect) sortIndicatorRectForBounds: (NSRect) bounds {
    NSRect rect;

    rect.size = NSMakeSize(12.0, 12.0);
    rect.origin.x = NSMaxX(bounds) - rect.size.width - 4.0;
    rect.origin.y = NSMidY(bounds) - rect.size.height / 2.0;
    return rect;
}

// An ascending indicator points up and a descending one down
- (void) drawSortIndicatorWithFrame: (NSRect) frame
                             inView: (NSView *) controlView
                          ascending: (BOOL) ascending
                           priority: (NSInteger) priority
{
    BOOL pointsUp = ascending != [controlView isFlipped];
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    CGFloat inset = 2.0;
    NSRect box = NSInsetRect(frame, inset, inset + 1.0);

    if (pointsUp) {
        [arrow moveToPoint: NSMakePoint(NSMinX(box), NSMinY(box))];
        [arrow lineToPoint: NSMakePoint(NSMaxX(box), NSMinY(box))];
        [arrow lineToPoint: NSMakePoint(NSMidX(box), NSMaxY(box))];
    } else {
        [arrow moveToPoint: NSMakePoint(NSMinX(box), NSMaxY(box))];
        [arrow lineToPoint: NSMakePoint(NSMaxX(box), NSMaxY(box))];
        [arrow lineToPoint: NSMakePoint(NSMidX(box), NSMinY(box))];
    }
    [arrow closePath];
    [[NSColor darkGrayColor] setFill];
    [arrow fill];
}

- (NSRect) titleRectForBounds: (NSRect) rect {
    rect.origin.x += 3.0;
    rect.origin.y += 2.5;
    rect.size.width -= 6.0;
    return rect;
}

- (void) drawWithFrame: (NSRect) cellFrame inView: (NSView *) controlView {
    _controlView = controlView;
    [[controlView graphicsStyle]
            drawTableViewHeaderInRect: cellFrame
                          highlighted: [self isHighlighted]];
    [[self attributedStringValue]
            _clipAndDrawInRect: [self titleRectForBounds: cellFrame]
                lineBreakMode: NS_EXTRA(NSCell, self)->_lineBreakMode];
}

@end
