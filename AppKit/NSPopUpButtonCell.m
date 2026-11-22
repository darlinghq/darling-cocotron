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

#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSPopUpButtonCell.h>
#import <AppKit/NSPopUpWindow.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSKeyedArchiver.h>

NSNotificationName NSPopUpButtonCellWillPopUpNotification =
        @"NSPopUpButtonCellWillPopUpNotification";

@interface NSButtonCell (AquaToolbarBezel)
- (NSRect) _aquaBezelArtworkRectForFrame: (NSRect) frame inView: (NSView *) controlView;
@end

@implementation NSPopUpButtonCell

- init {
    self = [super init];
    NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown = NO;
    _menu = [[NSMenu alloc] init];
    _selectedIndex = -1;
    NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition = NSPopUpArrowAtCenter;
    NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge = NSMaxYEdge;
    NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem = YES;
    NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu = YES;
    // QUIRK: a new pop-up or pull-down button has the rounded bezel style. Not documented. Evidence:
    // black-box observation on macOS 10.14.4 (tier 2): -bezelStyle of a new NSPopUpButton is 1
    // (NSRoundedBezelStyle). Test: appkit-popup-aqua.m
    NS_EXTRA(NSButtonCell, self)->_bezelStyle = NSRoundedBezelStyle;
    // QUIRK: left aligned title, as in -initTextCell:pullsDown: (test_quirk_popup_title_left_aligned).
    [self setAlignment: NSTextAlignmentLeft];
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    self = [super initWithCoder: coder];
    if ([coder allowsKeyedCoding]) {
        NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown = [coder decodeBoolForKey: @"NSPullDown"];
        _menu = [[coder decodeObjectForKey: @"NSMenu"] retain];
        _selectedIndex = [coder decodeIntForKey: @"NSSelectedIndex"];
        NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition = [coder decodeIntForKey: @"NSArrowPosition"];
        NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge = [coder decodeIntForKey: @"NSPreferredEdge"];
        NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu = [coder decodeBoolForKey: @"NSUsesItemFromMenu"];
        // Written only when set (macOS 26.7.3, black-box).
        NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem = [coder decodeBoolForKey: @"NSAltersState"];

        [self synchronizeTitleAndSelectedItem];
    } else {
        int flags, selectedIndex;
        [coder decodeValuesOfObjCTypes: "i@i", &flags, &_menu, &selectedIndex];
        _selectedIndex = selectedIndex;

        // The flag word, in Mac archives: bit 31 pulls down, bits 28-29 the preferred edge,
        // bit 27 uses the item from the menu, bit 26 alters the state of the selected
        // item and bits 24-25 the arrow position.
        NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown = (flags >> 31) & 1;
        NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge = (flags >> 28) & 3;
        NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu = (flags >> 27) & 1;
        NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem = (flags >> 26) & 1;
        NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition = (flags >> 24) & 3;

        // We can't call synchronizeTitleAndSelectedItem, as the _menu may not be finished decoding and we can't access the items
        NS_EXTRA(NSPopUpButtonCell, self)->_syncTitleNeeded = YES;
    }
    return self;
}

- copyWithZone: (NSZone *) zone {
    NSPopUpButtonCell *copy = [super copyWithZone: zone];

    NS_EXTRA_COPY(NSPopUpButtonCell, copy, self);
    copy->_menu = [_menu copy];

    return copy;
}

- initTextCell: (NSString *) string pullsDown: (BOOL) pullDown {
    self = [super initTextCell: string];
    _menu = [[NSMenu alloc] initWithTitle: string ?: @""];
    // The title becomes the first item; an empty title adds none.
    if ([string length] > 0) {
        [_menu addItemWithTitle: string action: [self action] keyEquivalent: @""];
        _selectedIndex = 0;
    } else {
        _selectedIndex = -1;
    }
    NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition = NSPopUpArrowAtCenter;
    NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge = NSMaxYEdge;
    NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown = pullDown;
    NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem = YES;
    NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu = YES;
    // QUIRK: the title of a new pop-up or pull-down button is left aligned (a plain button's is centered). Not
    // documented. Evidence: black-box observation on macOS 10.14.4 (tier 2): -alignment is 0 and the rendered title
    // starts at the title area's left edge. Test: tests/appkit-popup-title-rect.m (test_quirk_popup_title_left_aligned)
    [self setAlignment: NSTextAlignmentLeft];
    // QUIRK: a new pop-up or pull-down button has the rounded bezel style. Not documented. Evidence:
    // black-box observation on macOS 10.14.4 (tier 2): -bezelStyle of a new NSPopUpButton is 1
    // (NSRoundedBezelStyle). Test: appkit-popup-aqua.m
    NS_EXTRA(NSButtonCell, self)->_bezelStyle = NSRoundedBezelStyle;
    return self;
}

