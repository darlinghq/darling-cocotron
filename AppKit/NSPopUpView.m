/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPopUpView.h>
#import <AppKit/NSStringDrawer.h>

enum { KEYBOARD_INACTIVE, KEYBOARD_ACTIVE, KEYBOARD_OK, KEYBOARD_CANCEL };

// TODO : NSPopUpView should at least inherit from NSMenuView - we have plenty
// of common code here

#define ITEM_MARGIN 2

@implementation NSPopUpView

// If the user clicks and holds on a popup menu and then releases
// the app should just dismiss the popup and reselect the current value.
// If the user clicks and immediately releases the popup menu should remain
// on screen. This threshold is the dividing line between those two behaviours.
static const NSTimeInterval kMenuInitialClickThreshold = .3f;

// The metrics of the menu look (see -[NSGraphicsStyle menuItemGutterSize] and its neighbours): no frame line,
// 4 points of padding above the first and below the last row, rows of the font size plus 5 points (18 for the
// 13 point font of a pop-up button on macOS 10.14.4, measured from window images of its menu, black-box, tier 2).
#define WINDOW_BORDER_THICKNESS 0
#define WINDOW_VERTICAL_PADDING 4
#define IMAGE_ROW_EXTRA 5

// Note: moved these above init to avoid compiler warnings
- (NSDictionary *) itemAttributes {
    return [NSDictionary
            dictionaryWithObjectsAndKeys: _font, NSFontAttributeName, nil];
}

- (NSArray *) visibleItemArray {
    NSArray *items = [[self menu] itemArray];

    NSMutableArray *visibleArray = [[[NSMutableArray alloc] init] autorelease];

    for (NSMenuItem *item in items) {
        if (![item isHidden]) {
            [visibleArray addObject: item];
        }
    }

    return visibleArray;
}

- (NSSize) sizeForMenuItemImage: (NSMenuItem *) item {
    NSSize result = NSZeroSize;

    if ([item image] != nil)
        result = [[item image] size];

    return result;
}

