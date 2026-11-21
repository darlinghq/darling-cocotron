/* Copyright (c) 2009 Christopher J. W. Lloyd

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
#import "NSToolbarItemView.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSAttributedString.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSGradient.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSStringDrawer.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSToolbarItem.h>
#import <AppKit/NSWindow.h>

@interface NSToolbarItem (private)
- (void) drawInRect: (NSRect) bounds highlighted: (BOOL) highlighted;
- (NSSize) _labelSize;
- (BOOL) _sizeFollowsView;
- (NSSize) _viewSize;
@end

@interface NSToolbar (private)
- (void) didSelectToolbarItem: (NSString *) identifier;
- (void) _itemViewIntrinsicSizeDidChange: (NSToolbarItem *) item;
@end

@implementation NSToolbarItemView

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    _toolbarItem = nil;
    return self;
}

- (void) dealloc {
    _toolbarItem = nil;
    [super dealloc];
}

- (void) setToolbarItem: (NSToolbarItem *) item {
    _toolbarItem = item;
}

- (void) setSubview: (NSView *) view {
    while ([[self subviews] count])
        [[[self subviews] lastObject] removeFromSuperview];

    if (view != nil)
        [self addSubview: view];
}

- (NSRect) availableRectForSubview {
    NSRect rect = [self bounds];
    CGFloat labelHeight = [_toolbarItem _labelSize].height;

    // The label is drawn at the bottom, 4 points below the view (see -[NSToolbarItem drawInRect:]);
    // without a label (icon-only mode) the view has the whole height.
    if (labelHeight > 0) {
        rect.size.height -= labelHeight + 4;
        rect.origin.y += labelHeight + 4;
    }
    return rect;
}

// -setFrame: goes through -setFrameSize: as well.
- (void) setFrameSize: (NSSize) size {
    [super setFrameSize: size];
    if ([_toolbarItem view] != nil) {
        // Fix up the item viewWe
        NSView *view = [_toolbarItem view];
        // Center the subview within the bounds
        NSRect availableRect = [self availableRectForSubview];
        NSRect viewRect = [view frame];

        // An item that has no sizes of its own makes its view the size it asks for.
        if ([_toolbarItem _sizeFollowsView])
            viewRect.size = [_toolbarItem _viewSize];

        // Center the subview within the available bounds, both ways, so that views of
        // different heights line up on the middle of the toolbar and none sticks out of it.
        viewRect.origin.x = NSMinX(availableRect) +
                            (NSWidth(availableRect) - NSWidth(viewRect)) / 2.f;
        viewRect.origin.y = NSMinY(availableRect) +
                            floor((NSHeight(availableRect) - NSHeight(viewRect)) / 2);
        [view setFrame: viewRect];
    }
}
- (NSView *) view {
    return [[self subviews] lastObject];
}

// An item that has no sizes of its own is laid out again when its view's intrinsic
// content size changes (a pop-up button shows a longer title, for example).
- (void) _subviewIntrinsicContentSizeDidChange: (NSView *) subview {
    [super _subviewIntrinsicContentSizeDidChange: subview];
    if (subview == [_toolbarItem view] && [_toolbarItem _sizeFollowsView])
        [[_toolbarItem toolbar] _itemViewIntrinsicSizeDidChange: _toolbarItem];
}

typedef struct {
    CGFloat _C0[4];
    CGFloat _C1[4];
} gradientColors;

static void evaluate(void *info, const CGFloat *in, CGFloat *output) {
    CGFloat x = in[0];
    gradientColors *colors = info;
    int i;

    for (i = 0; i < 4; i++)
        output[i] = colors->_C0[i] + x * (colors->_C1[i] - colors->_C0[i]);
}

const CGFloat kFillGrayLevel = 0.75;
const CGFloat kEdgeGrayLevel = 0.5;
const CGFloat kEdgeThickness = 2.f;

- (void) drawRect: (NSRect) rect {
    if ([[_toolbarItem itemIdentifier]
                isEqual: [[_toolbarItem toolbar] selectedItemIdentifier]]) {

        NSArray *colors = [NSArray
                arrayWithObjects:
                        [NSColor colorWithCalibratedWhite: kFillGrayLevel
                                                    alpha: 0],
                        [NSColor colorWithCalibratedWhite: kFillGrayLevel
                                                    alpha: 0.5],
                        [NSColor colorWithCalibratedWhite: kFillGrayLevel
                                                    alpha: 1],
                        [NSColor colorWithCalibratedWhite: kFillGrayLevel
                                                    alpha: 0.0],
                        nil];
        NSGradient *gradient =
                [[[NSGradient alloc] initWithColors: colors] autorelease];
        [gradient drawInRect: [self bounds] angle: 270];

        // fill the edges
        colors = [NSArray
                arrayWithObjects:
                        [NSColor colorWithCalibratedWhite: kEdgeGrayLevel
                                                    alpha: 0],
                        [NSColor colorWithCalibratedWhite: kEdgeGrayLevel
                                                    alpha: 1],
                        [NSColor colorWithCalibratedWhite: kEdgeGrayLevel
                                                    alpha: 0.0],
                        nil];
        gradient = [[[NSGradient alloc] initWithColors: colors] autorelease];
        NSRect edgeRect = [self bounds];
        edgeRect.size.width = kEdgeThickness;
        [gradient drawInRect: edgeRect angle: 270];
        edgeRect.origin.x = NSMaxX([self bounds]) - kEdgeThickness;
        [gradient drawInRect: edgeRect angle: 270];
    }
    [_toolbarItem drawInRect: [self bounds] highlighted: _isHighlighted];
}

- (void) mouseDown: (NSEvent *) event {
    BOOL sendAction = NO;

    if (![_toolbarItem isEnabled])
        return;

    do {
        NSPoint point = [self convertPoint: [event locationInWindow]
                                  fromView: nil];

        _isHighlighted = NSMouseInRect(point, [self bounds], [self isFlipped]);

        [self setNeedsDisplay: YES];
        event = [[self window] nextEventMatchingMask: NSLeftMouseUpMask |
                                                      NSLeftMouseDraggedMask];
    } while ([event type] != NSLeftMouseUp);

    if (_isHighlighted) {
        _isHighlighted = NO;
        [[_toolbarItem toolbar]
                didSelectToolbarItem: [_toolbarItem itemIdentifier]];
        [NSApp sendAction: [_toolbarItem action]
                       to: [_toolbarItem target]
                     from: _toolbarItem];
        [self setNeedsDisplay: YES];
    }
}

@end