- (void) dealloc {
    [_menu release];
    NS_EXTRA_FREE(NSPopUpButtonCell, self);
    [super dealloc];
}

- (BOOL) isOpaque {
    return NO;
}

- (BOOL) pullsDown {
    return NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown;
}

- (NSMenu *) menu {
    return _menu;
}

- (BOOL) usesItemFromMenu {
    return NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu;
}

- (void) setUsesItemFromMenu: (BOOL) flag {
    NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu = flag;
    [self synchronizeTitleAndSelectedItem];
}

- (void) setMenuItem: (NSMenuItem *) item {
    [super setMenuItem: item];
    if (!NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu)
        [self synchronizeTitleAndSelectedItem];
}

// The cell's menu item is the item it shows.
- (NSMenuItem *) menuItem {
    return [self _displayedItem];
}

// The item whose title and image the button shows: the selected item of a
// pop-up menu or the first item of a pull-down menu, or, when the cell does
// not use an item from its menu, the cell's own menu item (none by default).
- (NSMenuItem *) _displayedItem {
    if (!NS_EXTRA(NSPopUpButtonCell, self)->_usesItemFromMenu)
        return [super menuItem];

    NSArray *itemArray = [_menu itemArray];

    if (_selectedIndex < 0 || NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown) {
        if ([itemArray count] > 0)
            return [itemArray objectAtIndex: 0];
    } else if (_selectedIndex < [itemArray count]) {
        return [itemArray objectAtIndex: _selectedIndex];
    }
    return nil;
}

- (BOOL) autoenablesItems {
    return NS_EXTRA(NSPopUpButtonCell, self)->_autoenablesItems;
}

- (NSPopUpArrowPosition) arrowPosition {
    return NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition;
}

- (NSRectEdge) preferredEdge {
    return NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge;
}

- (NSArray *) itemArray {
    return [_menu itemArray];
}

- (NSInteger) numberOfItems {
    return [_menu numberOfItems];
}

- (NSMenuItem *) itemAtIndex: (NSInteger) index {
    return [_menu itemAtIndex: index];
}

- (NSMenuItem *) itemWithTitle: (NSString *) title {
    return [_menu itemWithTitle: title];
}

- (NSMenuItem *) lastItem {
    if ([_menu numberOfItems] == 0)
        return nil;

    return [_menu itemAtIndex: [_menu numberOfItems] - 1];
}

- (NSInteger) indexOfItem: (NSMenuItem *) item {
    return [_menu indexOfItem: item];
}

- (NSInteger) indexOfItemWithTitle: (NSString *) title {
    return [_menu indexOfItemWithTitle: title];
}

- (NSInteger) indexOfItemWithTag: (NSInteger) tag {
    return [_menu indexOfItemWithTag: tag];
}

- (NSInteger) indexOfItemWithRepresentedObject: object {
    return [_menu indexOfItemWithRepresentedObject: object];
}

- (NSInteger) indexOfItemWithTarget: target andAction: (SEL) action {
    return [_menu indexOfItemWithTarget: target andAction: action];
}

- (NSMenuItem *) selectedItem {
    if (_selectedIndex < 0)
        return nil;

    if (_selectedIndex >= [_menu numberOfItems]) {
        return nil;
    }

    return [_menu itemAtIndex: _selectedIndex];
}

- (NSString *) titleOfSelectedItem {
    return [[self selectedItem] title];
}

- (NSInteger) indexOfSelectedItem {
    return _selectedIndex;
}

- (void) setPullsDown: (BOOL) flag {
    NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown = flag;
}

- (void) setMenu: (NSMenu *) menu {
    menu = [menu retain];
    [_menu release];
    _menu = menu;

    if ([_menu numberOfItems] > 0)
        _selectedIndex = 0;
    else
        _selectedIndex = -1;

    [self synchronizeTitleAndSelectedItem];
}

