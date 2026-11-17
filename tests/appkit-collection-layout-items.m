#import "appkit-collection-layout.h"

// NSCollectionLayoutItem and NSCollectionLayoutSupplementaryItem (NSCollectionViewCompositionalLayout.h, macOS 10.15),
// which Notes, Podcasts and Activity Monitor build on.

int main(void) {
    @autoreleasepool {
        Class itemClass = NSClassFromString(@"NSCollectionLayoutItem");
        Class supplementaryClass = NSClassFromString(@"NSCollectionLayoutSupplementaryItem");
        Class sizeClass = NSClassFromString(@"NSCollectionLayoutSize");
        Class dimensionClass = NSClassFromString(@"NSCollectionLayoutDimension");
        Class anchorClass = NSClassFromString(@"NSCollectionLayoutAnchor");
        Class spacingClass = NSClassFromString(@"NSCollectionLayoutSpacing");
        Class edgeClass = NSClassFromString(@"NSCollectionLayoutEdgeSpacing");
        expect(itemClass && supplementaryClass, @"the item classes exist");
        expectFromCollectionViewCore(itemClass);
        expectFromCollectionViewCore(supplementaryClass);
        expect([supplementaryClass isSubclassOfClass: itemClass], @"a supplementary item is an item");

        NSCollectionLayoutSize *size = [sizeClass sizeWithWidthDimension: [dimensionClass fractionalWidthDimension: 1.0]
                                                         heightDimension: [dimensionClass absoluteDimension: 30]];

        NSCollectionLayoutItem *item = [itemClass itemWithLayoutSize: size];
        expect(sameSize([item layoutSize], size), @"the item keeps its layout size");
        expect([[item supplementaryItems] isEqual: @[]], @"an item made without supplementary items has an empty array");
        NSCollectionLayoutItem *nilSupplementary = [itemClass itemWithLayoutSize: size supplementaryItems: nil];
        expect(nilSupplementary != nil && [nilSupplementary supplementaryItems] == nil,
               @"quirk: nil supplementary items for the factory are stored as nil, no exception (macOS 26.7.3)");
        NSDirectionalEdgeInsets zero = [item contentInsets];
        expect(zero.top == 0 && zero.leading == 0 && zero.bottom == 0 && zero.trailing == 0, @"content insets start at zero");
        NSCollectionLayoutEdgeSpacing *startSpacing = [item edgeSpacing];
        expect(startSpacing != nil && [[startSpacing leading] isFixedSpacing] && [[startSpacing leading] spacing] == 0 &&
                       [[startSpacing top] spacing] == 0 && [[startSpacing trailing] spacing] == 0 && [[startSpacing bottom] spacing] == 0 &&
                       [[startSpacing bottom] isFixedSpacing],
               @"quirk: edge spacing starts as fixed zero spacing on every edge (macOS 26.7.3)");

        [item setContentInsets: NSDirectionalEdgeInsetsMake(1, 2, 3, 4)];
        NSDirectionalEdgeInsets insets = [item contentInsets];
        expect(insets.top == 1 && insets.leading == 2 && insets.bottom == 3 && insets.trailing == 4, @"content insets round-trip");
        NSCollectionLayoutEdgeSpacing *spacing = [edgeClass spacingForLeading: [spacingClass fixedSpacing: 5] top: nil trailing: nil bottom: nil];
        [item setEdgeSpacing: spacing];
        expect([[[item edgeSpacing] leading] spacing] == 5, @"edge spacing round-trips");

        NSCollectionLayoutItem *itemCopy = [[item copy] autorelease];
        expect([itemCopy isMemberOfClass: itemClass] && itemCopy != item, @"an item copies to a new item of its class");
        expect(sameSize([itemCopy layoutSize], size) && [itemCopy contentInsets].trailing == 4 && [[[itemCopy edgeSpacing] leading] spacing] == 5,
               @"the copy keeps the size, insets and edge spacing");
        [itemCopy setContentInsets: NSDirectionalEdgeInsetsMake(9, 9, 9, 9)];
        expect([item contentInsets].top == 1, @"changing the copy leaves the original alone");

        NSCollectionLayoutAnchor *container = [anchorClass layoutAnchorWithEdges: NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing
                                                                  fractionalOffset: NSMakePoint(0.5, -0.5)];
        NSCollectionLayoutAnchor *own = [anchorClass layoutAnchorWithEdges: NSDirectionalRectEdgeBottom];
        NSCollectionLayoutSupplementaryItem *badge = [supplementaryClass supplementaryItemWithLayoutSize: size
                                                                                             elementKind: @"badge"
                                                                                         containerAnchor: container
                                                                                              itemAnchor: own];
        expect([[badge elementKind] isEqualToString: @"badge"], @"the supplementary item keeps its element kind");
        expect([badge containerAnchor] == container && [badge itemAnchor] == own, @"it keeps both anchors");
        expect(sameSize([badge layoutSize], size) && [[badge supplementaryItems] count] == 0, @"it keeps its layout size and has no supplementary items");
        NSCollectionLayoutSupplementaryItem *bare = [supplementaryClass supplementaryItemWithLayoutSize: size elementKind: @"bare" containerAnchor: container];
        expect([bare itemAnchor] == nil, @"an item anchor not given is nil");
        expect([bare zIndex] == 1, @"quirk: a supplementary item starts with z index 1 (macOS 26.7.3)");
        [badge setZIndex: 7];
        NSCollectionLayoutSupplementaryItem *badgeCopy = [[badge copy] autorelease];
        expect([badgeCopy zIndex] == 7 && [[badgeCopy elementKind] isEqualToString: @"badge"] && [badgeCopy itemAnchor] == own &&
                       [badgeCopy isMemberOfClass: supplementaryClass],
               @"a supplementary item's copy keeps the z index, element kind and anchors");

        NSCollectionLayoutItem *host = [itemClass itemWithLayoutSize: size supplementaryItems: @[badge]];
        expect([[host supplementaryItems] isEqual: @[badge]], @"an item keeps the supplementary items it was made with");
        NSCollectionLayoutItem *hostCopy = [[host copy] autorelease];
        expect([[hostCopy supplementaryItems] isEqual: @[badge]], @"an item's copy keeps its supplementary items");

    }
    printf("PASS: collection layout items and supplementary items\n");
    return 0;
}