- (NSSize) sizeForMenuItems: (NSArray *) items {
    NSSize result = NSZeroSize;
    CGFloat maxTitleWidth = 0.0f;
    BOOL anItemHasAnImage = NO;
    CGFloat maxKeyWidth = 0.0f;
    CGFloat totalHeight = WINDOW_VERTICAL_PADDING;
    CGFloat maxKeyTitleWidth = 0.0f;
    BOOL anItemHasSubmenu = NO;
    NSGraphicsStyle *style = [self graphicsStyle];
    NSSize gutterSize = [style menuItemGutterSize];
    CGFloat rowHeight = _font != nil ? ceil([_font pointSize]) + 5 : [style menuItemRowHeight];
    unsigned i, count = [items count];
    NSRect rects[count];

    BOOL useCustomFont = _font != nil;
    if (useCustomFont) {
        // If we have the default font, then really use the default menu one
        // instead of forcing it
        if ([_font isEqual: [NSFont fontWithName: @"Arial" size: 9.]]) {
            useCustomFont = NO;
        }
    }

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];
        CGFloat height = 0.;
        CGFloat titleAndIconWidth = 0.0f;
        if ([item isSeparatorItem]) {
            height = [style menuItemSeparatorSize].height;
        } else {
            NSSize size = NSZeroSize;

            height = rowHeight;
            size = [self sizeForMenuItemImage: item];
            if (size.width > 0.0f) {
                height = MAX(height, size.height + IMAGE_ROW_EXTRA);
                anItemHasAnImage = YES;
                titleAndIconWidth = size.width + [style menuItemImageTitleGap];
            }
            titleAndIconWidth += [item indentationLevel] * [style menuItemIndentationWidth];

            if ([item attributedTitle]) {
                size = [[self graphicsStyle]
                        menuItemAttributedTextSize: [item attributedTitle]];
            } else {
                if (useCustomFont) {
                    NSDictionary *attributes = [self itemAttributes];
                    NSAttributedString *attributedTitle =
                            [[[NSAttributedString alloc]
                                    initWithString: [item title]
                                        attributes: attributes] autorelease];
                    size = [[self graphicsStyle]
                            menuItemAttributedTextSize: attributedTitle];
                } else {
                    size = [[self graphicsStyle]
                            menuItemTextSize: [item title]];
                }
            }
            titleAndIconWidth += size.width;
            maxTitleWidth = MAX(maxTitleWidth, titleAndIconWidth);
            height = MAX(height, size.height);

            if ([[item keyEquivalent] length] != 0) {
                size = [[self graphicsStyle]
                        menuItemTextSize: [item _keyEquivalentDescription]];
                maxKeyWidth = MAX(maxKeyWidth, size.width);
                maxKeyTitleWidth = MAX(maxKeyTitleWidth, titleAndIconWidth);
            }
            if ([item hasSubmenu])
                anItemHasSubmenu = YES;
        }
        rects[i] = NSMakeRect(0, totalHeight, titleAndIconWidth, height);
        totalHeight += height;
    }

    // Wide enough for the widest title and its trailing margin (plus the submenu arrow's column when an item has a
    // submenu), and for the widest key equivalent after the widest title that has one; as in NSSubmenuView.
    result.height = totalHeight + WINDOW_VERTICAL_PADDING;
    CGFloat titleBased = gutterSize.width + maxTitleWidth +
                         [style menuItemTrailingMargin] + (anItemHasSubmenu ? [style menuItemSubmenuColumnWidth] : 0);
    CGFloat keyBased = 0.0f;
    if (maxKeyWidth > 0.0f)
        keyBased = gutterSize.width + maxKeyTitleWidth + [style menuItemKeyEquivalentGap] + maxKeyWidth +
                   [style menuItemKeyEquivalentRightMargin] + 1;
    result.width = MAX(titleBased, keyBased);
    (void) anItemHasAnImage;

    if (_cachedItemRects == nil && [items isEqual: [self visibleItemArray]]) {
        // Build our cached item rects
        _cachedItemRects = [[NSMutableArray arrayWithCapacity: count] retain];
        for (int i = 0; i < count; ++i) {
            // Normalize the items widths to the menu widths
            rects[i].size.width = result.width;
            [_cachedItemRects addObject: [NSValue valueWithRect: rects[i]]];
        }
    }
    return result;
}

- initWithFrame: (NSRect) frame {
    [super initWithFrame: frame];
    _cellSize = frame.size;
    _font = [[NSFont messageFontOfSize: 12] retain];
    _selectedIndex = -1;
    _pullsDown = NO;

    NSSize sz = [@"ABCxyzgjX" sizeWithAttributes: [self itemAttributes]];
    _cellSize.height = sz.height + ITEM_MARGIN + ITEM_MARGIN;

    return self;
}

- (void) dealloc {
    [_cachedItemRects release];
    [_font release];
    [super dealloc];
}

- (BOOL) isFlipped {
    return YES;
}

- (void) setFont: (NSFont *) font {
    [_font autorelease];
    _font = [font retain];
}

- (BOOL) pullsDown {
    return _pullsDown;
}

- (void) setPullsDown: (BOOL) pullsDown {
    _pullsDown = pullsDown;
}

- (void) selectItemAtIndex: (NSInteger) index {
    _selectedIndex = index;
    _initialSelectedIndex = index;
}

- (NSSize) sizeForContents {
    return [self sizeForMenuItems: [self visibleItemArray]];
}

- (void) _buildCachedItemRects {
    // Force a build of the cached item rects
    [self sizeForMenuItems: [self visibleItemArray]];
}

// For attributed strings - precalcing the the item rects makes performance much
// faster.
- (NSArray *) _cachedItemRects {
    if (_cachedItemRects == nil) {
        [self _buildCachedItemRects];
    }
    return _cachedItemRects;
}

