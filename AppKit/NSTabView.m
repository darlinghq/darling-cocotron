/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#import <AppKit/NSColor.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSMatrix.h>
#import <AppKit/NSPopUpButton.h> // for indexOfSelectedItem definition
#import <AppKit/NSRaise.h>
#import <AppKit/NSTabView.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSTabViewItem.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

id _NSTabViewFloatingCell = nil;

@interface NSTabViewItem (NSTabViewItem_private)
- (void) setTabView: (NSTabView *) tabView;
- (void) setTabState: (NSTabState) tabState;
@end

@implementation NSTabView

- initWithCoder: (NSCoder *) coder {
    // The class version is asked before the superclass part is decoded.
    NSInteger version = [coder allowsKeyedCoding] ? 0 : [coder versionForClassName: @"NSTabView"];

    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
        unsigned flags = [keyed decodeIntForKey: @"NSTvFlags"];

        _items = [[NSMutableArray alloc]
                initWithArray: [keyed decodeObjectForKey: @"NSTabViewItems"]];
        _selectedItem = [keyed decodeObjectForKey: @"NSSelectedTabViewItem"];
        _allowsTruncatedLabels =
                [keyed decodeBoolForKey: @"NSAllowTruncatedLabels"];
        _drawsBackground = [keyed decodeBoolForKey: @"NSDrawsBackground"];
        _controlSize = (flags & 0x18000000) >> 27;
        if (_font == nil)
            _font = [[NSFont boldSystemFontOfSize: 13 - _controlSize * 2]
                    retain];
        _type = (flags & 0x7);
    } else {
        // Layout per class version as recorded from Mac archives: the tab view items, the
        // selected item and the font, the tab type, the allows-truncated-labels byte
        // and, from version 2, the draws-background byte, then the delegate. Before
        // version 2 the background is always drawn.
        id items = nil, selectedItem = nil;
        int type = 0;
        char allowsTruncatedLabels = 0, drawsBackground = 1;

        if (version >= 2) {
            [coder decodeValuesOfObjCTypes: "@@@icc", &items, &selectedItem, &_font, &type, &allowsTruncatedLabels,
                                            &drawsBackground];
        } else {
            [coder decodeValuesOfObjCTypes: "@@@ic", &items, &selectedItem, &_font, &type, &allowsTruncatedLabels];
        }
        _delegate = [coder decodeObject];

        _items = [items isKindOfClass: [NSArray class]] ? [items mutableCopy] : [[NSMutableArray alloc] init];
        [items release];
        // The selected item's view is among the decoded subviews already.
        _selectedItem = [_items containsObject: selectedItem] ? selectedItem : nil;
        [selectedItem release];
        for (NSTabViewItem *item in _items)
            [item setTabState: item == _selectedItem ? NSSelectedTab : NSBackgroundTab];
        _type = (NSTabViewType) type;
        _allowsTruncatedLabels = allowsTruncatedLabels != 0;
        _drawsBackground = drawsBackground != 0;
        if (_font == nil)
            _font = [[NSFont boldSystemFontOfSize: 13] retain];
    }

    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    _items = [NSMutableArray new];
    _selectedItem = nil;
    // should probably be boldUserFont
    _font = [[NSFont boldSystemFontOfSize: 0] retain];
    _type = NSTopTabsBezelBorder;
    _position = NSTabPositionTop;
    _allowsTruncatedLabels = NO;
    return self;
}

- (void) dealloc {
    [_items release];
    _selectedItem = nil;
    [_font release];
    [super dealloc];
}

- delegate {
    return _delegate;
}

- (NSControlSize) controlSize {
    return _controlSize;
}

- (void) setControlSize: (NSControlSize) controlSize {
    _controlSize = controlSize;
    [self setNeedsDisplay: YES];
}