- (void) setAutoenablesItems: (BOOL) value {
    NS_EXTRA(NSPopUpButtonCell, self)->_autoenablesItems = value ? YES : NO;
}

- (void) setArrowPosition: (NSPopUpArrowPosition) position {
    NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition = position;
}

- (void) setPreferredEdge: (NSRectEdge) edge {
    edge = NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge;
}

// Appends an item for the title without looking for an earlier item of the
// same title. The first item of an empty menu becomes the selected one.
- (NSMenuItem *) _appendItemWithTitle: (NSString *) title {
    NSMenuItem *item = [_menu addItemWithTitle: title
                                        action: @selector(_popUpItemAction:)
                                 keyEquivalent: @""];
    [item setTarget: self];

    if (_selectedIndex < 0) {
        _selectedIndex = 0;
        [self _setStateOfItemAtIndex: 0 to: NSControlStateValueOn];
    }
    return item;
}

- (void) _addItemWithTitle: (NSString *) title {

    NSMenuItem *duplicate = [_menu itemWithTitle: title];
    if (duplicate != nil) {
        // don't allow items with duplicate titles by default
        [_menu removeItem: duplicate];
    }

    [self _appendItemWithTitle: title];
}

- (void) addItemWithTitle: (NSString *) title {
    [self _addItemWithTitle: title];
    [self synchronizeTitleAndSelectedItem];
}

- (void) addItemsWithTitles: (NSArray *) titles {
    NSInteger i, count = [titles count];

    for (i = 0; i < count; i++)
        [self _addItemWithTitle: [titles objectAtIndex: i]];

    [self synchronizeTitleAndSelectedItem];
}

- (void) removeAllItems {
    [_menu removeAllItems];
    _selectedIndex = -1;
    [self synchronizeTitleAndSelectedItem];
}

- (void) removeItemAtIndex: (NSInteger) index {
    [_menu removeItemAtIndex: index];

    if (_selectedIndex >= [_menu numberOfItems]) {
        // Don't know what to select anymore...
        _selectedIndex = -1;
    }
    [self synchronizeTitleAndSelectedItem];
}

- (void) removeItemWithTitle: (NSString *) title {
    NSInteger index = [self indexOfItemWithTitle: title];
    [self removeItemAtIndex: index];
}

- (void) insertItemWithTitle: (NSString *) title atIndex: (NSInteger) index {
    [_menu insertItemWithTitle: title
                        action: @selector(_popUpItemAction:)
                 keyEquivalent: @""
                       atIndex: index];
    NSMenuItem *check = [_menu itemAtIndex: index];
    [check setTarget: self];

    [self synchronizeTitleAndSelectedItem];
}

- (void) selectItem: (NSMenuItem *) item {

    NSInteger selectedIndex = _selectedIndex;
    if (item == nil)
        selectedIndex = -1;
    else {
        NSInteger check = [[_menu itemArray] indexOfObjectIdenticalTo: item];

        selectedIndex = (check == NSNotFound) ? -1 : check;
    }

    if (selectedIndex != _selectedIndex) {
        [self willChangeValueForKey: @"selectedItem"];
        [self _setStateOfItemAtIndex: _selectedIndex to: NSControlStateValueOff];
        _selectedIndex = selectedIndex;
        [self didChangeValueForKey: @"selectedItem"];
    }
    [self _setStateOfItemAtIndex: _selectedIndex to: NSControlStateValueOn];
    [self synchronizeTitleAndSelectedItem];
}

- (void) selectItemAtIndex: (NSInteger) index {
    NSMenuItem *item = (index < 0) ? nil : [self itemAtIndex: index];

    [self selectItem: item];
}

- (void) selectItemWithTitle: (NSString *) title {
    [self selectItemAtIndex: [self indexOfItemWithTitle: title]];
}

- (BOOL) selectItemWithTag: (NSInteger) tag {
    NSInteger index = [self indexOfItemWithTag: tag];

    if (index < 0)
        return NO;

    [self selectItemAtIndex: index];
    return YES;
}

- (NSString *) itemTitleAtIndex: (NSInteger) index {
    return [[self itemAtIndex: index] title];
}

- (NSArray *) itemTitles {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *array = [self itemArray];
    NSInteger i, count = [array count];

    for (i = 0; i < count; i++)
        [result addObject: [[array objectAtIndex: i] title]];

    return result;
}