- (NSRect) rectForItemAtIndex: (NSInteger) index {
    NSRect result = [[[self _cachedItemRects] objectAtIndex: index] rectValue];
    // Be sure we cover the full view width
    result.size.width = self.bounds.size.width;
    return result;
}

- (NSRect) rectForSelectedItem {
    if (_pullsDown) {
        return NSZeroRect;
    } else if (_selectedIndex == -1) {
        return [self rectForItemAtIndex: 0];
    } else {
        return [self rectForItemAtIndex: _selectedIndex];
    }
}

static NSRect boundsToTitleAreaRect(NSRect rect) {
    return NSInsetRect(rect, WINDOW_BORDER_THICKNESS, WINDOW_VERTICAL_PADDING);
}

- (void) drawRect: (NSRect) rect {
    NSRect bounds = [self bounds];
    NSRect itemArea = boundsToTitleAreaRect(bounds);
    NSArray *items = [self visibleItemArray];
    unsigned i, count = [items count];
    NSPoint origin = itemArea.origin;

    BOOL useCustomFont = _font != nil;
    if (useCustomFont) {
        // If we have the default font, then really use the default menu one
        // instead of forcing it
        if ([_font isEqual: [NSFont fontWithName: @"Arial" size: 9.]]) {
            useCustomFont = NO;
        }
    }

    [[self graphicsStyle] drawMenuWindowBackgroundInRect: self.bounds];

    CGContextRef clipContext = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSaveGState(clipContext);
    [[self graphicsStyle] clipToMenuWindowShape];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [items objectAtIndex: i];
        NSRect itemRect = [self rectForItemAtIndex: i];
        if (NSIntersectsRect(rect, itemRect) == NO) {
            continue;
        }
        itemArea = itemRect;
        origin = itemRect.origin;

        if ([item isSeparatorItem]) {
            NSRect separatorRect = NSMakeRect(
                    origin.x, origin.y, NSWidth(itemArea),
                    [[self graphicsStyle] menuItemSeparatorSize].height);

            [[self graphicsStyle] drawMenuSeparatorInRect: separatorRect];

            origin.y += NSHeight(separatorRect);
        } else {
#define CENTER_PART_RECT_VERTICALLY(partSize) {                                \
        NSSize __partSize = (partSize);                                        \
        __partSize.width = ceilf(__partSize.width);                            \
        partRect.origin.y = origin.y + (itemHeight - __partSize.height) / 2;   \
        partRect.size.height = __partSize.height;                              \
        partRect.size.width = __partSize.width;                                \
    }
            NSImage *image = [item image];
            BOOL selected = (i == _selectedIndex) ? YES : NO;
            CGFloat itemHeight = itemRect.size.height;
            NSRect partRect;
            NSSize partSize;
            BOOL showsEnabled = ([item isEnabled] || [item hasSubmenu]);

            partRect = NSMakeRect(origin.x, origin.y, itemArea.size.width,
                                  itemHeight);

            if (selected)
                [[self graphicsStyle] drawMenuSelectionInRect: partRect
                                                      enabled: showsEnabled];

            NSGraphicsStyle *style = [self graphicsStyle];
            NSSize gutterSize = [style menuItemGutterSize];

            // The state mark, in the gutter column at the left edge.
            NSImage *stateImage = nil;
            if ([item state] == NSControlStateValueOn)
                stateImage = [item onStateImage];
            else if ([item state] == NSControlStateValueMixed)
                stateImage = [item mixedStateImage];
            else if (_initialSelectedIndex == i)
                stateImage = [item onStateImage];
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
                CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];

                CGContextSaveGState(ctx);
                CGContextTranslateCTM(ctx, drawingRect.origin.x, drawingRect.origin.y);
                if ([self isFlipped]) {
                    CGContextTranslateCTM(ctx, 0, drawingRect.size.height);
                    CGContextScaleCTM(ctx, 1, -1);
                }
                drawingRect.origin = NSZeroPoint;
                [style drawButtonImage: image inRect: drawingRect enabled: showsEnabled mixed: NO];
                CGContextRestoreGState(ctx);

                x += imageSize.width + [style menuItemImageTitleGap];
            }

            NSAttributedString *atitle = [item attributedTitle];
            NSString *title = [item title];

            partRect = NSMakeRect(x, origin.y, 0, 0);
            if (atitle != nil && [atitle length] > 0) {
                partSize = [style menuItemAttributedTextSize: atitle];
            } else if (useCustomFont) {
                NSDictionary *attributes = [self itemAttributes];

                atitle = [[[NSAttributedString alloc] initWithString: title attributes: attributes] autorelease];
                partSize = [style menuItemAttributedTextSize: atitle];
            } else {
                partSize = [style menuItemTextSize: title];
            }
            partRect.size = partSize;
            partRect.size.width = ceilf(partRect.size.width);
            partRect.origin.y = origin.y + (itemHeight - partSize.height) / 2;
            if (atitle != nil && [atitle length] > 0)
                [style drawAttributedMenuItemText: atitle inRect: partRect enabled: showsEnabled selected: selected];
            else
                [style drawMenuItemText: title inRect: partRect enabled: showsEnabled selected: selected];

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
    CGContextRestoreGState(clipContext);
}
/*
 * Returns NSNotFound if the point is outside of the menu
 * Returns -1 if the point is inside the menu but on a disabled or separator
 * item Returns a usable index if the point is on a selectable item
 */
