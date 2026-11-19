/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSTreeNode.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>
#import <Foundation/NSIndexPath.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSSortDescriptor.h>

@implementation NSTreeNode

+ (instancetype) treeNodeWithRepresentedObject: (id) modelObject {
    return [[[self alloc] initWithRepresentedObject: modelObject] autorelease];
}

- (instancetype) initWithRepresentedObject: (id) modelObject {
    if ((self = [super init]))
        _representedObject = [modelObject retain];
    return self;
}

- (void) dealloc {
    // Children can outlive their parent; don't leave them pointing at it.
    for (NSTreeNode *child in _childNodes)
        child->_parentNode = nil;
    [_childNodes release];
    [_representedObject release];
    [super dealloc];
}

- (id) representedObject {
    return _representedObject;
}

- (NSTreeNode *) parentNode {
    return _parentNode;
}

- (NSArray *) childNodes {
    return _childNodes ? (NSArray *) _childNodes : [NSArray array];
}

- (NSMutableArray *) mutableChildNodes {
    // Like on macOS, a key-value coding proxy over the indexed accessors below, so that
    // observers of childNodes see the changes.
    return [self mutableArrayValueForKey: @"childNodes"];
}

- (NSUInteger) countOfChildNodes {
    return [_childNodes count];
}

- (id) objectInChildNodesAtIndex: (NSUInteger) index {
    return [_childNodes objectAtIndex: index];
}

- (void) insertObject: (NSTreeNode *) node inChildNodesAtIndex: (NSUInteger) index {
    if (![node isKindOfClass: [NSTreeNode class]])
        [NSException raise: NSInvalidArgumentException
                    format: @"-[NSTreeNode %@]: %@ is not a tree node", NSStringFromSelector(_cmd), node];
    if (index > [_childNodes count])
        [NSException raise: NSRangeException
                    format: @"-[NSTreeNode %@]: index %lu beyond bounds [0 .. %lu]", NSStringFromSelector(_cmd),
                            (unsigned long) index, (unsigned long) [_childNodes count]];

    [node retain];
    NSTreeNode *previous = node->_parentNode;
    if (previous != nil && previous != self) {
        NSUInteger previousIndex = [previous->_childNodes indexOfObjectIdenticalTo: node];
        if (previousIndex != NSNotFound)
            [[previous mutableChildNodes] removeObjectAtIndex: previousIndex];
    }
    if (_childNodes == nil)
        _childNodes = [[NSMutableArray alloc] init];
    [_childNodes insertObject: node atIndex: index];
    node->_parentNode = self;
    [node release];
}

- (void) removeObjectFromChildNodesAtIndex: (NSUInteger) index {
    NSTreeNode *node = [[_childNodes objectAtIndex: index] retain];
    [_childNodes removeObjectAtIndex: index];
    // A node inserted twice keeps its parent while it is still one of the children.
    if ([_childNodes indexOfObjectIdenticalTo: node] == NSNotFound)
        node->_parentNode = nil;
    [node release];
}

// As on macOS 26.7.3 (black-box), the descriptors compare the represented objects, the sorted
// children replace the list as a whole (observers of childNodes see a setting change), and with
// recursively set every descendant's children are sorted too.
- (void) sortWithSortDescriptors: (NSArray *) sortDescriptors recursively: (BOOL) recursively {
    if ([_childNodes count] > 1 && [sortDescriptors count] > 0) {
        NSArray *sorted = [_childNodes sortedArrayWithOptions: NSSortStable
                                              usingComparator: ^NSComparisonResult(id a, id b) {
            id left = ((NSTreeNode *) a)->_representedObject;
            id right = ((NSTreeNode *) b)->_representedObject;
            for (NSSortDescriptor *descriptor in sortDescriptors) {
                NSComparisonResult result = [descriptor compareObject: left toObject: right];
                if (result != NSOrderedSame)
                    return result;
            }
            return NSOrderedSame;
        }];
        [self willChangeValueForKey: @"childNodes"];
        [_childNodes release];
        _childNodes = [sorted mutableCopy];
        [self didChangeValueForKey: @"childNodes"];
    }
    if (recursively)
        for (NSTreeNode *child in _childNodes)
            [child sortWithSortDescriptors: sortDescriptors recursively: YES];
}

- (BOOL) isLeaf {
    return [[self childNodes] count] == 0;
}

- (NSIndexPath *) indexPath {
    NSUInteger depth = 0;
    for (NSTreeNode *node = self; node->_parentNode; node = node->_parentNode)
        depth++;

    NSUInteger indexes[depth > 0 ? depth : 1];
    NSUInteger position = depth;
    for (NSTreeNode *node = self; node->_parentNode; node = node->_parentNode)
        indexes[--position] =
                [node->_parentNode->_childNodes indexOfObjectIdenticalTo: node];
    return [NSIndexPath indexPathWithIndexes: indexes length: depth];
}

- (NSTreeNode *) descendantNodeAtIndexPath: (NSIndexPath *) indexPath {
    NSTreeNode *node = self;
    NSUInteger i, length = [indexPath length];

    for (i = 0; i < length && node != nil; i++) {
        NSArray *children = [node childNodes];
        NSUInteger index = [indexPath indexAtPosition: i];
        node = index < [children count] ? [children objectAtIndex: index] : nil;
    }
    return node;
}

@end
