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

// The Objective-C class behind the Swift NSDiffableDataSourceSnapshotReference (macOS 10.15). The members are the ones
// Apple's documentation lists. How it treats misuse is not in the public documentation (it documents only that an
// unknown section in numberOfItemsInSection: throws), so GUESS: a duplicate identifier, or an anchor, section or
// item that is not in the snapshot, raises NSInvalidArgumentException; a lookup that returns "not found" in the
// documentation (indexOf..., sectionIdentifierForSectionContainingItemIdentifier:) does not raise.

#import <Foundation/Foundation.h>

NS_SWIFT_NAME(NSDiffableDataSourceSnapshotReference)
@interface NSDiffableDataSourceSnapshot : NSObject <NSCopying> {
@private
    // Storage, see the implementation. Declared here because the 32-bit runtime has no ivars in @implementation.
    NSMutableArray *_sections;
    NSMutableArray *_items;
    NSMutableArray *_reloadedSections;
    NSMutableArray *_reloadedItems;
}

@property(readonly) NSInteger numberOfItems;
@property(readonly) NSInteger numberOfSections;
@property(readonly, copy) NSArray *sectionIdentifiers;
@property(readonly, copy) NSArray *itemIdentifiers;

- (NSInteger) numberOfItemsInSection: (id) sectionIdentifier;
- (NSArray *) itemIdentifiersInSectionWithIdentifier: (id) sectionIdentifier;
- (NSInteger) indexOfItemIdentifier: (id) itemIdentifier;
- (NSInteger) indexOfSectionIdentifier: (id) sectionIdentifier;
- (id) sectionIdentifierForSectionContainingItemIdentifier: (id) itemIdentifier;

- (void) appendSectionsWithIdentifiers: (NSArray *) sectionIdentifiers;
- (void) appendItemsWithIdentifiers: (NSArray *) identifiers;
- (void) appendItemsWithIdentifiers: (NSArray *) identifiers intoSectionWithIdentifier: (id) sectionIdentifier;
- (void) insertSectionsWithIdentifiers: (NSArray *) sectionIdentifiers beforeSectionWithIdentifier: (id) toSectionIdentifier;
- (void) insertSectionsWithIdentifiers: (NSArray *) sectionIdentifiers afterSectionWithIdentifier: (id) toSectionIdentifier;
- (void) insertItemsWithIdentifiers: (NSArray *) identifiers beforeItemWithIdentifier: (id) itemIdentifier;
- (void) insertItemsWithIdentifiers: (NSArray *) identifiers afterItemWithIdentifier: (id) itemIdentifier;

- (void) deleteSectionsWithIdentifiers: (NSArray *) sectionIdentifiers;
- (void) deleteItemsWithIdentifiers: (NSArray *) identifiers;
- (void) deleteAllItems;

- (void) moveSectionWithIdentifier: (id) fromSectionIdentifier beforeSectionWithIdentifier: (id) toSectionIdentifier;
- (void) moveSectionWithIdentifier: (id) fromSectionIdentifier afterSectionWithIdentifier: (id) toSectionIdentifier;
- (void) moveItemWithIdentifier: (id) fromIdentifier beforeItemWithIdentifier: (id) toIdentifier;
- (void) moveItemWithIdentifier: (id) fromIdentifier afterItemWithIdentifier: (id) toIdentifier;

- (void) reloadSectionsWithIdentifiers: (NSArray *) sectionIdentifiers;
- (void) reloadItemsWithIdentifiers: (NSArray *) identifiers;

@end

// GUESS (not in the public documentation): reloadSections/reloadItems only mark identifiers. No data source in this
// tree applies a snapshot yet, so the marks are read through these two accessors by whoever adds one.
@interface NSDiffableDataSourceSnapshot (ReloadMarks)
@property(readonly, copy) NSArray *reloadedSectionIdentifiers;
@property(readonly, copy) NSArray *reloadedItemIdentifiers;
@end
