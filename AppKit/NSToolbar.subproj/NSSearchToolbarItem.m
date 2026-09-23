#import <AppKit/NSSearchToolbarItem.h>
#import <AppKit/NSSearchField.h>
#import <AppKit/NSSearchFieldCell.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSEvent.h>

@interface _NSSearchToolbarFieldCell : NSSearchFieldCell {
    BOOL _resignsFirstResponderWithCancel;
}
@property BOOL resignsFirstResponderWithCancel;
@end

@implementation _NSSearchToolbarFieldCell

@synthesize resignsFirstResponderWithCancel = _resignsFirstResponderWithCancel;

- (BOOL) trackMouse: (NSEvent *) event
              inRect: (NSRect) frame
              ofView: (NSView *) view
        untilMouseUp: (BOOL) untilMouseUp
{
    NSPoint point = [view convertPoint: [event locationInWindow] fromView: nil];
    BOOL clickedCancel = NSPointInRect(point, [self cancelButtonRectForBounds: frame]);
    BOOL handled = [super trackMouse: event
                             inRect: frame
                             ofView: view
                       untilMouseUp: untilMouseUp];
    if (handled && clickedCancel && _resignsFirstResponderWithCancel)
        [[view window] makeFirstResponder: nil];
    return handled;
}

@end

@implementation NSSearchToolbarItem

- (instancetype) initWithItemIdentifier: (NSToolbarItemIdentifier) identifier {
    if ((self = [super initWithItemIdentifier: identifier])) {
        _preferredWidthForSearchField = 180;
        _resignsFirstResponderWithCancel = YES;
        _searchField = [[NSSearchField alloc]
                initWithFrame: NSMakeRect(0, 0, _preferredWidthForSearchField, 26)];
        _NSSearchToolbarFieldCell *cell = [[_NSSearchToolbarFieldCell alloc] init];
        [cell setResignsFirstResponderWithCancel: YES];
        [_searchField setCell: cell];
        [cell release];
        [self setView: _searchField];
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
    [(_NSSearchToolbarFieldCell *) [_searchField cell]
            setResignsFirstResponderWithCancel: value];
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