- (BOOL) altersStateOfSelectedItem {
    return NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem;
}

// As on macOS 26.7.3 (black-box): turning it off clears the state of every item, turning it on
// sets the selected item's state and leaves the others alone.
- (void) setAltersStateOfSelectedItem: (BOOL) flag {
    NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem = flag;
    if (flag)
        [self _setStateOfItemAtIndex: _selectedIndex to: NSControlStateValueOn];
    else
        for (NSMenuItem *item in [_menu itemArray])
            [item setState: NSControlStateValueOff];
}

// With altersStateOfSelectedItem, the item a pop-up menu selects is turned on and the one it
// selected before is turned off (macOS 26.7.3, black-box). A pull-down menu's items keep their
// states.
- (void) _setStateOfItemAtIndex: (NSInteger) index to: (NSControlStateValue) state {
    if (!NS_EXTRA(NSPopUpButtonCell, self)->_altersStateOfSelectedItem || NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown)
        return;
    if (index >= 0 && index < [_menu numberOfItems])
        [[_menu itemAtIndex: index] setState: state];
}

- (void) synchronizeTitleAndSelectedItem {
    NSMenuItem *item = [self _displayedItem];
    // With no items the title is the empty string rather than nil.
    NSString *oldTitle = [[self title] retain];

    [super setTitle: item != nil ? [item title] : @""];
    // The size of a pop-up button follows the title it shows.
    if (![oldTitle isEqual: [self title]])
        [[self controlView] invalidateIntrinsicContentSize];
    [oldTitle release];
    // For a redraw of the control
    [(NSControl *) [self controlView] updateCell: self];
}

- (NSImage *) arrowImage {
    if (NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown)
        return [NSImage imageNamed: @"NSPopUpButtonCellPullDown"];
    else
        return [NSImage imageNamed: @"NSPopUpButtonCellPopUp"];
}

- (NSRect) _arrowRectForRect: (NSRect) frame {
    NSRect result;
    // For no arrow or no arrow image, return a zero-sized
    // rect positioned on the right edge of the frame.
    result.origin.x = NSMaxX(frame);
    result.origin.y = NSMaxY(frame);
    result.size.width = 0;
    result.size.height = frame.size.height;

    if (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition != NSPopUpNoArrow) {
        NSImage *arrowImage =
                (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition != NSPopUpNoArrow) ? [self arrowImage] : NULL;

        if (arrowImage != nil) {

            // Scale down the arrows so they look proportional to the control
            // size
            CGFloat sizeFactor = 0;

            switch ([self controlSize]) {
            case NSRegularControlSize:
            case NSControlSizeLarge:
                sizeFactor = 0;
                break;
            case NSSmallControlSize:
                sizeFactor = 1;
                break;
            case NSMiniControlSize:
                sizeFactor = 2;
                break;
            }
            NSRect otherFrame = frame;
            NSSize arrowSize = [arrowImage size];
            otherFrame.origin.x += otherFrame.size.width -
                                   (arrowSize.width + (4 - sizeFactor));
            otherFrame.origin.y +=
                    (otherFrame.size.height - arrowSize.height) / 2;
            otherFrame.size = arrowSize;

            result = NSInsetRect(otherFrame, sizeFactor, sizeFactor);
        }
    }
    return result;
}

// QUIRK: the title area of a bordered pop-up or pull-down button with an arrow starts a fixed distance from the left
// edge and leaves a fixed width at the right for the bezel's arrows, which is why a pop-up button sized to its widest
// title (see -cellSize) shows that title in full. The distances depend on the type and the control size (left, then
// total width taken, at the regular, small and mini sizes): pop-up 11/32, 11/31, 11/32; pull-down 12/34, 11/33, 10/31.
// Not documented. Evidence: black-box observation on macOS 10.14.4 (tier 2) of -titleRectForBounds: with bounds 60 and
// 200 points wide, and of the ink of a rendered title.
// Test: tests/appkit-popup-title-rect.m (test_quirk_popup_title_rect)
static void popUpTitleInsets(BOOL pullsDown, NSControlSize size, CGFloat *left, CGFloat *taken) {
    switch (size) {
    case NSSmallControlSize:
        *left = 11;
        *taken = pullsDown ? 33 : 31;
        break;
    case NSMiniControlSize:
        *left = pullsDown ? 10 : 11;
        *taken = pullsDown ? 31 : 32;
        break;
    default:
        *left = pullsDown ? 12 : 11;
        *taken = pullsDown ? 34 : 32;
        break;
    }
}

