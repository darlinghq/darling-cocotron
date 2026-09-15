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
#import <AppKit/NSRaise.h>
#import <AppKit/NSTreeController.h>
#import <AppKit/NSTreeNode.h>
#import <Foundation/NSIndexPath.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSSortDescriptor.h>

@interface NSObjectController (private)
- (void) _selectionWillChange;
- (void) _selectionDidChange;
@end

@interface NSTreeController (private)
- (NSArray *) _childNodesOfNode: (NSTreeNode *) node;
- (BOOL) _isLeafNode: (NSTreeNode *) node;
- (NSIndexPath *) _indexPathOfObject: (id) object below: (NSTreeNode *) node;
@end

// Builds its children from the controller's key paths the first time they are asked for.
@interface _NSTreeControllerNode : NSTreeNode {
    NSTreeController *_controller;
    BOOL _childNodesLoaded;
}
- (instancetype) initWithRepresentedObject: (id) object
                                controller: (NSTreeController *) controller;
- (void) _detachController;
@end

@implementation _NSTreeControllerNode

- (instancetype) initWithRepresentedObject: (id) object
                                controller: (NSTreeController *) controller
{
    if ((self = [super initWithRepresentedObject: object]))
        _controller = controller;
    return self;
}

- (NSArray *) childNodes {
    if (!_childNodesLoaded && _controller != nil) {
        _childNodesLoaded = YES;
        _childNodes = [[_controller _childNodesOfNode: self] mutableCopy];
        for (_NSTreeControllerNode *child in _childNodes)
            child->_parentNode = self;
    }
    return [super childNodes];
}

- (BOOL) isLeaf {
    return _controller ? [_controller _isLeafNode: self] : [super isLeaf];
}

// Views can keep nodes alive after their controller is gone.
- (void) _detachController {
    _controller = nil;
    for (_NSTreeControllerNode *child in _childNodes)
        [child _detachController];
}

@end

@implementation NSTreeController

+ (void) initialize {
    [self setKeys: [NSArray arrayWithObjects: @"content", nil]
            triggerChangeNotificationsForDependentKey: @"contentArray"];
    NSArray *selectionKeys = [NSArray
            arrayWithObjects: @"content", @"selectionIndexPaths", nil];
    [self setKeys: selectionKeys
            triggerChangeNotificationsForDependentKey: @"selectionIndexPath"];
    [self setKeys: selectionKeys
            triggerChangeNotificationsForDependentKey: @"selectedObjects"];
    [self setKeys: selectionKeys
            triggerChangeNotificationsForDependentKey: @"selectedNodes"];
}

- (id) init {
    return [self initWithContent: nil];
}

- (id) initWithContent: (id) content {
    if ((self = [super initWithContent: content])) {
        _avoidsEmptySelection = YES;
        _preservesSelection = YES;
        _selectsInsertedObjects = YES;
        _selectionIndexPaths = [[NSArray alloc] init];
        [self setContent: content];
    }
    return self;
}