- (NSSize) minimumSize {
    switch (_type) {
    case NSTopTabsBezelBorder:
    case NSLeftTabsBezelBorder:
    case NSBottomTabsBezelBorder:
    case NSRightTabsBezelBorder: {
        NSSize finalSize;
        NSInteger i, count = [_items count];

        if (count == 0)
            break;

        finalSize =
                [[_items objectAtIndex: 0] sizeOfLabel: _allowsTruncatedLabels];
        for (i = 1; i < count; ++i)
            finalSize.width += [[_items objectAtIndex: i]
                                       sizeOfLabel: _allowsTruncatedLabels]
                                       .width;

        return finalSize;
    }

    case NSNoTabsBezelBorder:
    case NSNoTabsLineBorder:
    case NSNoTabsNoBorder:
    default:
        break;
    }

    return NSMakeSize(0, 0); // correct?
}

/* Distances from the view's edges to the content area (left, top, right, bottom), measured
   on macOS for a flipped tab view. The tab strip adds to the side that carries the tabs. */
typedef struct {
    CGFloat left, top, right, bottom;
} NSTabViewMargins;

static NSTabViewMargins NSTabViewContentMargins(NSTabViewType type, NSControlSize size) {
    static const NSTabViewMargins top[3] = {{10, 33, 10, 13}, {10, 25, 10, 13}, {10, 19, 10, 13}};
    static const NSTabViewMargins left[3] = {{32, 7, 10, 13}, {30, 7, 10, 13}, {28, 7, 10, 13}};
    static const NSTabViewMargins bottom[3] = {{10, 7, 10, 31}, {10, 7, 10, 29}, {10, 7, 10, 28}};
    static const NSTabViewMargins right[3] = {{10, 7, 31, 13}, {10, 7, 29, 13}, {10, 7, 28, 13}};
    int index = size == NSSmallControlSize ? 1 : (size == NSMiniControlSize ? 2 : 0);

    switch (type) {
    case NSTopTabsBezelBorder:
        return top[index];
    case NSLeftTabsBezelBorder:
        return left[index];
    case NSBottomTabsBezelBorder:
        return bottom[index];
    case NSRightTabsBezelBorder:
        return right[index];
    case NSNoTabsBezelBorder:
        return (NSTabViewMargins){10, 7, 10, 13};
    case NSNoTabsLineBorder:
        return (NSTabViewMargins){1, 1, 1, 1};
    case NSNoTabsNoBorder:
    default:
        return (NSTabViewMargins){0, 0, 0, 0};
    }
}

- (BOOL) isFlipped {
    return YES;
}

- (NSRect) contentRect {
    NSTabViewMargins m = NSTabViewContentMargins(_type, _controlSize);
    NSRect bounds = [self bounds];

    return NSMakeRect(m.left, m.top, bounds.size.width - m.left - m.right,
                      bounds.size.height - m.top - m.bottom);
}

/* The bezel or pane drawn around the content. The tab strip sits above it. Only top tabs have a
   drawn layout of their own: the other three tab positions draw like top tabs. */
- (NSRect) rectForBorder {
    switch (_type) {
    case NSTopTabsBezelBorder:
    case NSLeftTabsBezelBorder:
    case NSBottomTabsBezelBorder:
    case NSRightTabsBezelBorder: {
        NSTabViewMargins m = NSTabViewContentMargins(NSTopTabsBezelBorder, _controlSize);
        NSRect bounds = [self bounds];

        return NSMakeRect(m.left - 2, m.top - 2, bounds.size.width - m.left - m.right + 4,
                          bounds.size.height - m.top - m.bottom + 4);
    }

    case NSNoTabsBezelBorder:
        return NSInsetRect([self contentRect], -2, -2);

    case NSNoTabsLineBorder:
    case NSNoTabsNoBorder:
    default:
        return [self bounds];
    }
}

- (NSFont *) font {
    return _font;
}

- (NSTabViewType) tabViewType {
    return _type;
}

- (NSTabPosition) tabPosition {
    return _position;
}

- (BOOL) drawsBackground {
    return _drawsBackground;
}

- (BOOL) allowsTruncatedLabels {
    return _allowsTruncatedLabels;
}

- (void) setDelegate: delegate {
    _delegate = delegate;
}

- (void) setFont: (NSFont *) font {
    font = [font retain];
    [_font release];
    _font = font;
}

- (void) setTabViewType: (NSTabViewType) type {
    _type = type;
    [self setNeedsDisplay: YES];
}