// QUIRK: with the textured rounded bezel style the title area starts 7 points from the left edge and leaves 23
// points (pop-up) or 24 (pull-down) at the right for the chevrons, 22 for a small pop-up. Not documented. Evidence:
// black-box observation of -titleRectForBounds: with 100 point bounds on macOS 10.14.4 (tier 2), probe
// mac-probes/aqua-toolbar.m of the research notes. Test: appkit-toolbar-controls-aqua.m (test_quirk_textured_popup)
static void texturedPopUpTitleInsets(BOOL pullsDown, NSControlSize size, CGFloat *left, CGFloat *taken) {
    *left = 7;
    *taken = pullsDown ? 24 : (size == NSSmallControlSize ? 22 : 23);
}

- (NSRect) titleRectForBounds: (NSRect) rect {
    rect = [super titleRectForBounds: rect];
    if (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition != NSPopUpNoArrow) {
        if ([self isBordered]) {
            CGFloat left, taken;

            if (NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSTexturedRoundedBezelStyle)
                texturedPopUpTitleInsets(NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown, [self controlSize], &left,
                                         &taken);
            else
                popUpTitleInsets(NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown, [self controlSize], &left, &taken);
            rect.origin.x += left;
            rect.size.width = MAX(0, rect.size.width - taken);
            return rect;
        }
        // Don't use the room used by the arrow, with some margin
        NSRect arrowRect = [self _arrowRectForRect: rect];
        rect.size.width = NSMinX(arrowRect) - NSMinX(rect) - 5.;
    }
    return rect;
}

// QUIRK: a title that is a little too wide for its area is drawn with tighter spacing (here: squeezed horizontally) before it
// is shortened with an ellipsis: the overflow is taken up as long as it is at most 4% of the text's width. Not
// documented for this cell (the documented NSParagraphStyle property allowsDefaultTighteningForTruncation names the
// idea, not the limit). Evidence: black-box observation on macOS 10.14.4 (tier 2) of the rendered ink of a 13 and an
// 11 point title in areas 2 to 6 points narrower than the text: it narrows by the overflow up to about 4 points of
// 104 and 89, and loses a character from about 6 and 5 points on.
// Test: tests/appkit-popup-title-rect.m (test_quirk_popup_title_tightened)
- (NSRect) drawTitle: (NSAttributedString *) title withFrame: (NSRect) titleRect inView: (NSView *) controlView {
    CGFloat width = ceil([title size].width);
    CGFloat excess = width - titleRect.size.width;

    if (excess > 0 && excess <= width * 0.04) {
        // The text is squeezed horizontally into the area (its letters and the spaces between them).
        CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
        NSRect wide = titleRect;
        NSRect result;

        wide.size.width = width;
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, titleRect.origin.x, 0);
        CGContextScaleCTM(context, titleRect.size.width / width, 1);
        CGContextTranslateCTM(context, -titleRect.origin.x, 0);
        result = [super drawTitle: title withFrame: wide inView: controlView];
        CGContextRestoreGState(context);
        return result;
    }
    return [super drawTitle: title withFrame: titleRect inView: controlView];
}

- (void) drawBezelWithFrame: (NSRect) frame inView: (NSView *) controlView {

    [super drawBezelWithFrame: frame inView: controlView];

    // Now draw the arrow, unless the bezel included it
    if ([self isBordered] && NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSRoundedBezelStyle)
        return;
    if ([self isBordered] && NS_EXTRA(NSButtonCell, self)->_bezelStyle == NSTexturedRoundedBezelStyle) {
        if (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition == NSPopUpNoArrow)
            return;

        // the chevrons are drawn by the style, on the bezel's artwork, for a view that is not flipped
        NSRect art = [self _aquaBezelArtworkRectForFrame: frame inView: controlView];
        CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];

        CGContextSaveGState(context);
        if ([controlView isFlipped]) {
            CGContextTranslateCTM(context, 0, 2 * art.origin.y + art.size.height);
            CGContextScaleCTM(context, 1, -1);
        }
        [[controlView graphicsStyle] drawTexturedPopUpArrowsInRect: art
                                                         pullsDown: NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown
                                                           enabled: [self isEnabled]
                                                       controlSize: [self controlSize]];
        CGContextRestoreGState(context);
        return;
    }
    if (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition != NSPopUpNoArrow) {
        NSImage *arrowImage =
                (NS_EXTRA(NSPopUpButtonCell, self)->_arrowPosition != NSPopUpNoArrow) ? [self arrowImage] : NULL;

        if (arrowImage == NULL)
            return;

        NSRect arrowFrame = [self _arrowRectForRect: frame];
        [[controlView graphicsStyle] drawButtonImage: arrowImage
                                              inRect: arrowFrame
                                             enabled: YES
                                               mixed: YES];
    }
}

