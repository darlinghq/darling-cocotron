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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSSubmenuView.h>

@implementation NSSubmenuView

// The menu window has no frame line; the item rows start 4 points below the top and end 4 points above the
// bottom (WINDOW_VERTICAL_PADDING), and the selection runs the full width of the menu.
#define WINDOW_BORDER_THICKNESS 0
#define WINDOW_VERTICAL_PADDING 4
// An item with an image is taller than the row by this much (measured: a 16 point image gives a 21 point row).
#define IMAGE_ROW_EXTRA 5

- (NSSize) sizeForMenuItemImage: (NSMenuItem *) item {
    NSSize result = NSZeroSize;

    if ([item image] != nil)
        result = [[item image] size];

    return result;
}

// The width of the part of an item left of its key equivalent: indentation, image and title.
- (CGFloat) leadingWidthForItem: (NSMenuItem *) item {
    NSGraphicsStyle *style = [self graphicsStyle];
    CGFloat width = [item indentationLevel] * [style menuItemIndentationWidth];
    NSSize imageSize = [self sizeForMenuItemImage: item];
    NSAttributedString *atitle = [item attributedTitle];

    if (imageSize.width > 0)
        width += imageSize.width + [style menuItemImageTitleGap];
    if (atitle != nil && [atitle length] > 0)
        width += [style menuItemAttributedTextSize: atitle].width;
    else
        width += [style menuItemTextSize: [item title]].width;
    return width;
}

- (NSSize) contentSizeForItem: (NSMenuItem *) item {
    NSGraphicsStyle *style = [self graphicsStyle];

    if ([item isSeparatorItem])
        return [style menuItemSeparatorSize];

    CGFloat height = [style menuItemRowHeight];
    NSSize imageSize = [self sizeForMenuItemImage: item];
    NSAttributedString *atitle = [item attributedTitle];

    if (imageSize.width > 0)
        height = MAX(height, imageSize.height + IMAGE_ROW_EXTRA);
    if (atitle != nil && [atitle length] > 0)
        height = MAX(height, [style menuItemAttributedTextSize: atitle].height);
    return NSMakeSize([self leadingWidthForItem: item], height);
}

- (NSSize) sizeForMenuItems: (NSArray *) items {
    NSGraphicsStyle *style = [self graphicsStyle];
    CGFloat maxKeyWidth = 0.0f;
    CGFloat totalHeight = 0.0f;
    unsigned i, count = [items count];

    // Separators at the end of the menu add nothing to its size (measured: an item followed by one or two
    // separators is as high as the item alone; black-box on macOS 10.14.4, tier 2).
    unsigned end = count;
    while (end > 0 && [[items objectAtIndex: end - 1] isSeparatorItem])
        end--;

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        if (i < end)
            totalHeight += [self contentSizeForItem: item].height;
        if ([item isSeparatorItem])
            continue;

        if ([[item keyEquivalent] length] != 0)
            maxKeyWidth = MAX(maxKeyWidth, [style menuItemTextSize: [item _keyEquivalentDescription]].width);
    }

    // Each row needs its own width: the title and the space after it, which is the trailing margin, or the
    // submenu arrow's column (39 points more), or a key equivalent after the gap; the menu is as wide as the widest.
    CGFloat gutter = [style menuItemGutterSize].width;
    CGFloat titleBased = 0.0f, keyBased = 0.0f;

    for (i = 0; i < end; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        if ([item isSeparatorItem])
            continue;

        CGFloat leading = gutter + [self leadingWidthForItem: item];

        if ([item hasSubmenu])
            titleBased = MAX(titleBased, leading + [style menuItemTrailingMargin] + [style menuItemSubmenuColumnWidth]);
        else
            titleBased = MAX(titleBased, leading + [style menuItemTrailingMargin]);
        if ([[item keyEquivalent] length] != 0)
            keyBased = MAX(keyBased, leading + [style menuItemKeyEquivalentGap] + maxKeyWidth +
                                             [style menuItemKeyEquivalentRightMargin] + 1);
    }
    NSSize result;
    result.width = MAX(titleBased, keyBased);
    result.height = totalHeight + WINDOW_VERTICAL_PADDING * 2;
    return result;
}

- initWithMenu: (NSMenu *) menu {
    NSRect frame = NSZeroRect;

    [self initWithFrame: frame];

    NS_EXTRA(NSView, self)->_menu = [menu retain];
    _selectedItemIndex = NSNotFound;

    frame.size = [self sizeForMenuItems: [self visibleItemArray]];
    [self setFrame: frame];

    return self;
}