- (void) setTabPosition: (NSTabPosition) position {
    // TODO: Implement
    NSLog(@"-[NSTabView tabPosition] Is Currently Unimplemented");
    _position = position;
    [self setNeedsDisplay: YES];
}

- (void) setDrawsBackground: (BOOL) flag {
    _drawsBackground = flag;
    [self setNeedsDisplay: YES];
}

- (void) setAllowsTruncatedLabels: (BOOL) flag {
    _allowsTruncatedLabels = flag;
    [self setNeedsDisplay: YES];
}

- (NSInteger) numberOfTabViewItems {
    return [_items count];
}

- (NSArray *) tabViewItems {
    return _items;
}

- (NSTabViewItem *) tabViewItemAtIndex: (NSInteger) index {
    return [_items objectAtIndex: index];
}

- (NSRect) rectForItemLabelAtIndex: (NSUInteger) index {
    NSInteger i, count = [_items count];
    NSPoint base = NSMakePoint(0, 0);
    NSSize size;

    base.x += 6;
    for (i = 0; i < count && i < index; i++) {
        size = [[_items objectAtIndex: i] sizeOfLabel: NO];

        base.x += size.width;
        base.x += 8;
    }

    size = [[_items objectAtIndex: index] sizeOfLabel: NO];

    base.y = NSMinY([self rectForBorder]) - 2 - size.height;

    return NSMakeRect(base.x, base.y, size.width, size.height);
}

- (NSTabViewItem *) tabViewItemAtPoint: (NSPoint) point {
    NSInteger i, count = [_items count];

    for (i = 0; i < count; i++) {
        NSTabViewItem *item = [_items objectAtIndex: i];
        NSRect rect = [self rectForItemLabelAtIndex: i];

        if (NSMouseInRect(point, rect, [self isFlipped]))
            return item;
    }

    return nil;
}

- (NSInteger) indexOfTabViewItem: (NSTabViewItem *) item {
    return [_items indexOfObject: item];
}

- (NSInteger) indexOfTabViewItemWithIdentifier: identifier {
    NSInteger i, count = [_items count];

    for (i = 0; i < count; ++i)
        if ([[(NSTabViewItem *) [_items objectAtIndex: i] identifier]
                    isEqual: identifier])
            return i;

    return NSNotFound;
}

- (void) addTabViewItem: (NSTabViewItem *) item {
    [_items addObject: item];
    [item setTabView: self];
    if (_selectedItem == nil)
        [self selectTabViewItem: item];

    if ([_delegate respondsToSelector: @selector
                   (tabViewDidChangeNumberOfTabViewItems:)])
        [_delegate tabViewDidChangeNumberOfTabViewItems: self];

    [self setNeedsDisplay: YES];
}

- (void) removeTabViewItem: (NSTabViewItem *) item {
    NSInteger selectedIndex = [self indexOfTabViewItem: _selectedItem];
    if (item == _selectedItem) {
        NSInteger newIndex = selectedIndex - 1;

        if (newIndex < 0) {
            newIndex = selectedIndex + 1;

            if (newIndex >= [self numberOfTabViewItems]) {
                newIndex = NSNotFound;
            }
        }

        if (newIndex == NSNotFound) {
            [[_selectedItem view] removeFromSuperview];
            _selectedItem = nil;
        } else {
            [self selectTabViewItemAtIndex: newIndex];
        }
    }

    [_items removeObject: item];

    if ([_delegate respondsToSelector: @selector
                   (tabViewDidChangeNumberOfTabViewItems:)])
        [_delegate tabViewDidChangeNumberOfTabViewItems: self];

    [self setNeedsDisplay: YES];
}

- (void) insertTabViewItem: (NSTabViewItem *) item atIndex: (NSInteger) index {
    [_items insertObject: item atIndex: index];
    [item setTabView: self];
    if (_selectedItem == nil)
        [self selectTabViewItem: item];

    if ([_delegate respondsToSelector: @selector
                   (tabViewDidChangeNumberOfTabViewItems:)])
        [_delegate tabViewDidChangeNumberOfTabViewItems: self];

    [self setNeedsDisplay: YES];
}

- (NSTabViewItem *) selectedTabViewItem {
    return _selectedItem;
}

