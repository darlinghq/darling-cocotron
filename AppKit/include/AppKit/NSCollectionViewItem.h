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
#import <AppKit/NSViewController.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSCollectionView;

@class NSCollectionViewLayoutAttributes;

// Declared with NSCollectionView on macOS; here, so that NSCollectionViewItem can adopt it
@protocol NSCollectionViewElement <NSObject>
@optional
- (void) prepareForReuse;
- (void) applyLayoutAttributes: (NSCollectionViewLayoutAttributes *) layoutAttributes;
@end

@interface NSCollectionViewItem : NSViewController <NSCollectionViewElement, NSCoding, NSCopying> {
    NSCollectionView *_collectionView;
    BOOL _isSelected;
    NS_LEGACY_IVAR_PAD(_NSCollectionViewItemReserved, 8)
}

- (NSCollectionView *) collectionView;

- (BOOL) isSelected;

- (void) setSelected: (BOOL) value;

// Called before the collection view hands out the item again for another index path
- (void) prepareForReuse;

@end
