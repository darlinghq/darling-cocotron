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
@class NSImageView;
@class NSTextField;

@class NSCollectionViewLayoutAttributes;

typedef NS_ENUM(NSInteger, NSCollectionViewItemHighlightState) {
    NSCollectionViewItemHighlightNone = 0,
    NSCollectionViewItemHighlightForSelection = 1,
    NSCollectionViewItemHighlightForDeselection = 2,
    NSCollectionViewItemHighlightAsDropTarget = 3,
};

// Declared with NSCollectionView on macOS; here, so that NSCollectionViewItem can adopt it
@protocol NSCollectionViewElement <NSObject>
@optional
- (void) prepareForReuse;
- (void) applyLayoutAttributes: (NSCollectionViewLayoutAttributes *) layoutAttributes;
@end

#define _NS_SIDE_NSCollectionViewItem 0, 1,
// Legacy ObjC ABI (i386): add new state to the extra struct, never as an ivar.
@interface NSCollectionViewItem : NSViewController <NSCollectionViewElement, NSCoding, NSCopying> {
    NSCollectionView *_collectionView;
    BOOL _isSelected;
    unsigned char _highlightState; // an NSCollectionViewItemHighlightState
    NS_LEGACY_IVAR_PAD(_NSCollectionViewItemReserved, 7)
    NS_EXTRA_IVARS_BEGIN(NSCollectionViewItem)
        NSImageView *_imageView;
        NSTextField *_textField;
    NS_SIDE_IVARS_END(NSCollectionViewItem)
}

- (NSCollectionView *) collectionView;

- (BOOL) isSelected;

- (void) setSelected: (BOOL) value;
@property(getter=isSelected) BOOL selected;
@property NSCollectionViewItemHighlightState highlightState;

// Views of the item's view that show its image and its title. Retained (observed on macOS 10.14 and 26).
@property(retain) IBOutlet NSImageView *imageView;
@property(retain) IBOutlet NSTextField *textField;

// Called before the collection view hands out the item again for another index path
- (void) prepareForReuse;

@end
