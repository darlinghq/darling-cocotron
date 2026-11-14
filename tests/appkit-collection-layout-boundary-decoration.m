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
        expect(NSRectAlignmentTopLeading == 2 && NSRectAlignmentTopTrailing == 8, @"the alignment values follow the header's order");
        expect([header offset].x == 0 && [header offset].y == 0, @"its offset defaults to zero");
        expect([[header elementKind] isEqualToString: @"header"] && [header layoutSize] == size, @"it keeps the element kind and size");
        expect([header containerAnchor] != nil && [[header containerAnchor] edges] == NSDirectionalRectEdgeTop,
               @"its container anchor is the alignment's edge");
        expect(![header pinToVisibleBounds], @"it is not pinned by default");

        // Every alignment anchors the boundary item to the edges the alignment names.
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
            expect([[aligned containerAnchor] edges] == anchors[i].edges,
                   [NSString stringWithFormat: @"the %s alignment anchors to its own edges", anchors[i].name]);
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
        expect([[footer containerAnchor] edges] == (NSDirectionalRectEdgeBottom | NSDirectionalRectEdgeTrailing), @"a corner alignment anchors to two edges");

        NSCollectionLayoutDecorationItem *background = [decorationClass backgroundDecorationItemWithElementKind: @"background"];
        expect([[background elementKind] isEqualToString: @"background"] && [background zIndex] == 0, @"a decoration item keeps its element kind; z index 0");
        expect([background layoutSize] != nil, @"a decoration item has a layout size");
        [background setZIndex: -1];
        expect([[[background copy] autorelease] zIndex] == -1, @"a decoration item's copy keeps the z index");
    }
    printf("PASS: collection layout boundary and decoration items\n");
    return 0;
}