- (BOOL) isFlipped {
    return YES;
}

static NSRect boundsToTitleAreaRect(NSRect rect) {
    return NSInsetRect(rect, WINDOW_BORDER_THICKNESS, WINDOW_VERTICAL_PADDING);
}

// The rows' area, moved up by what is scrolled off.
- (NSRect) itemAreaRect {
    NSRect result = boundsToTitleAreaRect([self bounds]);

    result.origin.y -= _scrollOffset;
    return result;
}

// The height of the zone at each end of a scrolling menu that holds the scroll arrow; the rows run under it.
- (CGFloat) scrollZoneHeight {
    return [[self graphicsStyle] menuItemRowHeight];
}

- (void) limitHeightTo: (CGFloat) height {
    NSRect frame = [self frame];

    if (frame.size.height <= height || height < 3 * [self scrollZoneHeight])
        return;
    _contentHeight = frame.size.height;
    _scrollOffset = 0;
    frame.size.height = height;
    [self setFrame: frame];
}

- (BOOL) scrolls {
    return _contentHeight > 0;
}

- (CGFloat) maxScrollOffset {
    return [self scrolls] ? _contentHeight - NSHeight([self bounds]) : 0;
}

- (void) scrollToOffset: (CGFloat) offset {
    offset = MAX(0, MIN(offset, [self maxScrollOffset]));
    if (offset != _scrollOffset) {
        _scrollOffset = offset;
        [self setNeedsDisplay: YES];
    }
}

// Scrolls just far enough to show a row completely, clear of the scroll arrows.
- (void) scrollRowToVisible: (NSUInteger) index {
    if (![self scrolls] || index == NSNotFound)
        return;
    NSRect row = [self rectForItemAtIndex: index];
    CGFloat zone = [self scrollZoneHeight], top = zone, bottom = NSHeight([self bounds]) - zone;

    if (_scrollOffset <= 0)
        top = 0;
    if (_scrollOffset >= [self maxScrollOffset])
        bottom = NSHeight([self bounds]);
    if (NSMinY(row) < top)
        [self scrollToOffset: _scrollOffset - (top - NSMinY(row))];
    else if (NSMaxY(row) > bottom)
        [self scrollToOffset: _scrollOffset + (NSMaxY(row) - bottom)];
}

- (void) setSelectedItemIndex: (NSUInteger) itemIndex {
    [super setSelectedItemIndex: itemIndex];
    [self scrollRowToVisible: itemIndex];
}

// The scroll wheel scrolls the rows.
- (void) scrollWheel: (NSEvent *) event {
    if ([self scrolls])
        [self scrollToOffset: _scrollOffset - [event deltaY] * [[self graphicsStyle] menuItemRowHeight]];
}

- (CGFloat) heightOfMenuItem: (NSMenuItem *) item {
    NSSize titleSize = [self contentSizeForItem: item];

    return titleSize.height;
}

