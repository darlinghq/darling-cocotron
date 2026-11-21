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

#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSBezierPath.h>
#import <objc/runtime.h>

// centersPlaceholder lives outside the instance: the ivar layout is fixed
static char centersPlaceholderKey;

@interface NSSearchFieldCell (NSSearchFieldLayout)
- (NSRect) _searchTextRectForBounds: (NSRect) rect;
- (NSRect) _searchButtonRectForBounds: (NSRect) rect;
@end

@implementation NSSearchField

+ (Class) cellClass {
    return [NSSearchFieldCell class];
}

// A new search field draws no background of its own (macOS 10.14.4).
- (void) _setDefaultBackground {
    [[self cell] setDrawsBackground: NO];
}

// The ring follows the rounded corners of the search field's bezel (see NSSearchFieldCell).
- (void) drawFocusRingMask {
    [[NSBezierPath bezierPathWithRoundedRect: [self bounds] xRadius: 4 yRadius: 4] fill];
}

- (NSSearchFieldCell *) _searchCell {
    return [self cell];
}

- (NSArray *) recentSearches {
    return [[self _searchCell] recentSearches];
}

- (NSString *) recentsAutosaveName {
    return [[self _searchCell] recentsAutosaveName];
}

- (void) setRecentSearches: (NSArray *) searches {
    [[self _searchCell] setRecentSearches: searches];
}

- (void) setRecentsAutosaveName: (NSString *) name {
    [[self _searchCell] setRecentsAutosaveName: name];
}

- (int) maximumRecents {
    return [[self _searchCell] maximumRecents];
}

- (void) setMaximumRecents: (int) maxRecents {
    [[self _searchCell] setMaximumRecents: maxRecents];
}

- (BOOL) sendsWholeSearchString {
    return [[self _searchCell] sendsWholeSearchString];
}

- (void) setSendsWholeSearchString: (BOOL) flag {
    [[self _searchCell] setSendsWholeSearchString: flag];
}

- (BOOL) sendsSearchStringImmediately {
    return [[self _searchCell] sendsSearchStringImmediately];
}

- (void) setSendsSearchStringImmediately: (BOOL) flag {
    [[self _searchCell] setSendsSearchStringImmediately: flag];
}

- (NSButtonCell *) searchButtonCell {
    return [[self _searchCell] searchButtonCell];
}

- (void) setSearchButtonCell: (NSButtonCell *) cell {
    [[self _searchCell] setSearchButtonCell: cell];
}

- (NSButtonCell *) cancelButtonCell {
    return [[self _searchCell] cancelButtonCell];
}

- (void) setCancelButtonCell: (NSButtonCell *) cell {
    [[self _searchCell] setCancelButtonCell: cell];
}

- (NSMenu *) searchMenuTemplate {
    return [[self _searchCell] searchMenuTemplate];
}

- (void) setSearchMenuTemplate: (NSMenu *) menu {
    [[self _searchCell] setSearchMenuTemplate: menu];
}

- (BOOL) centersPlaceholder {
    return [objc_getAssociatedObject(self, &centersPlaceholderKey) boolValue];
}

- (void) setCentersPlaceholder: (BOOL) flag {
    objc_setAssociatedObject(self, &centersPlaceholderKey, flag ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self setNeedsDisplay: YES];
}

// The parts are where the cell lays them out in the field's bounds.
// QUIRK: the centred layout is the same as the other one: both are returned
// for either argument, whatever centersPlaceholder, the placeholder and the
// text are. Not documented. Evidence: black-box observation on macOS 10.14.4
// and 26.7.3 (tier 2). Test: tests/appkit-searchfield-centered-rects.m
// The cell in turn asks these methods for the text and search button.
- (NSRect) rectForSearchTextWhenCentered: (BOOL) isCentered {
    return [[self _searchCell] _searchTextRectForBounds: [self bounds]];
}

- (NSRect) rectForSearchButtonWhenCentered: (BOOL) isCentered {
    return [[self _searchCell] _searchButtonRectForBounds: [self bounds]];
}

- (NSRect) rectForCancelButtonWhenCentered: (BOOL) isCentered {
    return [[self _searchCell] cancelButtonRectForBounds: [self bounds]];
}

// The delegate hears that searching started when the field's text becomes
// non-empty and that it ended when the text is empty again (typing it away or
// pressing the cancel button).
- (void) _searchTextDidChange {
    BOOL hasText = [[self stringValue] length] > 0;

    if (hasText == _searching)
        return;
    _searching = hasText;

    id delegate = [self delegate];
    SEL selector = hasText ? @selector(searchFieldDidStartSearching:) : @selector(searchFieldDidEndSearching:);

    if ([delegate respondsToSelector: selector])
        [delegate performSelector: selector withObject: self];
}

- (void) textDidChange: (NSNotification *) note {
    [super textDidChange: note];
    [self _searchTextDidChange];
}

@end
