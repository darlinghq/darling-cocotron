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
#import <Foundation/NSIndexPath.h>

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