- (void) drawRect: (NSRect) rect {
    NSRect bounds = [self bounds];
    NSRect itemArea = [self itemAreaRect];
    NSArray *items = [self visibleItemArray];
    unsigned i, count = [items count];
    NSPoint origin = itemArea.origin;
    NSGraphicsStyle *style = [self graphicsStyle];
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

    [style drawMenuWindowBackgroundInRect: rect];

    CGContextSaveGState(context);
    [style clipToMenuWindowShape];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        if ([item isSeparatorItem]) {
            NSRect separatorRect = NSMakeRect(origin.x, origin.y, NSWidth(itemArea), [style menuItemSeparatorSize].height);

            [style drawMenuSeparatorInRect: separatorRect];

            origin.y += NSHeight(separatorRect);
        } else {
            NSImage *image = [item image];
            BOOL selected = (i == _selectedItemIndex) ? YES : NO;
            CGFloat itemHeight = [self heightOfMenuItem: item];
            BOOL showsEnabled = ([item isEnabled] || [item hasSubmenu]);
            NSRect rowRect = NSMakeRect(origin.x, origin.y, itemArea.size.width, itemHeight);
            NSSize gutterSize = [style menuItemGutterSize];

            if (selected)
                [style drawMenuSelectionInRect: rowRect enabled: showsEnabled];

            // The state mark, in the gutter column at the left edge.
            NSImage *stateImage = nil;
            if ([item state] == NSControlStateValueOn)
                stateImage = [item onStateImage];
            else if ([item state] == NSControlStateValueMixed)
                stateImage = [item mixedStateImage];
            else
                stateImage = [item offStateImage];
            if (stateImage != nil) {
                NSRect gutterRect = NSMakeRect(origin.x, origin.y, gutterSize.width, itemHeight);

                [style drawMenuGutterInRect: gutterRect];
                [style drawMenuStateImage: stateImage inRect: gutterRect enabled: showsEnabled selected: selected];
            }

            CGFloat x = origin.x + gutterSize.width + [item indentationLevel] * [style menuItemIndentationWidth];

            // The image, then the title after it.
            if (image) {
                NSSize imageSize = [image size];
                NSRect drawingRect = NSMakeRect(x, origin.y + floor((itemHeight - imageSize.height) / 2), imageSize.width,
                                                imageSize.height);

                CGContextSaveGState(context);
                CGContextTranslateCTM(context, drawingRect.origin.x, drawingRect.origin.y);
                if ([self isFlipped]) {
                    CGContextTranslateCTM(context, 0, drawingRect.size.height);
                    CGContextScaleCTM(context, 1, -1);
                }
                drawingRect.origin = NSZeroPoint;
                [style drawButtonImage: image inRect: drawingRect enabled: showsEnabled mixed: NO];
                CGContextRestoreGState(context);

                x += imageSize.width + [style menuItemImageTitleGap];
            }

            NSAttributedString *atitle = [item attributedTitle];
            NSRect textRect = NSMakeRect(x, origin.y, 0, 0);

            if (atitle != nil && [atitle length] > 0) {
                textRect.size = [style menuItemAttributedTextSize: atitle];
                textRect.origin.y = origin.y + (itemHeight - textRect.size.height) / 2;
                [style drawAttributedMenuItemText: atitle inRect: textRect enabled: showsEnabled selected: selected];
            } else {
                textRect.size = [style menuItemTextSize: [item title]];
                textRect.origin.y = origin.y + (itemHeight - textRect.size.height) / 2;
                [style drawMenuItemText: [item title] inRect: textRect enabled: showsEnabled selected: selected];
            }

            // The key equivalent, ending at a fixed distance from the right edge.
            if ([[item keyEquivalent] length] != 0) {
                NSString *keyString = [item _keyEquivalentDescription];
                NSSize keySize = [style menuItemTextSize: keyString];
                NSRect keyRect = NSMakeRect(NSMaxX(itemArea) - [style menuItemKeyEquivalentRightMargin] - keySize.width,
                                            origin.y + (itemHeight - keySize.height) / 2, keySize.width, keySize.height);

                [style drawMenuItemText: keyString inRect: keyRect enabled: showsEnabled selected: selected];
            }

            // The submenu arrow.
            if ([item hasSubmenu]) {
                NSSize arrowSize = [style menuItemBranchArrowSize];
                NSRect arrowRect = NSMakeRect(NSMaxX(itemArea) - [style menuItemBranchArrowMargins].right - arrowSize.width,
                                              origin.y + (itemHeight - arrowSize.height) / 2, arrowSize.width,
                                              arrowSize.height);

                [style drawMenuBranchArrowInRect: arrowRect enabled: showsEnabled selected: selected];
            }

            origin.y += itemHeight;
        }
    }

    if ([self scrolls]) {
        CGFloat zone = [self scrollZoneHeight];

        if (_scrollOffset > 0)
            [style drawMenuScrollArrowUp: YES inRect: NSMakeRect(0, 0, NSWidth(bounds), zone)];
        if (_scrollOffset < [self maxScrollOffset])
            [style drawMenuScrollArrowUp: NO inRect: NSMakeRect(0, NSHeight(bounds) - zone, NSWidth(bounds), zone)];
    }
    CGContextRestoreGState(context);
}

- (NSUInteger) itemIndexAtPoint: (NSPoint) point {
    NSArray *items = [self itemArray];
    NSUInteger i, count = [items count];
    NSRect check = [self itemAreaRect];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        check.size.height = [self heightOfMenuItem: item];

        if (NSMouseInRect(point, check, [self isFlipped]))
            return i;

        check.origin.y += check.size.height;
    }

    return NSNotFound;
}

- (NSUInteger) itemIndexAtPoint: (NSPoint) point rect: (NSRect*) rect {
    NSArray *items = [self itemArray];
    NSUInteger i, count = [items count];
    NSRect check = [self itemAreaRect];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        check.size.height = [self heightOfMenuItem: item];

        if (NSMouseInRect(point, check, [self isFlipped])) {
            *rect = check;
            return i;
        }
            
        check.origin.y += check.size.height;
    }

    return NSNotFound;
}

