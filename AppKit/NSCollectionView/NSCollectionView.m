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
#import <AppKit/NSCollectionView.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSCollectionViewFlowLayout.h>
#include <math.h>

@implementation NSCollectionView
@synthesize collectionViewLayout = _collectionViewLayout;
@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;
@synthesize selectionIndexPaths = _selectionIndexPaths;

- initWithCoder: (NSCoder *) coder {
    [super initWithCoder: coder];

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;
    } else
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %s] is not implemented for coder %@",
                            [self class], sel_getName(_cmd), coder];

    return self;
}

- (NSArray *) content {
    return _content;
}

- (NSCollectionViewItem *) itemPrototype {
    return _itemPrototype;
}

- (BOOL) isSelectable {
    return _isSelectable;
}

- (NSSize) minItemSize {
    return _minItemSize;
}

- (NSSize) maxItemSize {
    return _maxItemSize;
}

- (NSUInteger) maxNumberOfRows {
    return _maxNumberOfRows;
}

- (NSUInteger) maxNumberOfColumns {
    return _maxNumberOfColumns;
}

- (NSArray *) backgroundColors {
    return _backgroundColors;
}

- (BOOL) allowsMultipleSelection {
    return _allowsMultipleSelection;
}

- (NSIndexSet *) selectionIndexes {
    return _selectionIndexes;
}

- (void) setContent: (NSArray *) value {
    value = [value retain];
    [_content release];
    _content = value;
}

- (void) setItemPrototype: (NSCollectionViewItem *) value {
    value = [value retain];
    [_itemPrototype release];
    _itemPrototype = value;
}

- (void) setSelectable: (BOOL) value {
    _isSelectable = value;
}

- (void) setMinItemSize: (NSSize) value {
    _minItemSize = value;
}

- (void) setMaxItemSize: (NSSize) value {
    _maxItemSize = value;
}

- (void) setMaxNumberOfRows: (NSUInteger) value {
    _maxNumberOfRows = value;
}

- (void) setMaxNumberOfColumns: (NSUInteger) value {
    _maxNumberOfColumns = value;
}

- (void) setBackgroundColors: (NSArray *) value {
    value = [value copy];
    [_backgroundColors release];
    _backgroundColors = value;
}

- (void) setAllowsMultipleSelection: (BOOL) value {
    _allowsMultipleSelection = value;
}

- (void) setSelectionIndexes: (NSIndexSet *) value {
    value = [value copy];
    [_selectionIndexes release];
    _selectionIndexes = value;
}

- (BOOL) isFirstResponder {
    return ([[self window] firstResponder] == self) ? YES : NO;
}

- (NSCollectionViewItem *) newItemForRepresentedObject: object {
    NSUnimplementedMethod();
    return nil;
}

- (void) dealloc {
    [_content release];
    [_itemPrototype release];
    [_backgroundColors release];
    [_selectionIndexes release];
    [_collectionViewLayout release];
    [_selectionIndexPaths release];
    [_itemClasses release];
    [_loadedItems release];
    [_loadedPaths release];
    [super dealloc];
}

- (BOOL)isFlipped { return YES; }

- (NSInteger)numberOfSections {
    if (_dataSource == nil) return 0;
    NSInteger count = [_dataSource respondsToSelector:@selector(numberOfSectionsInCollectionView:)]
        ? [_dataSource numberOfSectionsInCollectionView:self] : 1;
    if (count < 0)
        [NSException raise:NSInvalidArgumentException format:@"negative collection section count"];
    return count;
}

- (NSInteger)numberOfItemsInSection:(NSInteger)section {
    if (section < 0 || section >= [self numberOfSections])
        [NSException raise:NSInvalidArgumentException format:@"invalid collection section"];
    NSInteger count = [_dataSource collectionView:self numberOfItemsInSection:section];
    if (count < 0)
        [NSException raise:NSInvalidArgumentException format:@"negative collection item count"];
    return count;
}

- (NSCollectionViewItem *)itemAtIndexPath:(NSIndexPath *)path {
    return [_loadedItems objectForKey:path];
}

