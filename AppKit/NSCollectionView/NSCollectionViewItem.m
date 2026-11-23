/* Copyright (c) 2009 Christopher J. W. Lloyd

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
#import <AppKit/NSCollectionViewItem.h>
#import <AppKit/NSRaise.h>
#import <Foundation/NSKeyedArchiver.h>

@implementation NSCollectionViewItem

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

    } else {
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];
    }

    return self;
}

- copyWithZone: (NSZone *) zone {
    NSUnimplementedMethod();
    return nil;
}

- (NSCollectionView *) collectionView {
    return _collectionView;
}

- (BOOL) isSelected {
    return _isSelected;
}

- (void) setSelected: (BOOL) value {
    _isSelected = value;
}

- (NSCollectionViewItemHighlightState) highlightState {
    return (NSCollectionViewItemHighlightState) _highlightState;
}

- (void) setHighlightState: (NSCollectionViewItemHighlightState) state {
    _highlightState = (unsigned char) state;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSCollectionViewItem, self)) {
        [NS_EXTRA(NSCollectionViewItem, self)->_imageView release];
        [NS_EXTRA(NSCollectionViewItem, self)->_textField release];
    }
    NS_EXTRA_FREE(NSCollectionViewItem, self);
    [super dealloc];
}

- (NSImageView *) imageView {
    return NS_EXTRA(NSCollectionViewItem, self)->_imageView;
}

- (void) setImageView: (NSImageView *) view {
    [view retain];
    [NS_EXTRA(NSCollectionViewItem, self)->_imageView release];
    NS_EXTRA(NSCollectionViewItem, self)->_imageView = view;
}

- (NSTextField *) textField {
    return NS_EXTRA(NSCollectionViewItem, self)->_textField;
}

- (void) setTextField: (NSTextField *) field {
    [field retain];
    [NS_EXTRA(NSCollectionViewItem, self)->_textField release];
    NS_EXTRA(NSCollectionViewItem, self)->_textField = field;
}

- (void) prepareForReuse {
}

// Set by the collection view that shows the item; it doesn't retain the collection view
- (void) _setCollectionView: (NSCollectionView *) collectionView {
    _collectionView = collectionView;
}

@end