- (void) setFrameSize: (NSSize) size {
    /* A tab view will autoresize the selected view regardless of whether
       autoresizesSubviews is enabled We do it here because
       resizeSubviewsWithOldSize: won't be called if autoresizesSubviews is off.
       -setFrame: goes through -setFrameSize: as well.
     */

    [super setFrameSize: size];
    if (_selectedItem != nil)
        [[_selectedItem view] setFrame: [self contentRect]];
}

- (void) _itemViewDidChange: (NSTabViewItem *) item {
    if (item == _selectedItem) {
        NSView *itemView = [item view];

        if (itemView != nil) {
            [self addSubview: itemView];
            [itemView setFrame: [self contentRect]];
        }
        [self setNeedsDisplay: YES];
    }
}

// delegate methods go here
- (void) selectTabViewItem: (NSTabViewItem *) item {
    if (item != _selectedItem) {
        BOOL selectItem = YES;

        if ([_delegate respondsToSelector: @selector(tabView:
                                                   shouldSelectTabViewItem:)])
            selectItem = [_delegate tabView: self
                    shouldSelectTabViewItem: item];

        if (selectItem) {
            if ([_delegate respondsToSelector: @selector(tabView:
                                                       willSelectTabViewItem:)])
                [_delegate tabView: self willSelectTabViewItem: item];

            [[_selectedItem view] removeFromSuperview];
            if ([item view] != nil) {
                [self addSubview: [item view]];
                [[item view] setFrame: [self contentRect]];
            }
            [self setNeedsDisplay: YES];
            _selectedItem = item;

            if ([item initialFirstResponder])
                [[self window]
                        makeFirstResponder: [item initialFirstResponder]];

            if ([_delegate respondsToSelector: @selector(tabView:
                                                       didSelectTabViewItem:)])
                [_delegate tabView: self didSelectTabViewItem: item];
        }
        // Since we're not opaque, we need to redraw the superview too
        // Shouldn't the view machinery do this automatically?? it might now
        [[self superview] setNeedsDisplay: YES];
    }
}

- (void) selectTabViewItemAtIndex: (NSInteger) index {
    [self selectTabViewItem: [_items objectAtIndex: index]];
}

- (void) selectTabViewItemWithIdentifier: identifier {
    [self selectTabViewItemAtIndex:
                    [self indexOfTabViewItemWithIdentifier: identifier]];
}

- (void) selectFirstTabViewItem: sender {
    [self selectTabViewItem: ([_items count] == 0) ? nil
                                                   : [_items objectAtIndex: 0]];
}

- (void) selectLastTabViewItem: sender {
    [self selectTabViewItem: [_items lastObject]];
}

- (void) takeSelectedTabViewItemFromSender: sender {
    if ([sender respondsToSelector: @selector(indexOfSelectedItem)])
        [self selectTabViewItemAtIndex: [sender indexOfSelectedItem]];
    else if ([sender isKindOfClass: [NSMatrix class]])
        [self selectTabViewItemAtIndex:
                        [[sender cells] indexOfObject: [sender selectedCell]]];
}

- (NSRect) rectForItemBorderAtIndex: (unsigned) index {
    NSRect result = [self rectForItemLabelAtIndex: index];

    CGFloat paneTop = NSMinY([self rectForBorder]);
    CGFloat height = MIN(24 - (CGFloat) _controlSize, paneTop);

    result = NSInsetRect(result, -4, 0);
    result.origin.y = paneTop - height;
    result.size.height = height;

    return result;
}

/* The tab and pane shapes of the graphics style are drawn for a coordinate system with the origin
   at the bottom. The view is flipped, so the shapes are drawn through a mirrored, unflipped
   context; _mirrored converts a view rectangle for it. */
- (NSRect) _mirrored: (NSRect) rect {
    rect.origin.y = [self bounds].size.height - NSMaxY(rect);
    return rect;
}

- (NSGraphicsContext *) _beginUnflippedDrawing {
    NSGraphicsContext *current = [NSGraphicsContext currentContext];
    CGContextRef port = [current graphicsPort];

    CGContextSaveGState(port);
    CGContextTranslateCTM(port, 0, [self bounds].size.height);
    CGContextScaleCTM(port, 1, -1);
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithGraphicsPort: port flipped: NO]];
    return current;
}