- (NSRect) rectForItemAtIndex: (NSUInteger) index {
    NSArray *items = [self itemArray];
    NSUInteger i, count = [items count];
    NSRect rect = [self itemAreaRect];

    for (i = 0; i < count; i++) {
        rect.size.height = [self heightOfMenuItem: [items objectAtIndex: i]];
        if (i == index)
            return rect;
        rect.origin.y += rect.size.height;
    }
    return NSZeroRect;
}

- (void) positionBranchForSelectedItem: (NSWindow *) branch
                                screen: (NSScreen *) screen
{
    NSRect branchFrame = [branch frame];
    NSRect screenVisible = [screen visibleFrame];
    NSArray *items = [self itemArray];
    NSUInteger i, count = [items count];
    NSRect itemRect = [self itemAreaRect];
    NSPoint topLeft = NSZeroPoint;

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];

        itemRect.size.height = [self heightOfMenuItem: item];

        if (i == _selectedItemIndex) {
            topLeft = itemRect.origin;

            topLeft.x += itemRect.size.width;
            // the branch's first row lines up with this item, so its window starts its padding above the item
            topLeft.y -= WINDOW_VERTICAL_PADDING;

            break;
        }

        itemRect.origin.y += itemRect.size.height;
    }

    topLeft = [self convertPoint: topLeft toView: nil];
    topLeft = [[self window] convertBaseToScreen: topLeft];

    if (topLeft.y - branchFrame.size.height < NSMinY(screenVisible)) {
        topLeft = itemRect.origin;

        topLeft.x += itemRect.size.width;
        topLeft.y += itemRect.size.height;
        topLeft.y += WINDOW_VERTICAL_PADDING;

        topLeft = [self convertPoint: topLeft toView: nil];
        topLeft = [[self window] convertBaseToScreen: topLeft];

        topLeft.y += branchFrame.size.height;
    }

    if (topLeft.x + branchFrame.size.width > NSMaxX(screenVisible)) {
        NSPoint redo = itemRect.origin;

        redo = [self convertPoint: redo toView: nil];
        redo = [[self window] convertBaseToScreen: redo];
        redo.x -= branchFrame.size.width;

        topLeft.x = redo.x;
    }

    [branch setFrameTopLeftPoint: topLeft];
}

- (NSMenuView *) viewAtSelectedIndexPositionOnScreen: (NSScreen *) screen {
    NSArray *items = [self visibleItemArray];

    if (_selectedItemIndex < [items count]) {
        NSMenuItem *item = [items objectAtIndex: _selectedItemIndex];

        if ([item hasSubmenu]) {
            [[item submenu] _updateWithoutSubmenus];

            NSMenuWindow *branch =
                    [[NSMenuWindow alloc] initWithMenu: [item submenu]];

            [self positionBranchForSelectedItem: branch screen: screen];

            [branch orderFront: nil];
            return [branch menuView];
        }
    }
    return nil;
}

@end

/*@implementation MenuMetrics

-(id)initWithStyle:(NSGraphicsStyle *)style
{
        checkBoxMargins = [style menuItemCheckBoxMargins];
        checkBoxBackgroundMargins = [style menuItemCheckBoxBackgroundMargins];
        itemMargins = [style menuItemMargins];
    keyEquivalentMargins = [style menuItemKeyEquivalentMargins];

        checkMarkSize = [style menuItemCheckMarkSize];
        separatorSize = [style menuItemSeparatorSize];

        minTitleKeyEquivalentWidth = [style minimumTitleKeyEquivalentWidth];
        extraTitleGutterMargin = [style extraTitleGutterMargin];

        titleMargins = itemMargins;
        titleMargins.left = [style menuBorderBackgroundSize].width;
        titleMargins.right = [style menuBorderSize].width;

        extraCheckMarkHeight = checkBoxBackgroundMargins.top +
checkBoxBackgroundMargins.bottom;
}

-(Margins)checkMarkMargins
{
        return checkMarkMargins;
}

-(Margins)checkMarkBackgroundMargins
{
        return checkMarkBackgroundMargins;
}

-(Margins)itemMargins
{
        return itemMargins;
}

-(Margins)titleMargins
{
        return titleMargins;
}

-(Margins)keyEquivalentMargins
{
        return keyEquivalentMargins;
}

-(NSSize)checkMarkSize
{
        return checkMarkSize;
}

-(NSSize)separatorSize
{
        return separatorSize;
}

-(CGFloat)minTitleKeyEquivalentWidth
{
        return minTitleKeyEquivalentWidth;
}

-(CGFloat)extraTitleGutterMargin
{
        return extraTitleGutterMargin;
}

-(CGFloat)extraCheckMarkHeight
{
        return extraCheckMarkHeight;
}


@end
*/
