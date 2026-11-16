#import <AppKit/NSTextFieldCell.h>

@interface NSPathComponentCell : NSTextFieldCell {
    NSURL *_URL;
    NS_LEGACY_IVAR_PAD(_NSPathComponentCellReserved, 24)
}

- (NSURL *) URL;
- (void) setURL: (NSURL *) value;

@end
