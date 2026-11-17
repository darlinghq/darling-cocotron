/*
 This file is part of Darling.

 Copyright (C) 2026 Darling developers

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

#import <AppKit/NSDiffableDataSourceSnapshot.h>

// Storage: two parallel arrays, the section identifiers in order and, at the same index, that section's item
// identifiers in order. Identifiers are compared with isEqual:, as the Swift snapshot compares Hashable values.
@implementation NSDiffableDataSourceSnapshot

- (instancetype) init {
    if ((self = [super init])) {
        _sections = [NSMutableArray new];
        _items = [NSMutableArray new];
        _reloadedSections = [NSMutableArray new];
        _reloadedItems = [NSMutableArray new];
    }
    return self;
}

- (void) dealloc {
    [_sections release];
    [_items release];
    [_reloadedSections release];
    [_reloadedItems release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *) zone {
    NSDiffableDataSourceSnapshot *copy = [[[self class] allocWithZone: zone] init];
    [copy->_sections addObjectsFromArray: _sections];
    for (NSArray *items in _items) {
        NSMutableArray *itemsCopy = [items mutableCopy];
        [copy->_items addObject: itemsCopy];
        [itemsCopy release];
    }
    [copy->_reloadedSections addObjectsFromArray: _reloadedSections];
    [copy->_reloadedItems addObjectsFromArray: _reloadedItems];
    return copy;
}


- (void) raise: (NSString *) why {
    [NSException raise: NSInvalidArgumentException
                format: @"NSDiffableDataSourceSnapshot: %@ (GUESS: raising is not in the public documentation)", why];
}

// Public reports of the UIKit implementation of the same class name NSInternalInconsistencyException for identifiers that
// are not unique; GUESS (not in the public documentation, not observed on AppKit) that AppKit does the same.
- (void) raiseNotUnique: (NSString *) why {
    [NSException raise: NSInternalInconsistencyException
                format: @"NSDiffableDataSourceSnapshot: %@ (GUESS: raising is not in the public documentation)", why];
}

- (NSInteger) indexOfSectionIdentifier: (id) identifier {
    NSUInteger index = [_sections indexOfObject: identifier];
    return index == NSNotFound ? NSNotFound : (NSInteger) index;
}

- (NSUInteger) sectionIndexOfItem: (id) identifier position: (NSUInteger *) position {
    for (NSUInteger i = 0; i < [_items count]; i++) {
        NSUInteger p = [[_items objectAtIndex: i] indexOfObject: identifier];
        if (p != NSNotFound) {
            if (position) {
                *position = p;
            }
            return i;
        }
    }
    return NSNotFound;
}

- (NSInteger) indexOfItemIdentifier: (id) identifier {
    NSInteger index = 0;
    for (NSArray *items in _items) {
        NSUInteger p = [items indexOfObject: identifier];
        if (p != NSNotFound) {
            return index + (NSInteger) p;
        }
        index += [items count];
    }
    return NSNotFound;
}

- (id) sectionIdentifierForSectionContainingItemIdentifier: (id) identifier {
    NSUInteger section = [self sectionIndexOfItem: identifier position: NULL];
    return section == NSNotFound ? nil : [_sections objectAtIndex: section];
}

- (NSUInteger) existingSectionIndex: (id) identifier {
    NSUInteger index = identifier ? [_sections indexOfObject: identifier] : NSNotFound;
    if (index == NSNotFound) {
        [self raise: [NSString stringWithFormat: @"section identifier %@ is not in the snapshot", identifier]];
    }
    return index;
}

- (NSUInteger) existingItemSection: (id) identifier position: (NSUInteger *) position {
    NSUInteger section = identifier ? [self sectionIndexOfItem: identifier position: position] : NSNotFound;
    if (section == NSNotFound) {
        [self raise: [NSString stringWithFormat: @"item identifier %@ is not in the snapshot", identifier]];
    }
    return section;
}

// New identifiers must be unique among themselves and absent from the snapshot.
- (void) checkNewSections: (NSArray *) identifiers {
    NSMutableArray *seen = [NSMutableArray array];
    for (id identifier in identifiers) {
        if ([_sections containsObject: identifier] || [seen containsObject: identifier]) {
            [self raiseNotUnique: [NSString stringWithFormat: @"section identifier %@ is already in the snapshot", identifier]];
        }
        [seen addObject: identifier];
    }
}

- (void) checkNewItems: (NSArray *) identifiers {
    NSMutableArray *seen = [NSMutableArray array];
    for (id identifier in identifiers) {
        if ([self sectionIndexOfItem: identifier position: NULL] != NSNotFound || [seen containsObject: identifier]) {
            [self raiseNotUnique: [NSString stringWithFormat: @"item identifier %@ is already in the snapshot", identifier]];
        }
        [seen addObject: identifier];
    }
}


- (NSInteger) numberOfSections {
    return [_sections count];
}

- (NSInteger) numberOfItems {
    NSInteger count = 0;
    for (NSArray *items in _items) {
        count += [items count];
    }
    return count;
}

- (NSArray *) sectionIdentifiers {
    return [[_sections copy] autorelease];
}

- (NSArray *) itemIdentifiers {
    NSMutableArray *all = [NSMutableArray array];
    for (NSArray *items in _items) {
        [all addObjectsFromArray: items];
    }
    return all;
}

- (NSInteger) numberOfItemsInSection: (id) sectionIdentifier {
    return [[_items objectAtIndex: [self existingSectionIndex: sectionIdentifier]] count];
}

- (NSArray *) itemIdentifiersInSectionWithIdentifier: (id) sectionIdentifier {
    return [[[_items objectAtIndex: [self existingSectionIndex: sectionIdentifier]] copy] autorelease];
}


- (void) insertSections: (NSArray *) identifiers atIndex: (NSUInteger) index {
    NSIndexSet *at = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(index, [identifiers count])];
    NSMutableArray *empty = [NSMutableArray array];
    for (NSUInteger i = 0; i < [identifiers count]; i++) {
        [empty addObject: [NSMutableArray array]];
    }
    [_sections insertObjects: identifiers atIndexes: at];
    [_items insertObjects: empty atIndexes: at];
}

- (void) appendSectionsWithIdentifiers: (NSArray *) identifiers {
    [self checkNewSections: identifiers];
    [self insertSections: identifiers atIndex: [_sections count]];
}

- (void) insertSectionsWithIdentifiers: (NSArray *) identifiers beforeSectionWithIdentifier: (id) anchor {
    NSUInteger index = [self existingSectionIndex: anchor];
    [self checkNewSections: identifiers];
    [self insertSections: identifiers atIndex: index];
}

- (void) insertSectionsWithIdentifiers: (NSArray *) identifiers afterSectionWithIdentifier: (id) anchor {
    NSUInteger index = [self existingSectionIndex: anchor];
    [self checkNewSections: identifiers];
    [self insertSections: identifiers atIndex: index + 1];
}

// Validate everything first so that a call with an absent identifier changes nothing.
- (void) deleteSectionsWithIdentifiers: (NSArray *) identifiers {
    for (id identifier in identifiers) {
        [self existingSectionIndex: identifier];
    }
    for (id identifier in identifiers) {
        NSUInteger index = [_sections indexOfObject: identifier];
        if (index == NSNotFound) {
            continue;
        }
        [_reloadedItems removeObjectsInArray: [_items objectAtIndex: index]];
        [_sections removeObjectAtIndex: index];
        [_items removeObjectAtIndex: index];
        [_reloadedSections removeObject: identifier];
    }
}

- (void) moveSection: (id) identifier to: (id) anchor offset: (NSUInteger) offset {
    NSUInteger from = [self existingSectionIndex: identifier];
    [self existingSectionIndex: anchor];
    if ([identifier isEqual: anchor]) {
        [self raise: @"a section cannot be moved relative to itself"];
    }
    id items = [[_items objectAtIndex: from] retain];
    [_sections removeObjectAtIndex: from];
    [_items removeObjectAtIndex: from];
    NSUInteger to = [self existingSectionIndex: anchor] + offset;
    [_sections insertObject: identifier atIndex: to];
    [_items insertObject: items atIndex: to];
    [items release];
}

- (void) moveSectionWithIdentifier: (id) identifier beforeSectionWithIdentifier: (id) anchor {
    [self moveSection: identifier to: anchor offset: 0];
}

- (void) moveSectionWithIdentifier: (id) identifier afterSectionWithIdentifier: (id) anchor {
    [self moveSection: identifier to: anchor offset: 1];
}

- (void) reloadSectionsWithIdentifiers: (NSArray *) identifiers {
    for (id identifier in identifiers) {
        [self existingSectionIndex: identifier];
    }
    for (id identifier in identifiers) {
        if (![_reloadedSections containsObject: identifier]) {
            [_reloadedSections addObject: identifier];
        }
    }
}

- (void) appendItemsWithIdentifiers: (NSArray *) identifiers {
    if (![_sections count]) {
        [self raise: @"there is no section to append items to"];
    }
    [self checkNewItems: identifiers];
    [[_items lastObject] addObjectsFromArray: identifiers];
}

- (void) appendItemsWithIdentifiers: (NSArray *) identifiers intoSectionWithIdentifier: (id) sectionIdentifier {
    NSUInteger section = [self existingSectionIndex: sectionIdentifier];
    [self checkNewItems: identifiers];
    [[_items objectAtIndex: section] addObjectsFromArray: identifiers];
}

- (void) insertItems: (NSArray *) identifiers relativeTo: (id) anchor offset: (NSUInteger) offset {
    NSUInteger position;
    NSUInteger section = [self existingItemSection: anchor position: &position];
    [self checkNewItems: identifiers];
    NSIndexSet *at = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(position + offset, [identifiers count])];
    [[_items objectAtIndex: section] insertObjects: identifiers atIndexes: at];
}

- (void) insertItemsWithIdentifiers: (NSArray *) identifiers beforeItemWithIdentifier: (id) anchor {
    [self insertItems: identifiers relativeTo: anchor offset: 0];
}

- (void) insertItemsWithIdentifiers: (NSArray *) identifiers afterItemWithIdentifier: (id) anchor {
    [self insertItems: identifiers relativeTo: anchor offset: 1];
}

- (void) deleteItemsWithIdentifiers: (NSArray *) identifiers {
    for (id identifier in identifiers) {
        [self existingItemSection: identifier position: NULL];
    }
    for (id identifier in identifiers) {
        NSUInteger position;
        NSUInteger section = [self sectionIndexOfItem: identifier position: &position];
        if (section == NSNotFound) {
            continue;
        }
        [[_items objectAtIndex: section] removeObjectAtIndex: position];
        [_reloadedItems removeObject: identifier];
    }
}

// The sections stay, empty (GUESS: the documentation does not say whether sections survive).
- (void) deleteAllItems {
    for (NSMutableArray *items in _items) {
        [items removeAllObjects];
    }
    [_reloadedItems removeAllObjects];
}

- (void) moveItem: (id) identifier to: (id) anchor offset: (NSUInteger) offset {
    NSUInteger position;
    NSUInteger section = [self existingItemSection: identifier position: &position];
    [self existingItemSection: anchor position: NULL];
    if ([identifier isEqual: anchor]) {
        [self raise: @"an item cannot be moved relative to itself"];
    }
    [[identifier retain] autorelease];
    [[_items objectAtIndex: section] removeObjectAtIndex: position];
    NSUInteger toPosition;
    NSUInteger toSection = [self existingItemSection: anchor position: &toPosition];
    [[_items objectAtIndex: toSection] insertObject: identifier atIndex: toPosition + offset];
}

- (void) moveItemWithIdentifier: (id) identifier beforeItemWithIdentifier: (id) anchor {
    [self moveItem: identifier to: anchor offset: 0];
}

- (void) moveItemWithIdentifier: (id) identifier afterItemWithIdentifier: (id) anchor {
    [self moveItem: identifier to: anchor offset: 1];
}

- (void) reloadItemsWithIdentifiers: (NSArray *) identifiers {
    for (id identifier in identifiers) {
        [self existingItemSection: identifier position: NULL];
    }
    for (id identifier in identifiers) {
        if (![_reloadedItems containsObject: identifier]) {
            [_reloadedItems addObject: identifier];
        }
    }
}

- (NSArray *) reloadedSectionIdentifiers {
    return [[_reloadedSections copy] autorelease];
}

- (NSArray *) reloadedItemIdentifiers {
    return [[_reloadedItems copy] autorelease];
}

@end