- (NSInteger) itemIndexForPoint: (NSPoint) point {
    NSInteger result;
    NSArray *items = [self visibleItemArray];
    int i, count = [items count];

    if (point.y < 0) {
        return NSNotFound;
    }

    for (i = 0; i < count; i++) {
        if ([[items objectAtIndex: i] isHidden])
            continue;

        NSRect itemRect = [self rectForItemAtIndex: i];
        if (NSPointInRect(point, itemRect)) {
            if (([[items objectAtIndex: i] isEnabled] == NO) ||
                ([[items objectAtIndex: i] isSeparatorItem])) {
                return -1;
            }
            return i;
        }
    }
    return NSNotFound;
}

- (void) rightMouseDown: (NSEvent *) event {
    // do nothing
}

- (void) updateSelectedIndex: (NSInteger) index {
    if (_selectedIndex != index) {
        NSInteger previous = _selectedIndex;
        _selectedIndex = index;
        if (previous != _selectedIndex) {
            if (previous != -1) {
                NSRect itemRect = [self rectForItemAtIndex: previous];
                [self setNeedsDisplayInRect: itemRect];
            }
            if (_selectedIndex != -1) {
                NSRect itemRect = [self rectForItemAtIndex: _selectedIndex];
                [self setNeedsDisplayInRect: itemRect];
            }
        }
    }
}
/*
 * This method may return NSNotFound when the view positioned outside the
 * initial tracking area due to preferredEdge settings and the user clicks the
 * mouse. The NSPopUpButtonCell code deals with it. It might make sense for this
 * to return the previous value.
 */