- (void)_layoutLoadedItems {
    if (_loadedPaths == nil) return;
    if (![_collectionViewLayout isKindOfClass:[NSCollectionViewFlowLayout class]])
        [NSException raise:NSInvalidArgumentException format:@"collection reload requires a flow layout"];
    NSCollectionViewFlowLayout *layout = (NSCollectionViewFlowLayout *)_collectionViewLayout;
    NSSize size = [layout itemSize];
    NSEdgeInsets inset = [layout sectionInset];
    CGFloat line = [layout minimumLineSpacing], gap = [layout minimumInteritemSpacing];
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0
        || !isfinite(line) || !isfinite(gap) || line < 0 || gap < 0
        || !isfinite(inset.top) || !isfinite(inset.left) || !isfinite(inset.bottom) || !isfinite(inset.right)
        || inset.top < 0 || inset.left < 0 || inset.bottom < 0 || inset.right < 0)
        [NSException raise:NSInvalidArgumentException format:@"invalid collection flow geometry"];
    CGFloat available = NSWidth([self bounds]) - inset.left - inset.right;
    if (!isfinite(available))
        [NSException raise:NSInvalidArgumentException format:@"invalid collection width"];
    NSUInteger columns = MAX(1, (NSUInteger)MAX(0, floor((available + gap) / (size.width + gap))));
    CGFloat y = 0; NSInteger section = -1; NSUInteger index = 0;
    for (NSIndexPath *path in _loadedPaths) {
        if ([path section] != section) {
            if (section >= 0) y += ((index + columns - 1) / columns) * (size.height + line) - line + inset.bottom;
            section = [path section]; index = 0; y += inset.top;
        }
        NSRect frame = NSMakeRect(inset.left + (index % columns) * (size.width + gap),
            y + (index / columns) * (size.height + line), size.width, size.height);
        [[[_loadedItems objectForKey:path] view] setFrame:frame]; index++;
    }
    CGFloat height = section < 0 ? 0 : y + ((index + columns - 1) / columns) * (size.height + line) - line + inset.bottom;
    NSRect frame = [self frame]; frame.size.height = MAX(0, height);
    [super setFrame:frame];
    [self setNeedsDisplay:YES];
}

- (void)setFrame:(NSRect)frame {
    [super setFrame:frame]; [self _layoutLoadedItems];
}

- (void)reloadData {
    if (_dataSource != nil && (![_dataSource respondsToSelector:@selector(collectionView:numberOfItemsInSection:)]
        || ![_dataSource respondsToSelector:@selector(collectionView:itemForRepresentedObjectAtIndexPath:)]))
        [NSException raise:NSInvalidArgumentException format:@"collection data source lacks required methods"];
    NSMutableDictionary *items = [NSMutableDictionary dictionary];
    NSMutableArray *paths = [NSMutableArray array];
    NSInteger sections = [self numberOfSections];
    for (NSInteger section = 0; section < sections; section++) {
        NSInteger count = [self numberOfItemsInSection:section];
        for (NSInteger index = 0; index < count; index++) {
            NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:section];
            NSCollectionViewItem *item = [_dataSource collectionView:self itemForRepresentedObjectAtIndexPath:path];
            if (![item isKindOfClass:[NSCollectionViewItem class]] || [item view] == nil)
                [NSException raise:NSInvalidArgumentException format:@"collection data source returned an invalid item"];
            [items setObject:item forKey:path]; [paths addObject:path];
        }
    }
    for (NSCollectionViewItem *item in [_loadedItems allValues]) [[item view] removeFromSuperview];
    [_loadedItems release]; _loadedItems = [items mutableCopy];
    [_loadedPaths release]; _loadedPaths = [paths copy];
    for (NSIndexPath *path in _loadedPaths) [self addSubview:[[_loadedItems objectForKey:path] view]];
    [self _layoutLoadedItems];
}

- (NSSet *) selectionIndexPaths {
    return _selectionIndexPaths ? _selectionIndexPaths : [NSSet set];
}

- (void) setSelectionIndexPaths: (NSSet *) value {
    value = [value copy];
    [_selectionIndexPaths release];
    _selectionIndexPaths = value;
}

- (void) registerClass: (Class) itemClass forItemWithIdentifier: (NSString *) identifier {
    if (_itemClasses == nil)
        _itemClasses = [[NSMutableDictionary alloc] init];
    if (itemClass != Nil)
        [_itemClasses setObject: itemClass forKey: identifier];
    else
        [_itemClasses removeObjectForKey: identifier];
}

// Items aren't reused: nothing lays them out or recycles them yet.
- (NSCollectionViewItem *) makeItemWithIdentifier: (NSString *) identifier
                                     forIndexPath: (NSIndexPath *) indexPath
{
    Class itemClass = [_itemClasses objectForKey: identifier];
    if (itemClass == Nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[%@ %s]: no item class registered for identifier %@",
                            [self class], sel_getName(_cmd), identifier];
    return [[[itemClass alloc] init] autorelease];
}

@end

@implementation NSIndexPath (NSCollectionViewAdditions)

+ (NSIndexPath *) indexPathForItem: (NSInteger) item inSection: (NSInteger) section {
    NSUInteger indexes[2] = {section, item};
    return [self indexPathWithIndexes: indexes length: 2];
}

- (NSInteger) item {
    return [self indexAtPosition: 1];
}

- (NSInteger) section {
    return [self indexAtPosition: 0];
}

@end
