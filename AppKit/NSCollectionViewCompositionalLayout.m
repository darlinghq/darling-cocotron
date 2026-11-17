/*
 This file is part of Darling.

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

#import <AppKit/NSCollectionViewCompositionalLayout.h>

// The compositional layout classes AppKit defines. The NSCollectionLayout* classes they hold come from
// CollectionViewCore: this file uses only their public methods, never their instance variables, because on a
// dyld-cache stage they are the cache's classes.

@implementation NSCollectionViewCompositionalLayoutConfiguration

- (NSCollectionViewScrollDirection) scrollDirection {
    return _scrollDirection;
}

- (void) setScrollDirection: (NSCollectionViewScrollDirection) scrollDirection {
    _scrollDirection = scrollDirection;
}

- (CGFloat) interSectionSpacing {
    return _interSectionSpacing;
}

- (void) setInterSectionSpacing: (CGFloat) interSectionSpacing {
    _interSectionSpacing = interSectionSpacing;
}

- (NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *) boundarySupplementaryItems {
    return _boundarySupplementaryItems;
}

// QUIRK: setting nil does not raise and leaves the property nil, which is also its value on a new configuration. Not
// documented. Evidence: black-box observation on macOS 26.7.3 and 27.0.1 (tier 2).
// Test: tests/appkit-collection-view-compositional-layout.m ("quirk: nil boundary items ...").
- (void) setBoundarySupplementaryItems: (NSArray<NSCollectionLayoutBoundarySupplementaryItem *> *) items {
    items = [items copy];
    [_boundarySupplementaryItems release];
    _boundarySupplementaryItems = items;
}

- (void) dealloc {
    [_boundarySupplementaryItems release];
    [super dealloc];
}

- (id) copyWithZone: (NSZone *) zone {
    NSCollectionViewCompositionalLayoutConfiguration *copy = [[[self class] allocWithZone: zone] init];

    copy->_scrollDirection = _scrollDirection;
    copy->_interSectionSpacing = _interSectionSpacing;
    [copy setBoundarySupplementaryItems: _boundarySupplementaryItems];
    return copy;
}

@end

@implementation NSCollectionViewCompositionalLayout

- (instancetype) initWithSection: (NSCollectionLayoutSection *) section {
    return [self initWithSection: section configuration: nil];
}

// A layout always has a configuration; one not given is a default one.
- (instancetype) initWithSection: (NSCollectionLayoutSection *) section
                   configuration: (NSCollectionViewCompositionalLayoutConfiguration *) configuration {
    if ((self = [super init]) != nil) {
        _section = [section retain];
        _configuration = configuration != nil
                ? [configuration copy]
                : [[NSCollectionViewCompositionalLayoutConfiguration alloc] init];
    }
    return self;
}

- (instancetype) initWithSectionProvider: (NSCollectionViewCompositionalLayoutSectionProvider) sectionProvider {
    return [self initWithSectionProvider: sectionProvider configuration: nil];
}

- (instancetype) initWithSectionProvider: (NSCollectionViewCompositionalLayoutSectionProvider) sectionProvider
                           configuration: (NSCollectionViewCompositionalLayoutConfiguration *) configuration {
    if ((self = [super init]) != nil) {
        _sectionProvider = [sectionProvider copy];
        _configuration = configuration != nil
                ? [configuration copy]
                : [[NSCollectionViewCompositionalLayoutConfiguration alloc] init];
    }
    return self;
}

- (NSCollectionViewCompositionalLayoutConfiguration *) configuration {
    return _configuration;
}

- (void) setConfiguration: (NSCollectionViewCompositionalLayoutConfiguration *) configuration {
    configuration = [configuration copy];
    [_configuration release];
    _configuration = configuration;
}

- (void) dealloc {
    [_section release];
    [_sectionProvider release];
    [_configuration release];
    [super dealloc];
}

@end
