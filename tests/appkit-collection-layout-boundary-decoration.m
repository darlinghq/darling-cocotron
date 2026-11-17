#import "appkit-collection-layout.h"

// NSCollectionLayoutBoundarySupplementaryItem and NSCollectionLayoutDecorationItem
// (NSCollectionViewCompositionalLayout.h, macOS 10.15). Notes, Podcasts and Activity Monitor build these.

int main(void) {
    @autoreleasepool {
        Class itemClass = NSClassFromString(@"NSCollectionLayoutItem");
        Class supplementaryClass = NSClassFromString(@"NSCollectionLayoutSupplementaryItem");
        Class boundaryClass = NSClassFromString(@"NSCollectionLayoutBoundarySupplementaryItem");
        Class decorationClass = NSClassFromString(@"NSCollectionLayoutDecorationItem");
        Class sizeClass = NSClassFromString(@"NSCollectionLayoutSize");
        Class dimensionClass = NSClassFromString(@"NSCollectionLayoutDimension");
        expect(boundaryClass && decorationClass, @"the boundary and decoration classes exist");
        expectFromCollectionViewCore(boundaryClass);
        expectFromCollectionViewCore(decorationClass);
        expect([boundaryClass isSubclassOfClass: supplementaryClass], @"a boundary supplementary item is a supplementary item");
        expect([decorationClass isSubclassOfClass: itemClass], @"a decoration item is an item");

        NSCollectionLayoutSize *size = [sizeClass sizeWithWidthDimension: [dimensionClass fractionalWidthDimension: 1.0]
                                                         heightDimension: [dimensionClass absoluteDimension: 30]];

        NSCollectionLayoutBoundarySupplementaryItem *header = [boundaryClass boundarySupplementaryItemWithLayoutSize: size
                                                                                                         elementKind: @"header"
                                                                                                           alignment: NSRectAlignmentTop];
        expect([header alignment] == NSRectAlignmentTop, @"the boundary item keeps its alignment");
        // The raw values, as the public SDK header and macOS 26.7.3 have them.
        expect(NSRectAlignmentNone == 0 && NSRectAlignmentTop == 1 && NSRectAlignmentTopLeading == 2 && NSRectAlignmentLeading == 3 &&
                       NSRectAlignmentBottomLeading == 4 && NSRectAlignmentBottom == 5 && NSRectAlignmentBottomTrailing == 6 &&
                       NSRectAlignmentTrailing == 7 && NSRectAlignmentTopTrailing == 8,
               @"the alignment raw values");
        expect(NSDirectionalRectEdgeNone == 0 && NSDirectionalRectEdgeTop == 1 && NSDirectionalRectEdgeLeading == 2 &&
                       NSDirectionalRectEdgeBottom == 4 && NSDirectionalRectEdgeTrailing == 8 && NSDirectionalRectEdgeAll == 15,
               @"the directional edge raw values");
        expect(NSCollectionElementCategoryItem == 0 && NSCollectionElementCategorySupplementaryView == 1 &&
                       NSCollectionElementCategoryDecorationView == 2 && NSCollectionElementCategoryInterItemGap == 3,
               @"the element category raw values");
        expect(NSCollectionLayoutSectionOrthogonalScrollingBehaviorNone == 0 && NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuous == 1 &&
                       NSCollectionLayoutSectionOrthogonalScrollingBehaviorContinuousGroupLeadingBoundary == 2 &&
                       NSCollectionLayoutSectionOrthogonalScrollingBehaviorPaging == 3 &&
                       NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPaging == 4 &&
                       NSCollectionLayoutSectionOrthogonalScrollingBehaviorGroupPagingCentered == 5,
               @"the orthogonal scrolling behavior raw values");
        expect([header offset].x == 0 && [header offset].y == 0, @"its offset defaults to zero");
        expect([[header elementKind] isEqualToString: @"header"] && sameSize([header layoutSize], size), @"it keeps the element kind and size");
        expect([header containerAnchor] == nil && [header itemAnchor] == nil,
               @"quirk: a boundary item has no container anchor and no item anchor (macOS 26.7.3)");
        expect([header extendsBoundary] && ![header pinToVisibleBounds], @"it extends the boundary and is not pinned by default");
        expect([header zIndex] == 1, @"quirk: a boundary item starts with z index 1 (macOS 26.7.3)");

        // Every alignment gives the same defaults and no anchor.
        const struct { NSRectAlignment alignment; NSDirectionalRectEdge edges; const char *name; } anchors[] = {
            {NSRectAlignmentNone, NSDirectionalRectEdgeNone, "none"},
            {NSRectAlignmentTop, NSDirectionalRectEdgeTop, "top"},
            {NSRectAlignmentTopLeading, NSDirectionalRectEdgeTop | NSDirectionalRectEdgeLeading, "top leading"},
            {NSRectAlignmentLeading, NSDirectionalRectEdgeLeading, "leading"},
            {NSRectAlignmentBottomLeading, NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeLeading, "bottom leading"},
            {NSRectAlignmentBottom, NSDirectionalRectEdgeBottom, "bottom"},
            {NSRectAlignmentBottomTrailing, NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing, "bottom trailing"},
            {NSRectAlignmentTrailing, NSDirectionalRectEdgeTrailing, "trailing"},
            {NSRectAlignmentTopTrailing, NSDirectionalRectEdgeTop | NSDirectionalRectEdgeTrailing, "top trailing"},
        };
        for (size_t i = 0; i < sizeof(anchors) / sizeof(anchors[0]); i++) {
            NSCollectionLayoutBoundarySupplementaryItem *aligned = [boundaryClass boundarySupplementaryItemWithLayoutSize: size
                                                                                                              elementKind: @"kind"
                                                                                                                alignment: anchors[i].alignment];
            expect([aligned containerAnchor] == nil && [aligned itemAnchor] == nil && [aligned alignment] == anchors[i].alignment &&
                           [aligned extendsBoundary] && ![aligned pinToVisibleBounds] && [aligned zIndex] == 1,
                   [NSString stringWithFormat: @"quirk: the %s alignment gives no anchors, extends the boundary, is not pinned (macOS 26.7.3)", anchors[i].name]);
        }
        [header setPinToVisibleBounds: YES];
        [header setExtendsBoundary: NO];
        [header setZIndex: 3];
        NSCollectionLayoutBoundarySupplementaryItem *headerCopy = [[header copy] autorelease];
        expect([headerCopy isMemberOfClass: boundaryClass] && [headerCopy pinToVisibleBounds] && ![headerCopy extendsBoundary] &&
                       [headerCopy zIndex] == 3 && [headerCopy alignment] == NSRectAlignmentTop,
               @"a boundary item's copy keeps its flags, z index and alignment");

        NSCollectionLayoutBoundarySupplementaryItem *footer = [boundaryClass boundarySupplementaryItemWithLayoutSize: size
                                                                                                         elementKind: @"footer"
                                                                                                           alignment: NSRectAlignmentBottomTrailing
                                                                                                      absoluteOffset: NSMakePoint(3, -4)];
        expect([footer alignment] == NSRectAlignmentBottomTrailing && [footer offset].x == 3 && [footer offset].y == -4,
               @"the boundary item keeps its offset");
        expect([footer containerAnchor] == nil, @"quirk: an offset does not give a boundary item a container anchor (macOS 26.7.3)");

        NSCollectionLayoutDecorationItem *background = [decorationClass backgroundDecorationItemWithElementKind: @"background"];
        expect([[background elementKind] isEqualToString: @"background"] && [background zIndex] == 0, @"a decoration item keeps its element kind; z index 0");
        NSCollectionLayoutDimension *backgroundWidth = [[background layoutSize] widthDimension];
        NSCollectionLayoutDimension *backgroundHeight = [[background layoutSize] heightDimension];
        expect([backgroundWidth isFractionalWidth] && [backgroundWidth dimension] == 1.0 && [backgroundHeight isFractionalHeight] &&
                       [backgroundHeight dimension] == 1.0,
               @"quirk: a background decoration item is the full width and height of its container (macOS 26.7.3)");
        NSDirectionalEdgeInsets backgroundInsets = [background contentInsets];
        expect(backgroundInsets.top == 0 && backgroundInsets.leading == 0 && backgroundInsets.bottom == 0 && backgroundInsets.trailing == 0 &&
                       [background edgeSpacing] == nil,
               @"quirk: a background decoration item has no insets and no edge spacing (macOS 26.7.3)");
        [background setZIndex: -1];
        expect([[[background copy] autorelease] zIndex] == -1, @"a decoration item's copy keeps the z index");
    }
    printf("PASS: collection layout boundary and decoration items\n");
    return 0;
}