// QUIRK: a pop-up button (not a pull-down) is as wide as its widest item, not as the item that is
// shown, so that the selection changing does not resize it: the widest title plus a fixed amount
// for the bezel and the arrows, rounded up. The amount depends on the control size. Not documented.
// Evidence: black-box observation on macOS 10.14.4 (tier 2) of the intrinsic width with titles of
// 156, 135 and 113 points at the three control sizes, probe mac-probes/ua5-intrinsic.m of the
// Darling research notes; 26.7.3 differs and is not followed.
// Test: tests/appkit-popup-stepper-intrinsic-size.m (test_quirk_popup_widest_item_width)
- (CGFloat) _widestItemWidthForPopUp {
    NSFont *font = [self font];
    NSDictionary *attributes = font != nil ? [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName] : nil;
    CGFloat widest = 0;

    for (NSMenuItem *item in [self itemArray]) {
        NSString *title = [item title];

        if (title != nil)
            widest = MAX(widest, [title sizeWithAttributes: attributes].width);
    }
    return widest;
}

- (NSSize) cellSize {
    NSSize result = [super cellSize];

    if (!NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown && [[self itemArray] count] > 0) {
        CGFloat extra = 32;

        if ([self controlSize] == NSSmallControlSize)
            extra = 28;
        else if ([self controlSize] == NSMiniControlSize)
            extra = 33;
        CGFloat fitted = ceil([self _widestItemWidthForPopUp] + extra);

        result.width = MAX(result.width, fitted);
    }

    switch ([self controlSize]) {

    case NSRegularControlSize:
    case NSControlSizeLarge:
        result.height = 22;
        break;

    case NSSmallControlSize:
        result.height = 19;
        break;

    case NSMiniControlSize:
        result.height = 15;
        break;
    }

    return result;
}

- (void) setTitle: (NSString *) title {

    if (NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown) {
        // Doc.s for pulls down behavior are not correct, it just sets the title
        // to the argument and doesn't affect the selection
        [super setTitle: title];
    } else {
        NSMenuItem *item = [_menu itemWithTitle: title];

        if (item == nil)
            [self addItemWithTitle: title];

        [self selectItemWithTitle: title];
    }
}

// From Cocoa doc :
// This method has no effect.
// The image displayed in a pop up button is taken from the selected menu item
// (in the case of a pop up menu) or from the first menu item (in the case of a
// pull-down menu).
- (void) setImage: (NSImage *) image {
}

- (NSImage *) image {
    return [[self _displayedItem] image];
}

- (NSCellImagePosition) imagePosition {
    // It seems Cocoa popup buttons never ignore the image - they are drawn at
    // Left position if set to None
    NSCellImagePosition imagePosition = [super imagePosition];
    return imagePosition == NSNoImage ? NSImageLeft : imagePosition;
}