- (void) _endUnflippedDrawing: (NSGraphicsContext *) saved {
    CGContextRestoreGState([saved graphicsPort]);
    [NSGraphicsContext setCurrentContext: saved];
}

- (void) drawRect: (NSRect) rect {
    NSGraphicsStyle *style = [self graphicsStyle];

    switch (_type) {
    case NSTopTabsBezelBorder:
    case NSLeftTabsBezelBorder:
    case NSBottomTabsBezelBorder:
    case NSRightTabsBezelBorder: {
        NSInteger i, count = [_items count];
        NSRect mirroredClip = [self _mirrored: rect];

        for (i = 0; i < count; i++) {
            NSTabViewItem *item = [_items objectAtIndex: i];

            // defer selected item for overlap
            if (item != _selectedItem) {
                NSGraphicsContext *saved = [self _beginUnflippedDrawing];
                [style drawTabInRect: [self _mirrored: [self rectForItemBorderAtIndex: i]]
                            clipRect: mirroredClip
                               color: [item color]
                            selected: NO];
                [self _endUnflippedDrawing: saved];
                [item drawLabel: _allowsTruncatedLabels
                         inRect: [self rectForItemLabelAtIndex: i]];
            }
        }

        NSGraphicsContext *saved = [self _beginUnflippedDrawing];
        [style drawTabPaneInRect: [self _mirrored: [self rectForBorder]]];
        [self _endUnflippedDrawing: saved];

        if ((i = [_items indexOfObjectIdenticalTo: _selectedItem]) !=
            NSNotFound) {
            // now do selected item
            NSGraphicsContext *saved = [self _beginUnflippedDrawing];
            [style drawTabInRect: [self _mirrored: [self rectForItemBorderAtIndex: i]]
                        clipRect: mirroredClip
                           color: [_selectedItem color]
                        selected: YES];
            [self _endUnflippedDrawing: saved];
            [[_selectedItem view] setNeedsDisplay: YES];

            NSRect labelRect = [self rectForItemLabelAtIndex: i];
            labelRect.origin.y -= 2;

            [_selectedItem drawLabel: _allowsTruncatedLabels inRect: labelRect];

            if ([[self window] firstResponder] == self)
                NSDottedFrameRect(NSInsetRect(labelRect, -1, 0));
        }
        break;
    }

    case NSNoTabsBezelBorder:
        NSDrawButton([self rectForBorder], rect);
        break;

    case NSNoTabsLineBorder:
        [[NSColor blackColor] setStroke];
        NSFrameRect([self rectForBorder]);
        break;

    case NSNoTabsNoBorder:
        if (_drawsBackground) {
            [[NSColor controlColor] setFill];
            NSRectFill([self rectForBorder]);
        }
        break;

    default:
        break;
    }
}

- (void) mouseDown: (NSEvent *) event {
    NSPoint point = [self convertPoint: [event locationInWindow] fromView: nil];
    NSTabViewItem *item = [self tabViewItemAtPoint: point];

    if (item != nil) {
        [_selectedItem setTabState: NSBackgroundTab];
        [self selectTabViewItem: item];

        // item is "pressed" until mouse up. this correct? docs unclear
        // IB 4.x "selects" immediately (at least visually)
        [_selectedItem setTabState: NSPressedTab];

        // Since we're not opaque, we need to redraw the superview too
        // Shouldn't the view machinery do this automatically?? it might now
        [[self superview] setNeedsDisplay: YES];
        do {
            event = [[self window]
                    nextEventMatchingMask: NSLeftMouseUpMask |
                                           NSLeftMouseDraggedMask];
        } while ([event type] != NSLeftMouseUp);

        [_selectedItem setTabState: NSSelectedTab];
    }
    [[self superview] setNeedsDisplay: YES];
}

@end

@implementation NSTabView (Bindings)

- (NSInteger) _selectedIndex {
    return [self indexOfTabViewItem: _selectedItem];
}
- (void) _setSelectedIndex: (NSInteger) selectedIndex {
    [self selectTabViewItemAtIndex: selectedIndex];
}

@end
