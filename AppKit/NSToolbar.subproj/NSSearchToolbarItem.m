#import <AppKit/NSSearchToolbarItem.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>

@interface NSSearchFieldCell (NSSearchToolbarItem)
- (void) _setResignsFirstResponderWithCancel: (BOOL) value;
@end

@implementation NSSearchToolbarItem

- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier {
    if ((self = [super initWithItemIdentifier: identifier])) {
        _preferredWidthForSearchField = 180;
        _searchField = [[NSSearchField alloc]
                initWithFrame: NSMakeRect(0, 0, _preferredWidthForSearchField, 26)];
        [self setView: _searchField];
        [self setResignsFirstResponderWithCancel: YES];
    }
    return self;
}

// A nib archives the search field as the item's view.
- (instancetype) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder])) {
        NSView *view = [self view];
        if (![view isKindOfClass: [NSSearchField class]]) {
            [self release];
            [NSException raise: NSInvalidArgumentException
                        format: @"NSSearchToolbarItem archived with a %@ view, not an NSSearchField",
                                [view class]];
        }
        _searchField = (NSSearchField *) [view retain];
        _preferredWidthForSearchField = [_searchField frame].size.width;
        [self setResignsFirstResponderWithCancel: YES];
    }
    return self;
}

- (void) dealloc {
    [_searchField release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *) zone {
    NSSearchToolbarItem *copy = [[[self class] allocWithZone: zone]
            initWithItemIdentifier: [self itemIdentifier]];
    [copy setPreferredWidthForSearchField: _preferredWidthForSearchField];
    [copy setResignsFirstResponderWithCancel: _resignsFirstResponderWithCancel];
    [copy setLabel: [self label]];
    [copy setPaletteLabel: [self paletteLabel]];
    [copy setToolTip: [self toolTip]];
    [[copy searchField] setStringValue: [_searchField stringValue]];
    [[copy searchField] setTarget: [_searchField target]];
    [[copy searchField] setAction: [_searchField action]];
    return copy;
}

- (NSSearchField *) searchField {
    return _searchField;
}

- (CGFloat) preferredWidthForSearchField {
    return _preferredWidthForSearchField;
}

- (void) setPreferredWidthForSearchField: (CGFloat) width {
    if (width <= 0)
        return;
    _preferredWidthForSearchField = width;
    NSRect frame = [_searchField frame];
    frame.size.width = width;
    [_searchField setFrame: frame];
    [self setMinSize: frame.size];
    [self setMaxSize: frame.size];
}

- (BOOL) resignsFirstResponderWithCancel {
    return _resignsFirstResponderWithCancel;
}

- (void) setResignsFirstResponderWithCancel: (BOOL) value {
    _resignsFirstResponderWithCancel = value;
    [[_searchField cell] _setResignsFirstResponderWithCancel: value];
}

- (void) beginSearchInteraction {
    [[_searchField window] makeFirstResponder: _searchField];
}

- (void) endSearchInteraction {
    NSWindow *window = [_searchField window];
    if ([window firstResponder] == _searchField)
        [window makeFirstResponder: nil];
}

@end