- (id) initWithCoder: (NSCoder *) coder {
    if ((self = [super initWithCoder: coder])) {
        _childrenKeyPath =
                [[coder decodeObjectForKey: @"NSTreeContentChildrenKey"] copy];
        _countKeyPath =
                [[coder decodeObjectForKey: @"NSTreeContentCountKey"] copy];
        _leafKeyPath = [[coder decodeObjectForKey: @"NSTreeContentLeafKey"] copy];
        _avoidsEmptySelection =
                [coder decodeBoolForKey: @"NSAvoidsEmptySelection"];
        _preservesSelection = [coder decodeBoolForKey: @"NSPreservesSelection"];
        _selectsInsertedObjects =
                [coder decodeBoolForKey: @"NSSelectsInsertedObjects"];
        _alwaysUsesMultipleValuesMarker =
                [coder decodeBoolForKey: @"NSAlwaysUsesMultipleValuesMarker"];
        _selectionIndexPaths = [[NSArray alloc] init];
        [self rearrangeObjects];
    }
    return self;
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- copyWithZone: (NSZone *) zone {
    NSUnimplementedMethod();
    return [self retain];
}

- (void) dealloc {
    [_childrenKeyPath release];
    [_countKeyPath release];
    [_leafKeyPath release];
    [_sortDescriptors release];
    [_selectionIndexPaths release];
    [(_NSTreeControllerNode *) _arrangedRoot _detachController];
    [_arrangedRoot release];
    [super dealloc];
}

#pragma mark Key paths and flags

- (NSString *) childrenKeyPath {
    return _childrenKeyPath;
}

- (void) setChildrenKeyPath: (NSString *) keyPath {
    [_childrenKeyPath autorelease];
    _childrenKeyPath = [keyPath copy];
    [self rearrangeObjects];
}

- (NSString *) countKeyPath {
    return _countKeyPath;
}

- (void) setCountKeyPath: (NSString *) keyPath {
    [_countKeyPath autorelease];
    _countKeyPath = [keyPath copy];
    [self rearrangeObjects];
}

- (NSString *) leafKeyPath {
    return _leafKeyPath;
}

- (void) setLeafKeyPath: (NSString *) keyPath {
    [_leafKeyPath autorelease];
    _leafKeyPath = [keyPath copy];
    [self rearrangeObjects];
}

- (NSArray *) sortDescriptors {
    return _sortDescriptors;
}

- (void) setSortDescriptors: (NSArray *) descriptors {
    [_sortDescriptors autorelease];
    _sortDescriptors = [descriptors copy];
    [self rearrangeObjects];
}

- (BOOL) avoidsEmptySelection {
    return _avoidsEmptySelection;
}

- (void) setAvoidsEmptySelection: (BOOL) flag {
    _avoidsEmptySelection = flag;
}

- (BOOL) preservesSelection {
    return _preservesSelection;
}

- (void) setPreservesSelection: (BOOL) flag {
    _preservesSelection = flag;
}

- (BOOL) selectsInsertedObjects {
    return _selectsInsertedObjects;
}

- (void) setSelectsInsertedObjects: (BOOL) flag {
    _selectsInsertedObjects = flag;
}

- (BOOL) alwaysUsesMultipleValuesMarker {
    return _alwaysUsesMultipleValuesMarker;
}

- (void) setAlwaysUsesMultipleValuesMarker: (BOOL) flag {
    _alwaysUsesMultipleValuesMarker = flag;
}

#pragma mark Content

- (void) setContent: (id) content {
    [super setContent: content];
    [self rearrangeObjects];
}

// Target of the "contentArray" binding.
- (void) _setContentArray: (id) content {
    [self setContent: content];
}

- (id) _contentArray {
    return [self content];
}

- (id) arrangedObjects {
    return [[_arrangedRoot retain] autorelease];
}

- (void) rearrangeObjects {
    NSMutableArray *oldPaths = [NSMutableArray array];
    NSMutableArray *oldObjects = [NSMutableArray array];
    if (_preservesSelection) {
        for (NSIndexPath *path in _selectionIndexPaths) {
            id object = [[_arrangedRoot descendantNodeAtIndexPath: path]
                    representedObject];
            if (object != nil) {
                [oldPaths addObject: path];
                [oldObjects addObject: object];
            }
        }
    }
    _NSTreeControllerNode *oldRoot = (_NSTreeControllerNode *) _arrangedRoot;

    [self _selectionWillChange];
    [self willChangeValueForKey: @"arrangedObjects"];
    _arrangedRoot = [[_NSTreeControllerNode alloc] initWithRepresentedObject: nil
                                                                  controller: self];
    [self didChangeValueForKey: @"arrangedObjects"];
    [oldRoot _detachController];
    [oldRoot autorelease];

    NSMutableArray *paths = [NSMutableArray array];
    NSUInteger i;
    for (i = 0; i < [oldObjects count]; i++) {
        id object = [oldObjects objectAtIndex: i];
        NSIndexPath *path = [oldPaths objectAtIndex: i];
        if ([[_arrangedRoot descendantNodeAtIndexPath: path] representedObject] !=
            object)
            path = [self _indexPathOfObject: object below: _arrangedRoot];
        if (path != nil)
            [paths addObject: path];
    }
    [self setSelectionIndexPaths: paths];
    [self _selectionDidChange];
}

// Depth-first search by identity; used to keep the selected objects selected.
- (NSIndexPath *) _indexPathOfObject: (id) object below: (NSTreeNode *) node {
    for (NSTreeNode *child in [node childNodes]) {
        if ([child representedObject] == object)
            return [child indexPath];
        NSIndexPath *path = [self _indexPathOfObject: object below: child];
        if (path != nil)
            return path;
    }
    return nil;
}

- (NSArray *) _childNodesOfNode: (NSTreeNode *) node {
    NSArray *objects;

    if (node == _arrangedRoot) {
        id content = [self content];
        if (content == nil)
            objects = [NSArray array];
        else if ([content isKindOfClass: [NSArray class]])
            objects = content;
        else
            objects = [NSArray arrayWithObject: content];
    } else if (_childrenKeyPath == nil ||
               ((_leafKeyPath != nil || _countKeyPath != nil) &&
                [self _isLeafNode: node])) {
        return [NSArray array];
    } else {
        objects = [[node representedObject] valueForKeyPath: _childrenKeyPath];
    }

    if ([_sortDescriptors count] > 0)
        objects = [objects sortedArrayUsingDescriptors: _sortDescriptors];

    NSMutableArray *nodes = [NSMutableArray arrayWithCapacity: [objects count]];
    for (id object in objects) {
        _NSTreeControllerNode *child =
                [[_NSTreeControllerNode alloc] initWithRepresentedObject: object
                                                              controller: self];
        [nodes addObject: child];
        [child release];
    }
    return nodes;
}

- (BOOL) _isLeafNode: (NSTreeNode *) node {
    if (node == _arrangedRoot)
        return NO;
    id object = [node representedObject];
    if (_leafKeyPath != nil)
        return [[object valueForKeyPath: _leafKeyPath] boolValue];
    if (_countKeyPath != nil)
        return [[object valueForKeyPath: _countKeyPath] integerValue] == 0;
    return [[node childNodes] count] == 0;
}

#pragma mark Selection

- (NSArray *) selectionIndexPaths {
    return [[_selectionIndexPaths retain] autorelease];
}

- (BOOL) setSelectionIndexPaths: (NSArray *) indexPaths {
    if (indexPaths == nil)
        indexPaths = [NSArray array];
    if ([indexPaths count] == 0 && _avoidsEmptySelection &&
        [[_arrangedRoot childNodes] count] > 0)
        indexPaths = [NSArray arrayWithObject: [NSIndexPath indexPathWithIndex: 0]];

    if ([_selectionIndexPaths isEqualToArray: indexPaths])
        return NO;

    [self willChangeValueForKey: @"selectionIndexPaths"];
    [self _selectionWillChange];
    [_selectionIndexPaths release];
    _selectionIndexPaths = [indexPaths copy];
    [self _selectionDidChange];
    [self didChangeValueForKey: @"selectionIndexPaths"];
    return YES;
}

- (NSIndexPath *) selectionIndexPath {
    return [_selectionIndexPaths count] ? [_selectionIndexPaths objectAtIndex: 0]
                                        : nil;
}

- (BOOL) setSelectionIndexPath: (NSIndexPath *) indexPath {
    return [self setSelectionIndexPaths: indexPath ? [NSArray arrayWithObject: indexPath]
                                                   : nil];
}

- (BOOL) addSelectionIndexPaths: (NSArray *) indexPaths {
    NSMutableArray *paths = [[_selectionIndexPaths mutableCopy] autorelease];
    for (NSIndexPath *path in indexPaths)
        if (![paths containsObject: path])
            [paths addObject: path];
    return [self setSelectionIndexPaths: paths];
}

- (BOOL) removeSelectionIndexPaths: (NSArray *) indexPaths {
    NSMutableArray *paths = [[_selectionIndexPaths mutableCopy] autorelease];
    [paths removeObjectsInArray: indexPaths];
    return [self setSelectionIndexPaths: paths];
}

- (NSArray *) selectedNodes {
    NSMutableArray *nodes = [NSMutableArray array];
    for (NSIndexPath *path in _selectionIndexPaths) {
        NSTreeNode *node = [_arrangedRoot descendantNodeAtIndexPath: path];
        if (node != nil)
            [nodes addObject: node];
    }
    return nodes;
}

- (NSArray *) selectedObjects {
    return [[self selectedNodes] valueForKey: @"representedObject"];
}

@end