- (NSInteger) runTrackingWithEvent: (NSEvent *) event {
    enum {
        STATE_FIRSTMOUSEDOWN,
        STATE_MOUSEDOWN,
        STATE_MOUSEUP,
        STATE_EXIT
    } state = STATE_FIRSTMOUSEDOWN;
    NSPoint firstLocation, point = [event locationInWindow];
    NSInteger initialSelectedIndex = _selectedIndex;

    // Make sure we get mouse moved events, too, so we can respond apporpiately
    // to click-click actions as well as of click-and-drag
    BOOL oldAcceptsMouseMovedEvents = [[self window] acceptsMouseMovedEvents];
    [[self window] setAcceptsMouseMovedEvents: YES];

    // point comes in on controls window
    point = [[event window] convertBaseToScreen: point];
    // Movement is measured against the pointer's screen position, which is
    // what -[NSEvent mouseLocation] gives below.
    firstLocation = point;
    point = [[self window] convertScreenToBase: point];
    point = [self convertPoint: point fromView: nil];

    // Make sure we know if the user clicks away from the app in the middle of
    // this
    BOOL cancelled = NO;

    NSRect screenVisible =
            NSInsetRect([[[self window] screen] visibleFrame], 0, 4);

    [NSEvent startPeriodicEventsAfterDelay: .0 withPeriod: .02];
    BOOL mouseMoved = NO;

    NSTimeInterval firstTimestamp = 0.;
    do {
        NSInteger index = [self itemIndexForPoint: point];

        /*
         If the popup is activated programmatically with performClick: index may
         be NSNotFound because the mouse starts out outside the view. We don't
         change _selectedIndex in this case.
         */
        if (index != NSNotFound && _keyboardUIState == KEYBOARD_INACTIVE) {
            [self updateSelectedIndex: index];
        }

        event = [[self window]
                nextEventMatchingMask: NSPeriodicMask | NSLeftMouseUpMask |
                                       NSMouseMovedMask |
                                       NSLeftMouseDraggedMask | NSKeyDownMask |
                                       NSAppKitDefinedMask];
        if (firstTimestamp == 0.) {
            // Note: we don't do that using the first event, because in case the
            // menu takes a long of time to display, the next event we get will
            // be actually after our "long click" threshold
            firstTimestamp = [event timestamp];
        }
        if ([event type] == NSKeyDown) {
            [self interpretKeyEvents: [NSArray arrayWithObject: event]];
            switch (_keyboardUIState) {
            case KEYBOARD_INACTIVE:
                _keyboardUIState = KEYBOARD_ACTIVE;
                continue;

            case KEYBOARD_ACTIVE:
                break;

            case KEYBOARD_CANCEL:
                _selectedIndex = initialSelectedIndex;
            case KEYBOARD_OK:
                state = STATE_EXIT;
                break;
            }
        } else
            _keyboardUIState = KEYBOARD_INACTIVE;

        if ([event type] == NSAppKitDefined) {
            if ([event subtype] == NSApplicationDeactivated) {
                cancelled = YES;
            }
        }
        point = [NSEvent mouseLocation];
        if (mouseMoved == NO) {
            mouseMoved = ABS(point.x - firstLocation.x) > 2. ||
                         ABS(point.y - firstLocation.y) > 2.;
        }

        if (NSPointInRect(point, [[self window] frame])) {
            if (!NSPointInRect(point, screenVisible)) {
                // The point is inside the menu, and on the top or bottom border
                // of the screen - let's autoscroll
                NSPoint origin = [[self window] frame].origin;
                BOOL change = NO;

                if (point.y < NSMinY(screenVisible)) {
                    origin.y += _cellSize.height;
                    change = YES;
                }

                if (point.y > NSMaxY(screenVisible)) {
                    origin.y -= _cellSize.height;
                    change = YES;
                }

                if (change)
                    [[self window] setFrameOrigin: origin];
            }
        } else {
            [self updateSelectedIndex: -1];
        }
        // Convert the global point to view coordinates
        point = [[self window] convertScreenToBase: point];
        point = [self convertPoint: point fromView: nil];

        if ([event type] == NSPeriodic) {
            // Periodic events are just there for autoscroll so we're done with
            // this one
            continue;
        }

        switch (state) {
        case STATE_FIRSTMOUSEDOWN:
            if ([event type] == NSLeftMouseUp) {
                if (mouseMoved || [event timestamp] - firstTimestamp >
                                          kMenuInitialClickThreshold) {
                    // Long click - accept the selection
                    state = STATE_EXIT;
                } else {
                    // Short click - let's keep the menu sticky
                    state = STATE_MOUSEUP;
                }
            } else {
                if (mouseMoved) {
                    state = STATE_MOUSEDOWN;
                }
            }
            break;

        default:
            if ([event type] == NSLeftMouseUp) {
                // If the user clicked outside of the window - then they want
                // to dismiss it without changing anything
                NSPoint winPoint = [event locationInWindow];
                winPoint = [[event window] convertBaseToScreen: winPoint];
                if (NSPointInRect(winPoint, [[self window] frame]) == NO) {
                    [self updateSelectedIndex: -1];
                }
                state = STATE_EXIT;
            }
            break;
        }

    } while (cancelled == NO && state != STATE_EXIT);
    [NSEvent stopPeriodicEvents];

    [[self window] setAcceptsMouseMovedEvents: oldAcceptsMouseMovedEvents];

    _keyboardUIState = KEYBOARD_INACTIVE;

    return (_selectedIndex == -1) ? NSNotFound : _selectedIndex;
}