- (NSInteger) tag {
    return [[self selectedItem] tag];
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) cellFrame
              ofView: (NSView *) controlView
        untilMouseUp: (BOOL) flag
{
    NSPoint origin = [controlView bounds].origin;

#if 0
   // Note: the min options don't mean much unless we don't have room for the menu, so either way we just pop
   // up over the button itself. However, maxX and maxY *do* have special meanings
   switch( NS_EXTRA(NSPopUpButtonCell, self)->_preferredEdge )
   {
      case NSMinXEdge:
      case NSMinYEdge:
	     break;
	  case NSMaxXEdge:
		 origin.x += [controlView bounds].size.width;
	     break;
	  case NSMaxYEdge: 
         // Remember, our Y axis is flipped in Cocoa. Also, not sure why we need the -4 offset here, 
		 // can't figure out where the offset comes from, but it works			
		 origin.y -= [controlView bounds].size.height - 4;
	     break;
   }
#endif
    origin = [controlView convertPoint: origin toView: nil];
    origin = [[controlView window] convertBaseToScreen: origin];

    // The delegate calls are optional, and go to the menu itself, not to the copy shown for a pull-down: the
    // update (-menuNeedsUpdate: once, then the validation of the items), the tracking notification and
    // -menuWillOpen:, in the order macOS makes them; after the tracking come -menuDidClose: and the end
    // notification. The list of items does not open submenus, so a submenu's delegate is not asked: macOS
    // updates and opens a submenu of a pop-up, which is not implemented here.
    // QUIRK: a pop-up (not pull-down) button's menu is updated before NSMenuDidBeginTrackingNotification is
    // posted, a pull-down's after it. Not documented. Evidence: black-box observation on macOS 26.7.3 (tier 2).
    // Test: appkit-popupbuttoncell-menu-delegate (test_quirk_pop_up_updates_before_begin_notification)
    BOOL pullsDown = NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    if (pullsDown) {
        [center postNotificationName: NSMenuDidBeginTrackingNotification object: _menu];
        [_menu _updateWithoutSubmenus];
    } else {
        [_menu _updateWithoutSubmenus];
        [center postNotificationName: NSMenuDidBeginTrackingNotification object: _menu];
    }
    if ([[_menu delegate] respondsToSelector: @selector(menuWillOpen:)])
        [[_menu delegate] menuWillOpen: _menu];
    NSMenu *menu = _menu;
    if (NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown && [_menu numberOfItems]) {
        // Don't display the first item for pullDowns controls
        menu = [[_menu copy] autorelease];
        [menu removeItemAtIndex: 0];
    }

    NSPopUpWindow *window = [[NSPopUpWindow alloc]
            initWithFrame: NSMakeRect(origin.x, origin.y, cellFrame.size.width,
                                      cellFrame.size.height)];
    [window setPullsDown: NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown];
    [window setMenu: menu];
    if ([self font] != nil)
        [window setFont: [self font]];

    if (NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown)
        [window selectItemAtIndex: -1]; // No initial selection for pullsDown
    else
        [window selectItemAtIndex: _selectedIndex];

    NSInteger itemIndex = [window runTrackingWithEvent: event];
    if (itemIndex != NSNotFound) {
        if (NS_EXTRA(NSPopUpButtonCell, self)->_pullsDown) {
            // remember that thing we did with the first menu item?
            itemIndex++;
        }
        // We can be embedded in controls other than a PopUpButton - so don't
        // assume selectItemAtIndex: is available
        if ([controlView respondsToSelector: @selector(selectItemAtIndex:)]) {
            [(id) controlView selectItemAtIndex: itemIndex];
        }
    }
    _selectedIndex = (itemIndex == NSNotFound) ? -1 : itemIndex;
    [window close]; // release when closed=YES
    if ([[_menu delegate] respondsToSelector: @selector(menuDidClose:)])
        [[_menu delegate] menuDidClose: _menu];
    [center postNotificationName: NSMenuDidEndTrackingNotification object: _menu];

    return itemIndex != NSNotFound;
}

- (void) moveUp: sender {
    NSInteger index = [self indexOfSelectedItem];

    if (index > 0)
        [self selectItemAtIndex: index - 1];
}

- (void) moveDown: sender {
    NSInteger index = [self indexOfSelectedItem];

    if (index < [self numberOfItems] - 1)
        [self selectItemAtIndex: index + 1];
}

/* That's the action the menu items are connected to in nibs */
- (void) _popUpItemAction: (id) sender {
    NSUInteger itemIndex = [_menu indexOfItem: sender];
    if (itemIndex != NSNotFound) {
        [self selectItemAtIndex: itemIndex];
    }
    [NSApp sendAction: [self action] to: [self target] from: _controlView];
}

- (void) setControlView: (NSView *) view {
    [super setControlView: view];

    // Is this hacky? We need to a way to sync the title after _menu is fully initialized
    if (NS_EXTRA(NSPopUpButtonCell, self)->_syncTitleNeeded) {
        [self synchronizeTitleAndSelectedItem];
        NS_EXTRA(NSPopUpButtonCell, self)->_syncTitleNeeded = NO;

    }
}

@end
