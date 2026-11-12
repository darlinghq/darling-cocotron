#import <AppKit/NSToolbarItem.h>

@class NSSearchField;

@interface NSSearchToolbarItem : NSToolbarItem {
    NSSearchField *_searchField;
    CGFloat _preferredWidthForSearchField;
    BOOL _resignsFirstResponderWithCancel;
}

@property CGFloat preferredWidthForSearchField;
@property BOOL resignsFirstResponderWithCancel;
@property (readonly) NSSearchField *searchField;

- (void) beginSearchInteraction;
- (void) endSearchInteraction;

@end
