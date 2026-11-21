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

#import <AppKit/NSButtonCell.h>
#import <AppKit/NSControl.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSGraphicsStyle.h>
#import <AppKit/NSView.h>
#import <AppKit/NSTextField.h>
#import <AppKit/NSWindow.h>

@interface NSTextFieldCell (AquaRoundedBezel)
- (CGFloat) _aquaRoundedBezelHeight;
- (NSRect) _aquaRoundedBezelRectForFrame: (NSRect) frame inView: (NSView *) control;
@end

@implementation NSSearchFieldCell

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];
    _searchButtonCell = [[NSButtonCell alloc]
            initImageCell: [NSImage imageNamed: @"NSSearchGlass"]];
    [_searchButtonCell setImageScaling: NSImageScaleProportionallyUpOrDown];
    _cancelButtonCell = [[NSButtonCell alloc]
            initImageCell:
                    [NSImage
                            imageNamed: @"NSStopProgressFreestandingTemplate"]];
    [_cancelButtonCell setImageScaling: NSImageScaleProportionallyUpOrDown];

    if (![coder allowsKeyedCoding]) {
        // The search and cancel button cells, the search menu template, the recents autosave
        // name, two bytes (sends the whole search string; maximum recents, -1 for the
        // default), a flag word (bit 27 sends the search string immediately) and three
        // unused ints. The button cells of an archive carry no images (the system draws
        // them), so the ones made above stay.
        id searchCell = nil, cancelCell = nil, menu = nil, autosaveName = nil;
        char wholeString, maximumRecents;
        int flags, unused[3];

        [coder decodeValuesOfObjCTypes: "@@@@cciiii", &searchCell, &cancelCell, &menu, &autosaveName, &wholeString,
                                        &maximumRecents, &flags, &unused[0], &unused[1], &unused[2]];
        [searchCell release];
        [cancelCell release];
        _searchMenuTemplate = [menu isKindOfClass: [NSMenu class]] ? menu : nil;
        if (_searchMenuTemplate == nil)
            [menu release];
        [self setRecentsAutosaveName: [autosaveName isKindOfClass: [NSString class]] ? autosaveName : nil];
        [autosaveName release];
        _sendsWholeSearchString = wholeString != 0;
        _sendsSearchStringImmediately = ((unsigned) flags & 0x08000000u) != 0;
        if (maximumRecents >= 0)
            _maximumRecents = maximumRecents;
    }
    return self;
}

// QUIRK: a new search field cell keeps its text on one line, clipped, where a text field wraps it. Not
// documented. Evidence: black-box observation of NSSearchField on macOS 10.14.4 and 26.7.3 (tier 2),
// probe mac-probes/aqua-metric-followups.m of the research notes.
// Test: appkit-combobox-search-field-cell-size.m (test_quirk_single_line_defaults)
- initTextCell: (NSString *) string {
    [super initTextCell: string];
    [self setWraps: NO];
    _searchButtonCell = [[NSButtonCell alloc]
            initImageCell: [NSImage imageNamed: @"NSSearchGlass"]];
    [_searchButtonCell setImageScaling: NSImageScaleProportionallyUpOrDown];
    _cancelButtonCell = [[NSButtonCell alloc]
            initImageCell:
                    [NSImage
                            imageNamed: @"NSStopProgressFreestandingTemplate"]];
    [_cancelButtonCell setImageScaling: NSImageScaleProportionallyUpOrDown];
    return self;
}

- (void) dealloc {
    [_searchButtonCell release];
    [_cancelButtonCell release];
    [super dealloc];
}

- (NSArray *) recentSearches {
    return _recentSearches;
}

- (NSString *) recentsAutosaveName {
    return _autosaveName;
}

- (int) maximumRecents {
    return _maximumRecents;
}

- (BOOL) sendsWholeSearchString {
    return _sendsWholeSearchString;
}

- (BOOL) sendsSearchStringImmediately {
    return _sendsSearchStringImmediately;
}

- (NSButtonCell *) searchButtonCell {
    return _searchButtonCell;
}

- (NSButtonCell *) cancelButtonCell {
    return _cancelButtonCell;
}

- (NSMenu *) searchMenuTemplate {
    return _searchMenuTemplate;
}

- (void) setRecentSearches: (NSArray *) searches {
    searches = [searches copy];
    [_recentSearches release];
    _recentSearches = searches;
}

- (void) setRecentsAutosaveName: (NSString *) name {
    name = [name copy];
    [_autosaveName release];
    _autosaveName = name;
}

- (void) setMaximumRecents: (int) value {
    _maximumRecents = value;
}

- (void) setSendsWholeSearchString: (BOOL) flag {
    _sendsWholeSearchString = flag;
}

- (void) setSendsSearchStringImmediately: (BOOL) flag {
    _sendsSearchStringImmediately = flag;
}

- (void) setSearchButtonCell: (NSButtonCell *) cell {
    cell = [cell retain];
    [_searchButtonCell release];
    _searchButtonCell = cell;
}

- (void) setCancelButtonCell: (NSButtonCell *) cell {
    cell = [cell retain];
    [_cancelButtonCell release];
    _cancelButtonCell = cell;
}

- (void) setSearchMenuTemplate: (NSMenu *) menu {
    menu = [menu retain];
    [_searchMenuTemplate release];
    _searchMenuTemplate = menu;
}