- (void) keyDown: (NSEvent *) event {
    [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

- (void) moveUp: (id) sender {
    NSInteger previous = _selectedIndex;

    // Find the previous visible item
    NSArray *items = [self visibleItemArray];
    if (_selectedIndex == -1)
        _selectedIndex = [items count];

    do {
        _selectedIndex--;
    } while (_selectedIndex >= 0 &&
             ([[items objectAtIndex: _selectedIndex] isHidden] ||
              [[items objectAtIndex: _selectedIndex] isSeparatorItem]));

    if (_selectedIndex < 0)
        _selectedIndex = previous;

    [self setNeedsDisplay: YES];
}

- (void) moveDown: (id) sender {
    NSInteger previous = _selectedIndex;

    // Find the next visible item
    NSArray *items = [self visibleItemArray];
    NSInteger searchIndex = _selectedIndex;

    do {
        searchIndex++;
    } while (searchIndex < [items count] &&
             ([[items objectAtIndex: searchIndex] isHidden] ||
              [[items objectAtIndex: searchIndex] isSeparatorItem]));

    if (searchIndex >= [items count]) {
        _selectedIndex = previous;
    } else {
        _selectedIndex = searchIndex;
    }

    [self setNeedsDisplay: YES];
}

- (void) cancel: (id) sender {
    _keyboardUIState = KEYBOARD_CANCEL;
}

- (void) insertNewline: (id) sender {
    _keyboardUIState = KEYBOARD_OK;
}

- (void) insertText: (id) aString {

    // We're intercepting insertText: so we can do menu navigation by letter
    unichar ch = [aString characterAtIndex: 0];
    NSString *letterString =
            [[NSString stringWithCharacters: &ch length: 1] uppercaseString];

    NSInteger oldIndex = _selectedIndex;

    NSArray *items = [self visibleItemArray];
    NSInteger newIndex = _selectedIndex;

    // Set to the next item in the array or the start if we're at the end or
    // there's no selection
    if (oldIndex == NSNotFound || oldIndex == [items count] - 1) {
        newIndex = 0;
    } else {
        newIndex = oldIndex + 1;
    }

    // Find the next visible item that has a title with an uppercase letter
    // matching what the user entered (who knows what this means in Japan...)
    BOOL found = NO;
    while (!found && newIndex != oldIndex) {
        // Make sure we stop eventually
        if (oldIndex == NSNotFound || oldIndex == -1) {
            oldIndex = 0;
        }
        // Try and find a new item to select
        NSMenuItem *item = [items objectAtIndex: newIndex];
        if ([item isEnabled] == YES && [item isSeparatorItem] == NO) {
            NSRange range = [[item title] rangeOfString: letterString];
            if (range.location != NSNotFound) {
                _selectedIndex = newIndex;
                found = YES;
            }
        }
        if (!found) {
            if (newIndex == [items count] - 1) {
                newIndex = 0;
            } else {
                newIndex++;
            }
        }
    }
    if (newIndex != oldIndex) {
        [self setNeedsDisplay: YES];
    }
}
@end