// The search field the cell lays out, if any
- (NSSearchField *) _searchField {
    NSView *view = [self controlView];

    if ([view isKindOfClass: [NSSearchField class]] && [(NSSearchField *) view cell] == self)
        return (NSSearchField *) view;
    return nil;
}

// QUIRK: in a search field, the text and the search button go where the
// field's rectForSearchTextWhenCentered: and rectForSearchButtonWhenCentered:
// (with YES) put them, so that a subclass of the field can move them; the
// cancel button is the cell's own. Not documented. Evidence: black-box
// observation on macOS 10.14.4 and 26.7.3 (tier 2).
// Test: tests/appkit-searchfield-centered-rects.m
- (NSRect) searchTextRectForBounds: (NSRect) rect {
    NSSearchField *field = [self _searchField];

    if (field != nil)
        return [field rectForSearchTextWhenCentered: YES];
    return [self _searchTextRectForBounds: rect];
}

- (NSRect) searchButtonRectForBounds: (NSRect) rect {
    NSSearchField *field = [self _searchField];

    if (field != nil)
        return [field rectForSearchButtonWhenCentered: YES];
    return [self _searchButtonRectForBounds: rect];
}

// The cell's own layout of its parts
- (NSRect) _searchTextRectForBounds: (NSRect) rect {
    return [self titleRectForBounds: rect];
}

// QUIRK: the magnifying glass is 14 points wide and 4 points from the left edge of a search field, the cancel
// button a 14 point disc 4 points from the right edge. Not documented. Evidence: black-box renders on macOS
// 10.14.4 (tier 2). Test: appkit-textfield-aqua.m
- (NSRect) _searchButtonRectForBounds: (NSRect) rect {
    return NSMakeRect(NSMinX(rect) + 4, NSMinY(rect), 14, NSHeight(rect));
}

- (NSRect) cancelButtonRectForBounds: (NSRect) rect {
    return NSMakeRect(NSMaxX(rect) - 4 - 14, NSMidY(rect) - 7, 14, 14);
}

- (void) _setResignsFirstResponderWithCancel: (BOOL) value {
    _resignsFirstResponderWithCancel = value;
}

- (void) resetCancelButtonCell {
    NSUnimplementedMethod();
}

- (void) resetSearchButtonCell {
    NSUnimplementedMethod();
}

// QUIRK: the size of a search field's content is the text plus 42, 41 or 40 points across at the
// regular, small and mini control sizes (21 more than a rounded text field adds), rounded up to
// whole points, and as high as a rounded bezel (22, 19 or 17 points). Not documented. Evidence:
// black-box observation of cellSize and sizeToFit of NSSearchField on macOS 10.14.4 (tier 2;
// macOS 26.7.3 differs: 24/20/16 high and other widths, and Mojave's values are used), probe
// mac-probes/combobox-searchfield-cellsize.m of the research notes.
// Test: appkit-combobox-search-field-cell-size.m (test_quirk_search_field_cell_size)
- (NSSize) cellSize {
    static const CGFloat insets[3] = {42, 41, 40};
    NSControlSize controlSize = [self controlSize];
    NSSize text = [[self attributedStringValue] size];

    return NSMakeSize(ceil(text.width + insets[controlSize == NSSmallControlSize ? 1 : (controlSize == NSMiniControlSize ? 2 : 0)]),
                      [self _aquaRoundedBezelHeight]);
}

- (NSRect) titleRectForBounds: (NSRect) rect {
    NSRect result = [super titleRectForBounds: rect];

    // between the magnifying glass and the cancel button
    result.origin.x = NSMinX(rect) + 20;
    result.size.width = NSWidth(rect) - 20 - 22;

    return result;
}

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) frame
              ofView: (NSView *) view
        untilMouseUp: (BOOL) untilMouseUp
{
    if ([_cancelButtonCell trackMouse: event
                               inRect: [self cancelButtonRectForBounds: frame]
                               ofView: view
                         untilMouseUp: YES]) {
        [(NSControl *) view setStringValue: @""];
        // lets a search field tell its delegate that searching ended
        if ([view respondsToSelector: NSSelectorFromString(@"_searchTextDidChange")])
            [view performSelector: NSSelectorFromString(@"_searchTextDidChange")];

        if (_resignsFirstResponderWithCancel)
            [[view window] makeFirstResponder: nil];
        else if ([view respondsToSelector: @selector(selectText:)])
            [(NSTextField *) view selectText: nil];
        return YES;
    }

    return [super trackMouse: event
                      inRect: frame
                      ofView: view
                untilMouseUp: untilMouseUp];
}

- (void) _drawSquareBezelInRect: (NSRect) frame inView: (NSView *) control {
    [[control graphicsStyle] drawRoundedTextFieldBezelInRect: [self _aquaRoundedBezelRectForFrame: frame inView: control]
                                                      radius: 4
                                                     enabled: [self isEnabled]];
}

- (void) drawWithFrame: (NSRect) frame inView: (NSView *) control {
    [super drawWithFrame: frame inView: control];

    [[control graphicsStyle] drawSearchGlyphInRect: [self searchButtonRectForBounds: frame]
                                       controlSize: [self controlSize]];
    if ([[self attributedStringValue] length] > 0)
        [[control graphicsStyle] drawSearchCancelGlyphInRect: [self cancelButtonRectForBounds: frame]
                                                 controlSize: [self controlSize]];
}

@end
